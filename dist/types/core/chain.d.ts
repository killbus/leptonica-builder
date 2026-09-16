import type { AreaSelection, Op } from "../protocol.js";
import { type Leptonica, type Pix } from "./types.js";
/**
 * Chain builder (design §5.1: builder IS the protocol).
 *
 * Each method records one Op — the same tagged-union shape the worker
 * sends over the wire and the native oracle parses. Depth is validated
 * at RECORD time (the builder tracks a depth cursor from the source
 * Pix), so an invalid chain throws before any wasm work happens.
 *
 * run() replays the recorded ops through the executor; the source Pix is
 * never consumed, intermediates are destroyed in the run() call stack,
 * and the failure path cleans up the same way.
 */
export declare class ChainBuilder {
    #private;
    constructor(lp: Leptonica, src: Pix);
    toGray(weights?: readonly [number, number, number]): this;
    threshold(level: number): this;
    otsu(opts?: {
        tile?: number;
        factor?: number;
    }): this;
    sauvola(whsize: number, factor?: number): this;
    cleanBackgroundToWhite(gamma: number, black: number, white: number): this;
    sauvolaTiled(whsize: number, factor: number, nx: number, ny: number): this;
    selectByArea(thresholdArea: number, connectivity: 4 | 8, relation: AreaSelection): this;
    maskOverColorPixels(thresholdDiff: number, minDistance: number): this;
    deskew(reduction?: 1 | 2 | 4): this;
    rotate(angle: number, quality?: "area" | "shear"): this;
    scale(fx: number, fy?: number): this;
    shear(direction: "h" | "v", angle: number): this;
    clip(x: number, y: number, w: number, h: number): this;
    translate(dx: number, dy: number): this;
    dilate(w: number, h: number): this;
    erode(w: number, h: number): this;
    open(w: number, h: number): this;
    close(w: number, h: number): this;
    or(other: Pix): this;
    and(other: Pix): this;
    xor(other: Pix): this;
    blend(other: Pix, frac: number): this;
    addBorder(t: number, val?: number): this;
    sobel(orientation?: "all" | "h" | "v"): this;
    /** Execute the recorded chain. Returns the final Pix (a new handle). */
    run(): Pix;
}
/**
 * The chain executor. Mirrors the op→call mapping in tests (golden
 * parity) and the native oracle (cpp/oracle.c applyOp); the intermediate
 * Pix handles are destroyed within this call stack on BOTH success and
 * failure paths (design §5.2 run-failure cleanup).
 */
export declare function runChain(lp: Leptonica, src: Pix, ops: readonly Op[]): Pix;
