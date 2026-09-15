/**
 * Raw C-ABI escape hatch (design §4.3).
 *
 * Loads the full-abi build (dist/full-abi/) and hands you the C ABI
 * with loose types. This module is documented danger: no semver, no
 * ownership, no validation. Prefer the curated layer unless you need
 * a leptonica function it does not expose.
 */
import { type RawMemory, type RawModule } from "./types.js";
export { rawMemory, type Ptr, type RawFunction, type RawVoidFunction, type RawMemory, type RawModule, type RawSymbolHolder, } from "./types.js";
export interface RawLoadOptions {
    /**
     * The wasm bytes, e.g. read or fetched from dist/full-abi/leptonica.wasm.
     * Required: the heap views exposed on the result need the instance's
     * memory export, which is captured at instantiation time.
     */
    wasmBinary: ArrayBuffer | Uint8Array;
}
export interface RawInstance {
    /** The raw module — every C symbol as a loose function. */
    readonly raw: RawModule;
    /** Heap views tied to this module's memory. */
    readonly memory: RawMemory;
}
/**
 * Instantiate the full-abi wasm build.
 *
 * The -O2 full-abi glue does not expose HEAP views on the module object,
 * so the memory export is captured at instantiation and exposed as heap
 * views on the result (see rawMemory). Views are re-derived per read to
 * survive heap growth (ALLOW_MEMORY_GROWTH).
 */
export declare function loadRaw(options: RawLoadOptions): Promise<RawInstance>;
