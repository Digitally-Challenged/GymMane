import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
} from "node:crypto";
export const stateDigest = (state: string) =>
  createHash("sha256").update(state).digest("hex");
export interface Tokens {
  access_token: string;
  refresh_token: string;
  expires_at: number;
}
export function validTokens(value: unknown): value is Tokens {
  const t = value as Tokens | null;
  return (
    !!t &&
    typeof t.access_token === "string" &&
    t.access_token.length > 0 &&
    typeof t.refresh_token === "string" &&
    t.refresh_token.length > 0 &&
    Number.isSafeInteger(t.expires_at)
  );
}
export class TokenCipher {
  private key: Buffer;
  constructor(key: string) {
    this.key = Buffer.from(key, "base64");
    if (this.key.length !== 32 || this.key.toString("base64") !== key)
      throw new Error(
        "STRAVA_TOKEN_KEY must be canonical base64 of 32 random bytes",
      );
  }
  seal(tokens: Tokens, account: string): string {
    const iv = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", this.key, iv);
    cipher.setAAD(Buffer.from(account));
    const data = Buffer.concat([
      cipher.update(JSON.stringify(tokens)),
      cipher.final(),
    ]);
    return [iv, cipher.getAuthTag(), data]
      .map((b) => b.toString("base64"))
      .join(".");
  }
  open(value: string, account: string): Tokens {
    const parts = value.split(".").map((s) => Buffer.from(s, "base64"));
    if (parts.length !== 3) throw new Error("Invalid encrypted token");
    const cipher = createDecipheriv("aes-256-gcm", this.key, parts[0]);
    cipher.setAAD(Buffer.from(account));
    cipher.setAuthTag(parts[1]);
    const tokens: unknown = JSON.parse(
      Buffer.concat([cipher.update(parts[2]), cipher.final()]).toString(),
    );
    if (!validTokens(tokens)) throw new Error("Invalid encrypted token");
    return tokens;
  }
}
