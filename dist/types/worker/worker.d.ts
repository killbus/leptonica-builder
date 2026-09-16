/**
 * The worker entry (design §5.3) — runs INSIDE the worker thread.
 *
 * One Leptonica instance per worker (decision ⑧: Leptonica has global
 * state; one-instance-per-worker is the safety model). The wasm binary
 * is located next to this file by default (new URL + import.meta.url);
 * the session client can override the location via wasmPath, forwarded
 * through the init handshake.
 *
 * The arena (decision ⑭): every Pix created here stays here; close()
 * destroys all of them at once. Intermediates from a failed run() die
 * inside the request handler (design §5.2) — the error path is also a
 * call-stack-local death.
 */
export {};
