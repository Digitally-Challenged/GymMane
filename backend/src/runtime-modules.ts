import type { Pool } from "pg";
import type { BackendModule } from "./modules.js";
export interface RuntimeModule {
  register: BackendModule;
  tick: () => Promise<void>;
}
export async function loadRuntimeModules(
  pool: Pool,
  env: NodeJS.ProcessEnv,
): Promise<RuntimeModule[]> {
  if (env.STRAVA_ENABLED !== "true") return [];
  // Optional module is supplied by the Strava owner; enabling without it fails startup.
  const path = "../strava/index.js";
  const implementation = await import(path);
  const module: RuntimeModule = await implementation.createStravaModule(
    pool,
    env,
  );
  if (
    typeof module.register !== "function" ||
    typeof module.tick !== "function"
  )
    throw new Error("Invalid Strava runtime module");
  return [module];
}
export function startModuleJobs(modules: RuntimeModule[], intervalMs = 5000) {
  let stopped = false;
  let pending: Promise<void> | undefined;
  const timer = setInterval(() => {
    if (stopped || pending) return;
    pending = Promise.all(
      modules.map(async (module) => {
        try {
          await module.tick();
        } catch (error) {
          console.error("Module tick failed", {
            name: error instanceof Error ? error.name : "UnknownError",
          });
        }
      }),
    ).then(() => {
      pending = undefined;
    });
  }, intervalMs);
  timer.unref();
  return async () => {
    stopped = true;
    clearInterval(timer);
    await pending;
  };
}
