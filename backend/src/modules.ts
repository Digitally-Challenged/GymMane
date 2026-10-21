import type { IncomingMessage } from "node:http";
import type { Pool } from "pg";
export interface RouteContext {
  accountId: string;
  request: IncomingMessage;
  url: URL;
  readJson: () => Promise<unknown>;
}
export type RouteHandler = (context: RouteContext) => Promise<unknown>;
export class RouteRegistry {
  private routes = new Map<string, RouteHandler>();
  private callbacks = new Map<
    string,
    (request: IncomingMessage, url: URL) => Promise<string>
  >();
  // OAuth modules must validate and consume one-use state before returning its account.
  publicCallback(
    method: string,
    pathname: string,
    verifyState: (request: IncomingMessage, url: URL) => Promise<string>,
    handler: RouteHandler,
  ) {
    this.authenticated(method, pathname, handler);
    this.callbacks.set(`${method.toUpperCase()} ${pathname}`, verifyState);
  }
  callbackVerifier(method: string, pathname: string) {
    return this.callbacks.get(`${method} ${pathname}`);
  }
  authenticated(method: string, pathname: string, handler: RouteHandler) {
    const key = `${method.toUpperCase()} ${pathname}`;
    if (this.routes.has(key)) throw new Error(`Duplicate route: ${key}`);
    this.routes.set(key, handler);
  }
  get(method: string, pathname: string) {
    return this.routes.get(`${method} ${pathname}`);
  }
}
export type BackendModule = (
  registry: RouteRegistry,
  context: { pool: Pool },
) => void;
