/**
 * Node worker_threads adapter (design §5.3).
 *
 * createSession() must work unchanged in Node and the browser: the
 * browser branch resolves the worker entry through a bundler-friendly
 * new URL(...) pattern, which Node's ESM loader cannot execute as a
 * worker script (it needs a real file URL, and the .TS source form is
 * not loadable at all). This module resolves both paths explicitly
 * against the package layout on disk and bridges worker_threads'
 * message shapes onto the session's postMessage transport.
 */
import { WorkerSession } from "./session.js";
import type { SessionOptions } from "./session.js";
export { WorkerSession, RemotePix } from "./session.js";
export type { SessionOptions } from "./session.js";
export type { PackedMask } from "../core/types.js";
/** Create a session backed by a worker_threads Worker (Node ≥ 20). */
export declare function createSession(opts?: SessionOptions): Promise<WorkerSession>;
