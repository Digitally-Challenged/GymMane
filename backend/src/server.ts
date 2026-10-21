import { createServer, type IncomingMessage } from "node:http";
import type { Pool } from "pg";
import { createAuthenticator, type AuthConfig } from "./auth.js";
import { HttpError, parsePull, parsePush } from "./protocol.js";
import { RouteRegistry, type BackendModule } from "./modules.js";
import { SyncStore } from "./store.js";
const MAX_BODY = 1024 * 1024;
async function readJson(request: IncomingMessage) {
  if (
    request.headers["content-type"]?.split(";")[0].trim() !== "application/json"
  )
    throw new HttpError(400, "Expected application/json");
  if (
    request.headers["content-encoding"] &&
    request.headers["content-encoding"] !== "identity"
  )
    throw new HttpError(400, "Unsupported content encoding");
  let bytes = 0;
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    bytes += chunk.length;
    if (bytes > MAX_BODY) throw new HttpError(413, "Request exceeds 1 MiB");
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown;
  } catch {
    throw new HttpError(400, "Malformed JSON");
  }
}
export function createApp(
  pool: Pool,
  auth: AuthConfig,
  modules: BackendModule[] = [],
  options: { allowedOrigins?: string[] } = {},
) {
  const allowedOrigins = new Set(options.allowedOrigins ?? []);
  for (const origin of allowedOrigins) {
    const parsed = new URL(origin);
    if (
      parsed.origin !== origin ||
      !["http:", "https:"].includes(parsed.protocol)
    )
      throw new Error("CORS requires exact HTTP(S) origins");
  }
  const authenticate = createAuthenticator(auth, pool);
  const store = new SyncStore(pool);
  const registry = new RouteRegistry();
  registry.authenticated(
    "POST",
    "/v1/sync/push",
    async ({ accountId, readJson }) =>
      store.push(accountId, parsePush(await readJson())),
  );
  registry.authenticated("GET", "/v1/sync/pull", async ({ accountId, url }) => {
    const { cursor, limit } = parsePull(url);
    return store.pull(accountId, cursor, limit);
  });
  modules.forEach((module) => module(registry, { pool }));
  const server = createServer(async (request, response) => {
    response.setHeader("Content-Type", "application/json");
    response.setHeader("Cache-Control", "no-store");
    try {
      const url = new URL(request.url ?? "/", "http://localhost");
      const origin = request.headers.origin;
      if (origin) {
        response.setHeader("Vary", "Origin");
        if (!allowedOrigins.has(origin))
          throw new HttpError(403, "Origin not allowed");
        response.setHeader("Access-Control-Allow-Origin", origin);
        if (request.method === "OPTIONS") {
          const method = request.headers["access-control-request-method"] ?? "";
          const headers = (
            request.headers["access-control-request-headers"] ?? ""
          )
            .toLowerCase()
            .split(",")
            .map((h) => h.trim())
            .filter(Boolean);
          if (
            !registry.get(method, url.pathname) ||
            headers.some((h) => !["authorization", "content-type"].includes(h))
          )
            throw new HttpError(403, "Preflight not allowed");
          response.setHeader("Access-Control-Allow-Methods", method);
          response.setHeader(
            "Access-Control-Allow-Headers",
            "Authorization, Content-Type",
          );
          response.statusCode = 204;
          response.end();
          return;
        }
      }
      const handler = registry.get(request.method ?? "", url.pathname);
      if (!handler) throw new HttpError(404, "Route not found");
      const verifyState = registry.callbackVerifier(
        request.method ?? "",
        url.pathname,
      );
      const accountId = verifyState
        ? await verifyState(request, url)
        : await authenticate(request.headers.authorization);
      if (Number(request.headers["content-length"] ?? 0) > MAX_BODY)
        throw new HttpError(413, "Request exceeds 1 MiB");
      const result = await handler({
        accountId,
        request,
        url,
        readJson: () => readJson(request),
      });
      response.end(JSON.stringify(result));
    } catch (error) {
      response.statusCode = error instanceof HttpError ? error.status : 503;
      response.end(
        JSON.stringify({
          error:
            error instanceof HttpError
              ? error.message
              : "Service temporarily unavailable",
        }),
      );
      if (!(error instanceof HttpError))
        console.error("Request failed", {
          name: error instanceof Error ? error.name : "UnknownError",
        });
      request.resume();
    }
  });
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  return server;
}
