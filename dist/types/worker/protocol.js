/**
 * Wire protocol shared by the session client (main thread) and the worker
 * entry (design §5.2 — hand-written, both ends import this file).
 *
 * Large payloads move exclusively as transferred ArrayBuffers: load
 * carries the RGBA bytes up, extract carries the encoded bytes down.
 * Handles never cross the boundary — only their numeric ids.
 */
export {};
