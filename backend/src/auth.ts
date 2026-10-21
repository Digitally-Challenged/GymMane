import { createRemoteJWKSet, jwtVerify, errors } from "jose";
import type { Pool } from "pg";
import { HttpError, uuid } from "./protocol.js";
export interface AuthConfig {
  issuer: string;
  audience: string;
  jwksUrl: string;
}
export function createAuthenticator(config: AuthConfig, pool: Pool) {
  const keys = createRemoteJWKSet(new URL(config.jwksUrl), {
    timeoutDuration: 5000,
  });
  return async (authorization: string | undefined): Promise<string> => {
    if (!authorization?.startsWith("Bearer ") || authorization.length > 16384)
      throw new HttpError(401, "Bearer token required");
    let claims;
    try {
      claims = (
        await jwtVerify(authorization.slice(7), keys, {
          issuer: config.issuer,
          audience: config.audience,
          algorithms: ["RS256", "ES256"],
          requiredClaims: ["sub", "exp", "iat"],
        })
      ).payload;
      if (
        !claims.sub ||
        !uuid.test(claims.sub) ||
        !Number.isSafeInteger(claims.iat) ||
        claims.iat! > Date.now() / 1000 + 30
      )
        throw new HttpError(401, "Invalid subject or issue time");
    } catch (error) {
      if (error instanceof HttpError) throw error;
      if (
        !(error instanceof errors.JOSEError) ||
        ["ERR_JWKS_TIMEOUT", "ERR_JWKS_INVALID", "ERR_JOSE_GENERIC"].includes(
          error.code,
        )
      )
        throw new HttpError(503, "Authentication service unavailable");
      throw new HttpError(401, "Invalid or expired token");
    }
    const accountId = claims.sub.toLowerCase();
    const state = await pool.query(
      "SELECT disabled, tokens_valid_after FROM sync_accounts WHERE account_id=$1",
      [accountId],
    );
    if (state.rows[0]?.disabled) throw new HttpError(403, "Account disabled");
    if (
      state.rows[0] &&
      claims.iat! <= Number(state.rows[0].tokens_valid_after)
    )
      throw new HttpError(401, "Token revoked");
    return accountId;
  };
}
