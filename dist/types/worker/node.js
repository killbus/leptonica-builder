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
import { existsSync } from "node:fs";
import { Worker } from "node:worker_threads";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { WorkerSession } from "./session.js";
export { WorkerSession, RemotePix } from "./session.js";
/**
 * Locate the worker entry from this file's own location. Two layouts
 * ship the same file:
 *
 *  - published package: dist/types/worker/node.js → sibling
 *    dist/worker.mjs (found by probing upward)
 *  - in-repo source (tests run against src/): src/worker/node.ts →
 *    <repo>/dist/worker.mjs (found by probing into dist/ below a
 *    package.json root)
 *
 * A fixed hop count cannot cover both, so probe upward instead.
 */
function resolveEntry() {
    let dir = dirname(new URL(import.meta.url).pathname);
    for (let i = 0; i < 5; i++) {
        const candidate = join(dir, "worker.mjs");
        if (existsSync(candidate))
            return pathToFileURL(candidate);
        const nested = join(dir, "dist", "worker.mjs");
        if (existsSync(nested))
            return pathToFileURL(nested);
        const next = dirname(dir);
        if (next === dir)
            break;
        dir = next;
    }
    throw new Error("worker entry not found: dist/worker.mjs is missing — run the build first (pnpm run build outputs it into dist/)");
}
/** Create a session backed by a worker_threads Worker (Node ≥ 20). */
export async function createSession(opts = {}) {
    const entry = resolveEntry();
    // .mjs entry → ESM; worker_threads infers module type from the extension.
    const worker = new Worker(entry);
    const session = new WorkerSession((msg, transfer) => {
        worker.postMessage(msg, (transfer ?? []));
    }, (cb) => {
        worker.on("message", (r) => cb(r));
    }, 
    // The arena release is the worker-side half of close(); this is the
    // adapter half — a worker_threads Worker keeps the event loop alive
    // until terminated, so a session whose close() resolved would hang
    // the process without this.
    () => void worker.terminate());
    worker.once("exit", (code) => session.markTerminated(new Error(`worker exited with code ${code}`)));
    worker.once("error", (error) => {
        session.markTerminated(error instanceof Error ? error : new Error(String(error)));
    });
    worker.once("messageerror", (error) => {
        session.markTerminated(error instanceof Error ? error : new Error(String(error)));
    });
    try {
        await session.init(opts.wasmPath);
    }
    catch (err) {
        // Keep initialization failure cleanup on WorkerSession's single,
        // idempotent teardown path. Fatal init responses may already have
        // retired the session before this catch runs.
        session.terminate();
        throw err;
    }
    return session;
}
