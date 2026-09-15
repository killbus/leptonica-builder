/**
 * Browser worker session client (design §5.3).
 *
 * The worker entry is resolved through the standard bundler-friendly
 * pattern (new URL + import.meta.url); every major bundler rewrites it
 * at build time to a worker chunk. Node resolves "leptonica-wasm/worker"
 * to the worker_threads adapter through the "node" export condition —
 * the same specifier serves both platforms.
 */
import { WorkerSession } from "./session.js";
import type { SessionOptions } from "./session.js";
/** Create a session backed by a DOM Worker. */
export declare function createSession(opts?: SessionOptions): Promise<WorkerSession>;
export { WorkerSession, RemotePix } from "./session.js";
export type { SessionOptions } from "./session.js";
export type { PackedMask } from "../core/types.js";
