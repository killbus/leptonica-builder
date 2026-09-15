/**
 * Wire protocol shared by the session client (main thread) and the worker
 * entry (design §5.2 — hand-written, both ends import this file).
 *
 * Large payloads move exclusively as transferred ArrayBuffers: load
 * carries the RGBA bytes up, extract carries the encoded bytes down.
 * Handles never cross the boundary — only their numeric ids.
 */
import type { Op, Query } from "../protocol.js";
/** Numeric id of a Pix living in the worker's arena. */
export type HandleId = number;
/** Client → worker requests. One request id per message. */
export type WorkerRequest = {
    readonly id: number;
    readonly type: "init";
    readonly wasmPath?: string;
} | {
    readonly id: number;
    readonly type: "load";
    readonly buffer: ArrayBuffer;
    readonly w: number;
    readonly h: number;
} | {
    readonly id: number;
    readonly type: "run";
    readonly source: HandleId;
    readonly ops: readonly Op[];
} | {
    readonly id: number;
    readonly type: "extract";
    readonly handle: HandleId;
    readonly format: "rgba" | "png" | "jpeg" | "mask";
    readonly quality?: number;
} | {
    readonly id: number;
    readonly type: "query";
    readonly handle: HandleId;
    readonly query: Query;
} | {
    readonly id: number;
    readonly type: "close";
};
/** Worker → client responses. */
export type WorkerResponse = {
    readonly id: number;
    readonly ok: true;
    readonly type: "init";
} | {
    readonly id: number;
    readonly ok: true;
    readonly type: "load";
    readonly handle: HandleId;
    readonly width: number;
    readonly height: number;
    readonly depth: number;
} | {
    readonly id: number;
    readonly ok: true;
    readonly type: "run";
    readonly handle: HandleId;
    readonly width: number;
    readonly height: number;
    readonly depth: number;
} | {
    readonly id: number;
    readonly ok: true;
    readonly type: "extract";
    readonly buffer: ArrayBuffer;
} | {
    readonly id: number;
    readonly ok: true;
    readonly type: "query";
    readonly value: {
        readonly kind: "findSkew";
        readonly angle: number;
        readonly confidence: number;
    } | {
        readonly kind: "connComp";
        readonly boxes: readonly {
            readonly x: number;
            readonly y: number;
            readonly w: number;
            readonly h: number;
        }[];
    } | {
        readonly kind: "countPixels";
        readonly count: number;
    } | {
        readonly kind: "histogram";
        readonly bins: readonly number[];
    } | {
        readonly kind: "average";
        readonly value: number;
    };
} | {
    readonly id: number;
    readonly ok: true;
    readonly type: "close";
} | {
    readonly id: number;
    readonly ok: false;
    readonly fatal?: false;
    readonly error: string;
} | {
    readonly id: number;
    readonly ok: false;
    readonly fatal: true;
    readonly error: string;
};
