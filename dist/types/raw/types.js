/**
 * Raw C-ABI module shape — the escape-hatch layer.
 *
 * DANGER ZONE (no semver, no ownership semantics):
 *
 * - Every "pointer" here is a raw 32-bit wasm address. Nothing checks
 *   that it is alive, of the right type, or that you own it.
 * - Passing a stale or wrong-type pointer is undefined behavior; the
 *   process (worker/Node instance) may corrupt silently.
 * - Ownership is yours: leptonica's refcounting rules (pixDestroy vs
 *   pixClone, lept_free vs free) apply exactly as in C. The curated
 *   layer exists because these rules are easy to get wrong.
 * - No symbol here is part of the public API contract. The leptonica
 *   symbol name IS the API; a dependency bump may change any of it.
 * - Each loadRaw call instantiates a fresh module with its OWN heap.
 *   Pointers are instance-scoped: a Ptr from one instance is meaningless
 *   (silently wrong or crashing) when passed to another instance.
 * - C string parameters (const char*) are raw wasm addresses, not JS
 *   strings. You must _malloc, encode as UTF-8, append a NUL byte, and pass
 *   the pointer. Omitting the NUL terminator reads past your allocation.
 * - Out-params that take a T** (e.g. pixDestroy(PIX **ppix)) expect the
 *   address of a pointer slot: stage the pointer in a _malloc'd slot and
 *   pass the slot address, not the pointer itself.
 */
/**
 * Build RawMemory from a captured WebAssembly.Memory. Views are
 * constructed on read so they stay valid if the heap grows (the views
 * track the current buffer). The per-read construction is O(view
 * creation) — hoist reads out of hot loops rather than indexing
 * through these getters per pixel.
 */
export function rawMemory(memory) {
    return {
        get buffer() {
            return memory.buffer;
        },
        get heapU8() {
            return new Uint8Array(memory.buffer);
        },
        get heap32() {
            return new Int32Array(memory.buffer);
        },
    };
}
