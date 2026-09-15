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
/** Create a session backed by a DOM Worker. */
export async function createSession(opts = {}) {
    // The bundler rewrites this to a worker chunk URL at build time.
    // NOTE: the constructor must appear literally as `new Worker(...)` —
    // bundlers (vite) detect exactly that shape to emit a bundled worker
    // chunk. A globalThis.Worker lookup defeats the detection and the
    // entry gets copied as a raw asset instead.
    const domWorker = new Worker(new URL("./worker.mjs", import.meta.url), { type: "module" });
    // Narrow to the postMessage(msg, transfer[]) shape the session uses;
    // the DOM lib types the second argument as StructuredSerializeOptions.
    const worker = domWorker;
    const session = new WorkerSession((msg, transfer) => {
        worker.postMessage(msg, transfer);
    }, (cb) => {
        worker.addEventListener("message", (ev) => cb(ev.data));
    }, 
    // Symmetric with the Node adapter: release the platform worker once
    // the session is dead. DOM Workers are GC-able, but explicit
    // teardown keeps the no-residue contract observable.
    () => worker.terminate());
    worker.addEventListener("error", () => session.markTerminated());
    worker.addEventListener("messageerror", () => session.markTerminated(new Error("worker message deserialization failed")));
    try {
        await session.init(opts.wasmPath);
    }
    catch (err) {
        // Route initialization failures through the session's idempotent
        // retirement gate. A fatal init response has already called the same
        // teardown; terminating the native Worker directly here would do it
        // twice. Ordinary init failures still retire and release it once.
        session.terminate();
        throw err;
    }
    return session;
}
export { WorkerSession, RemotePix } from "./session.js";
