import { Leptonica } from "./types.js";
/**
 * Instantiate the curated wasm module (default build, dist/leptonica.mjs).
 *
 * Each call creates a fresh module with its own heap. Handles are
 * instance-scoped — never mix Pix objects across instances.
 */
export declare function load(): Promise<Leptonica>;
