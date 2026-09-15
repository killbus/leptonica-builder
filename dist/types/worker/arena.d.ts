import { Leptonica } from "../core/types.js";
import type { Op, Query } from "../protocol.js";
import type { HandleId, WorkerRequest, WorkerResponse } from "./protocol.js";
/**
 * The postMessage surface shared by browser and Node worker adapters.
 * Keeping it here makes the arena/protocol boundary testable without
 * importing the production worker entry or its generated WASM loader.
 */
export interface PostSurface {
    post(msg: WorkerResponse, transfer?: Transferable[]): void;
    onMessage(cb: (req: WorkerRequest) => void): void;
}
/** The worker-side arena: every adopted Pix belongs to one Leptonica heap. */
export declare class WorkerArena {
    #private;
    constructor(lp: Leptonica);
    load(buffer: ArrayBuffer, w: number, h: number): {
        handle: HandleId;
        width: number;
        height: number;
        depth: number;
    };
    run(source: HandleId, ops: readonly Op[]): {
        handle: HandleId;
        width: number;
        height: number;
        depth: number;
    };
    extract(handle: HandleId, format: "rgba" | "png" | "jpeg" | "mask", quality?: number): ArrayBuffer;
    query(handle: HandleId, query: Query): WorkerResponse;
    close(): void;
}
/** Wire the arena to a postMessage surface. */
export declare function wireWorker(lp: Leptonica, surface: PostSurface): void;
