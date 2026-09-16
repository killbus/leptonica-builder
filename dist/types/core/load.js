import { Leptonica } from "./types.js";
/**
 * Instantiate the curated wasm module (default build, dist/leptonica.mjs).
 *
 * Each call creates a fresh module with its own heap. Handles are
 * instance-scoped — never mix Pix objects across instances.
 */
export async function load() {
    const factory = (await import("@killbus/leptonica/leptonica.mjs")).default;
    const module = await factory();
    return new Leptonica(module);
}
