import type { PoolClient } from "pg";
import { TokenCipher, validTokens } from "./crypto.js";
import type { Connection } from "./database.js";
import {
  ProviderError,
  rateLimitUntil,
  responseObject,
  type Transport,
} from "./transport.js";
export interface Config {
  clientId: string;
  clientSecret: string;
  redirectUri: string;
  cipher: TokenCipher;
}
export class Provider {
  constructor(
    readonly config: Config,
    readonly fetch: Transport,
  ) {}
  async request(
    db: PoolClient,
    path: string,
    init: RequestInit,
    beforeFetch?: () => Promise<void>,
  ) {
    const gate = await db.query(
      "SELECT until_at > now() AS paused, until_at FROM strava_throttle WHERE id=true",
    );
    if (gate.rows[0].paused)
      throw new ProviderError(429, gate.rows[0].until_at);
    await beforeFetch?.();
    const response = await this.fetch(`https://www.strava.com${path}`, init);
    const until = rateLimitUntil(response);
    await db.query(
      "UPDATE strava_throttle SET until_at=GREATEST(until_at,$1) WHERE id=true",
      [until],
    );
    if (!response.ok) throw new ProviderError(response.status, until);
    return responseObject(response);
  }
  async tokenRequest(db: PoolClient, fields: Record<string, string>) {
    const body = new URLSearchParams({
      ...fields,
      client_id: this.config.clientId,
      client_secret: this.config.clientSecret,
    });
    const value = await this.request(db, "/oauth/token", {
      method: "POST",
      body,
    });
    if (!validTokens(value)) throw new Error("Invalid token response");
    return value;
  }
  async access(db: PoolClient, c: Connection): Promise<string | null> {
    if (c.status !== "connected" || !c.tokens || c.refresh_pending) {
      if (c.refresh_pending) await this.invalidate(db, c.account_id);
      return null;
    }
    const tokens = this.config.cipher.open(c.tokens, c.account_id);
    if (tokens.expires_at > Math.floor(Date.now() / 1000) + 60)
      return tokens.access_token;
    // Commit intent before rotating: process death or a lost refresh response must
    // never reuse an old refresh token whose replacement may have been issued.
    await db.query(
      "UPDATE strava_connections SET refresh_pending=true WHERE account_id=$1",
      [c.account_id],
    );
    try {
      const next = await this.tokenRequest(db, {
        grant_type: "refresh_token",
        refresh_token: tokens.refresh_token,
      });
      await db.query(
        "UPDATE strava_connections SET tokens=$2,refresh_pending=false WHERE account_id=$1",
        [c.account_id, this.config.cipher.seal(next, c.account_id)],
      );
      return next.access_token;
    } catch (error) {
      if (error instanceof ProviderError && error.status === 429) {
        await db.query(
          "UPDATE strava_connections SET refresh_pending=false WHERE account_id=$1",
          [c.account_id],
        );
        throw error;
      }
      await this.invalidate(db, c.account_id);
      return null;
    }
  }
  async invalidate(db: PoolClient, account: string) {
    await db.query(
      "UPDATE strava_connections SET status='needsAuthorization',tokens=NULL,refresh_pending=false WHERE account_id=$1",
      [account],
    );
    await db.query(
      "UPDATE strava_jobs SET status='needsAuthorization',message='Reconnect Strava; no automatic resend' WHERE account_id=$1 AND status IN ('queued','processing')",
      [account],
    );
  }
}
