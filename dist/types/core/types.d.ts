/**
 * Core-layer types: the Leptonica instance and the Pix wrapper.
 *
 * The Pix wrapper owns exactly one PIX handle (embind class handle from
 * the curated build). Disposal is explicit — Symbol.dispose →
 * destroyPix + poison; FinalizationRegistry only warns (decision ④).
 */
/** Box from a connComp query. */
export interface Box {
    readonly x: number;
    readonly y: number;
    readonly w: number;
    readonly h: number;
}
/** Result of a findSkew query. */
export interface SkewResult {
    /** Estimated deskew angle in DEGREES (pixFindSkew returns degrees; pixRotate takes radians — convert with deg * Math.PI / 180 before rotating). */
    readonly angle: number;
    /** Confidence score; pixDeskew ignores angles with confidence < 3.0. */
    readonly confidence: number;
}
/** Compact, row-major 1 bpp data in JS-owned memory. */
export interface PackedMask {
    readonly data: Uint8Array;
    readonly width: number;
    readonly height: number;
    readonly strideBytes: number;
    readonly bitOrder: "msb-first";
    readonly foregroundBit: 1;
}
/**
 * Fail-closed retirement policy for errors crossing a native/module boundary.
 *
 * JavaScript exposes no portable, cross-realm discriminator between an actual
 * execution trap and a RuntimeError constructed by that realm. Treating the
 * RuntimeError shape conservatively can retire a healthy instance, but avoids
 * the more dangerous false negative: re-entering a heap after a real trap.
 * Call this only around trusted WASM module initialization/native operations,
 * never as a classifier for arbitrary external input.
 */
export declare function shouldRetireWasmInstance(error: unknown): error is WebAssembly.RuntimeError;
import type { CuratedModule } from "./emscripten-glue.js";
import { ChainBuilder } from "./chain.js";
/**
 * A wrapped PIX handle. The wrapper is the only public way to touch the
 * handle; every method checks the poisoned flag first.
 */
export declare class Pix {
    #private;
    private constructor();
    /** Width in pixels. Throws if disposed. */
    get width(): number;
    /** Height in pixels. Throws if disposed. */
    get height(): number;
    /** Bit depth (1/2/4/8/16/24/32). Throws if disposed. */
    get depth(): number;
    /** Encode to PNG bytes in JS-owned memory. */
    toPNG(): Uint8Array;
    /** Encode to JPEG bytes at the given quality (0-100). */
    toJPEG(quality: number): Uint8Array;
    /** Extract RGBA bytes (32bpp only) into JS-owned memory. */
    toRGBA(): Uint8Array;
    /** Extract a compact, row-major MSB-first mask (1bpp only). */
    toMask(): PackedMask;
    /** Query: deskew angle estimate (1bpp only). */
    findSkew(): SkewResult;
    /** Query: count of ON pixels (1bpp only). */
    countPixels(): number;
    /** Query: connected components, 8-connectivity (1bpp only). */
    connComp(): readonly Box[];
    /** Query: 256-bin gray histogram (8bpp). */
    histogram(): readonly number[];
    /** Query: mean gray value (L_MEAN_ABSVAL). */
    average(): number;
    /** Release the PIX handle. Idempotent; poisons the wrapper. */
    [Symbol.dispose](): void;
    /** Explicit disposal — same as Symbol.dispose. */
    dispose(): void;
    /** Dev-mode detection shared with the registry guard (decision ④). */
    static isDev(): boolean;
}
/**
 * A loaded leptonica instance — one wasm module instantiation with its
 * own heap. Handles are instance-scoped.
 */
export declare class Leptonica {
    #private;
    constructor(module: CuratedModule);
    /**
     * Create a 32bpp Pix from RGBA bytes. The data is copied into the wasm
     * heap; the input is not retained.
     */
    fromRGBA(data: Uint8Array | ArrayBufferView, w: number, h: number): Pix;
    /** Start a chain on a source Pix. The source is not consumed by run(). */
    chain(src: Pix): ChainBuilder;
    /** Destroy every live Pix and poison the arena. Instance is unusable after. */
    close(): void;
}
