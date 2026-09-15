/**
 * Worker session client (design §5) — the recommended entry point.
 *
 * Pix handles live in the worker's arena; the main thread holds light
 * proxy objects carrying numeric handle ids. session.close() releases
 * every live Pix at once and poisons the session (decision ⑭: arena
 * model, no per-object remote dispose in v1). terminate() kills the
 * worker thread outright — the whole wasm heap dies with it.
 */
import type { WorkerRequest, WorkerResponse } from "./protocol.js";
import type { PackedMask } from "../core/types.js";
/** Options for createSession. */
export interface SessionOptions {
    /**
     * Override for the wasm binary location. Default: the file sitting
     * next to the worker entry (dist/leptonica.wasm), resolved by the
     * worker itself — CDN/self-hosting users pass their own URL.
     */
    readonly wasmPath?: string | URL;
}
/** Main-thread proxy for a Pix living in the worker. */
export declare class RemotePix {
    #private;
    /** Width in pixels. */
    readonly width: number;
    /** Height in pixels. */
    readonly height: number;
    /** Bit depth of the remote Pix. */
    readonly depth: number;
    /** Constructed by WorkerSession only. */
    private constructor();
    /** Encode to PNG bytes; the buffer transfers back to this thread. */
    toPNG(): Promise<Uint8Array>;
    /** Encode to JPEG bytes at quality 0-100. */
    toJPEG(quality: number): Promise<Uint8Array>;
    /** Extract RGBA bytes (32bpp only). */
    toRGBA(): Promise<Uint8Array>;
    /** Extract a compact, row-major MSB-first mask (1bpp only). */
    toMask(): Promise<PackedMask>;
    /** Query: deskew angle estimate (1bpp only). */
    findSkew(): Promise<{
        angle: number;
        confidence: number;
    }>;
    /** Query: count of ON pixels (1bpp only). */
    countPixels(): Promise<number>;
    /** Query: connected components, 8-connectivity (1bpp only). */
    connComp(): Promise<readonly {
        x: number;
        y: number;
        w: number;
        h: number;
    }[]>;
    /** Query: 256-bin gray histogram (8bpp). */
    histogram(): Promise<readonly number[]>;
    /** Query: mean gray value. */
    average(): Promise<number>;
}
/** A live worker session. Obtain via createSession(). */
export declare class WorkerSession {
    #private;
    /** Transport-level constructor used by the browser and Node adapters. */
    constructor(post: (msg: WorkerRequest, transfer?: Transferable[]) => void, onMessage: (cb: (r: WorkerResponse) => void) => void, 
    /** @internal — adapter hook: kill the platform worker once the session is dead. */
    teardown?: () => void);
    /**
     * Load RGBA bytes as a new 32bpp Pix in the worker's arena.
     * A full view over an ArrayBuffer is transferred and detaches. Partial or
     * SharedArrayBuffer-backed views are copied exactly before transfer.
     */
    load(data: Uint8Array | ArrayBufferView, w: number, h: number): Promise<RemotePix>;
    /**
     * Chain ops on a source Pix. The whole op array goes over as ONE
     * message (design §5.1: builder IS the protocol — run() is the only
     * round trip, one await).
     */
    run(source: RemotePix, ops: readonly import("../protocol.js").Op[]): Promise<RemotePix>;
    /** Every live Pix in the worker's arena is released; the session is poisoned. */
    close(): Promise<void>;
    /**
     * Kill the worker thread outright — the whole wasm heap dies with it
     * (design §5: the nuclear option). In-flight requests reject with
     * "worker terminated"; every live proxy is poisoned; close() after
     * this is a no-op resolve. Use when close() cannot drain fast enough
     * (a long-running op holds the farewell FIFO slot indefinitely).
     */
    terminate(): void;
}
