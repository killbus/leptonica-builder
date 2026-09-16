/**
 * Core-layer types: the Leptonica instance and the Pix wrapper.
 *
 * The Pix wrapper owns exactly one PIX handle (embind class handle from
 * the curated build). Disposal is explicit — Symbol.dispose →
 * destroyPix + poison; FinalizationRegistry only warns (decision ④).
 */
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
export function shouldRetireWasmInstance(error) {
    if (typeof WebAssembly === "object" &&
        typeof WebAssembly.RuntimeError === "function" &&
        error instanceof WebAssembly.RuntimeError) {
        return true;
    }
    // Errors retain their originating realm's constructor. A genuine trap
    // crossing an iframe/vm boundary therefore fails instanceof in this realm.
    // Require both the standard Error tag and the built-in constructor/name
    // pair; changing an ordinary Error's public `name` alone is not enough.
    if (typeof error !== "object" || error === null)
        return false;
    try {
        const candidate = error;
        return (Object.prototype.toString.call(error) === "[object Error]" &&
            candidate.name === "RuntimeError" &&
            candidate.constructor?.name === "RuntimeError");
    }
    catch {
        return false;
    }
}
import { ChainBuilder } from "./chain.js";
const nativeModules = new WeakMap();
const nativeHandles = new WeakMap();
const pixOwners = new WeakMap();
const pixConstructionToken = Symbol("leptonica-wasm Pix construction");
let createPix;
/** @internal — package-private native access for the chain executor. */
export function nativeModuleFor(lp) {
    const module = nativeModules.get(lp);
    if (module === undefined)
        throw new ReferenceError("Leptonica native module is unavailable");
    return module;
}
/** @internal — package-private native access for the chain executor. */
export function nativeHandleFor(pix) {
    const handle = nativeHandles.get(pix);
    if (handle === undefined)
        throw new ReferenceError("Pix native handle is unavailable");
    return handle;
}
function ownerFor(pix) {
    const owner = pixOwners.get(pix);
    if (owner === undefined)
        throw new ReferenceError("Pix owner is unavailable");
    return owner;
}
/**
 * A wrapped PIX handle. The wrapper is the only public way to touch the
 * handle; every method checks the poisoned flag first.
 */
export class Pix {
    #poisoned = false;
    static {
        createPix = (handle, lp) => new Pix(handle, lp, pixConstructionToken);
    }
    get #handle() {
        return nativeHandleFor(this);
    }
    get #lp() {
        return ownerFor(this);
    }
    /** @internal — poisoned flag read for cross-class checks. */
    isPoisoned() {
        return this.#poisoned;
    }
    constructor(handle, lp, token) {
        if (token !== pixConstructionToken) {
            throw new TypeError("Pix cannot be constructed directly");
        }
        nativeHandles.set(this, handle);
        pixOwners.set(this, lp);
    }
    /** Width in pixels. Throws if disposed. */
    get width() {
        this.#assertAlive("width");
        return this.#lp.callNative("width", () => nativeModuleFor(this.#lp).pixWidth(this.#handle));
    }
    /** Height in pixels. Throws if disposed. */
    get height() {
        this.#assertAlive("height");
        return this.#lp.callNative("height", () => nativeModuleFor(this.#lp).pixHeight(this.#handle));
    }
    /** Bit depth (1/2/4/8/16/24/32). Throws if disposed. */
    get depth() {
        this.#assertAlive("depth");
        return this.#lp.callNative("depth", () => nativeModuleFor(this.#lp).pixDepth(this.#handle));
    }
    /** Encode to PNG bytes in JS-owned memory. */
    toPNG() {
        this.#assertAlive("toPNG");
        const view = this.#lp.callNative("toPNG", () => nativeModuleFor(this.#lp).toPNG(this.#handle));
        if (view === null)
            throw new Error("toPNG: encoder failed");
        return view;
    }
    /** Encode to JPEG bytes at the given quality (0-100). */
    toJPEG(quality) {
        this.#assertAlive("toJPEG");
        const view = this.#lp.callNative("toJPEG", () => nativeModuleFor(this.#lp).toJPEG(this.#handle, quality));
        if (view === null)
            throw new Error("toJPEG: encoder failed");
        return view;
    }
    /** Extract RGBA bytes (32bpp only) into JS-owned memory. */
    toRGBA() {
        this.#assertAlive("toRGBA");
        const view = this.#lp.callNative("toRGBA", () => nativeModuleFor(this.#lp).toRGBA(this.#handle));
        if (view === null)
            throw new Error("toRGBA: requires 32bpp");
        return view;
    }
    /** Extract a compact, row-major MSB-first mask (1bpp only). */
    toMask() {
        this.#assertAlive("toMask");
        if (this.depth !== 1)
            throw new TypeError(`toMask: requires 1bpp, got ${this.depth}bpp`);
        const view = this.#lp.callNative("toMask", () => nativeModuleFor(this.#lp).toMask(this.#handle));
        if (view === null)
            throw new Error("toMask: extraction failed");
        const width = this.width;
        const height = this.height;
        return {
            data: view,
            width,
            height,
            strideBytes: Math.ceil(width / 8),
            bitOrder: "msb-first",
            foregroundBit: 1,
        };
    }
    /** Query: deskew angle estimate (1bpp only). */
    findSkew() {
        this.#assertAlive("findSkew");
        const r = this.#lp.callNative("findSkew", () => nativeModuleFor(this.#lp).findSkew(this.#handle));
        if (r === null)
            throw new Error("findSkew: requires 1bpp");
        return r;
    }
    /** Query: count of ON pixels (1bpp only). */
    countPixels() {
        this.#assertAlive("countPixels");
        const n = this.#lp.callNative("countPixels", () => nativeModuleFor(this.#lp).countPixels(this.#handle));
        if (n < 0)
            throw new Error("countPixels: requires 1bpp");
        return n;
    }
    /** Query: connected components, 8-connectivity (1bpp only). */
    connComp() {
        this.#assertAlive("connComp");
        const boxes = this.#lp.callNative("connComp", () => nativeModuleFor(this.#lp).connComp(this.#handle));
        if (boxes === null)
            throw new Error("connComp: requires 1bpp");
        return boxes;
    }
    /** Query: 256-bin gray histogram (8bpp). */
    histogram() {
        this.#assertAlive("histogram");
        const bins = this.#lp.callNative("histogram", () => nativeModuleFor(this.#lp).histogram(this.#handle));
        if (bins === null)
            throw new Error("histogram: requires 8bpp");
        return bins;
    }
    /** Query: mean gray value (L_MEAN_ABSVAL). */
    average() {
        this.#assertAlive("average");
        const avg = this.#lp.callNative("average", () => nativeModuleFor(this.#lp).average(this.#handle));
        if (avg === null)
            throw new Error("average: query failed");
        return avg;
    }
    /** Release the PIX handle. Idempotent; poisons the wrapper. */
    [Symbol.dispose]() {
        this.dispose();
    }
    /** Explicit disposal — same as Symbol.dispose. */
    dispose() {
        if (this.#poisoned)
            return;
        this.#poisoned = true;
        try {
            this.#lp.callNative("dispose", () => nativeModuleFor(this.#lp).destroyPix(this.#handle));
        }
        finally {
            this.#lp.unregister(this);
        }
    }
    /** @internal — poison without destroying (owner is closing everything). */
    poisonForClose() {
        this.#poisoned = true;
    }
    #assertAlive(what) {
        if (this.#poisoned) {
            throw new ReferenceError(`Pix is disposed (call: ${what})`);
        }
    }
    /** Dev-mode detection shared with the registry guard (decision ④). */
    static isDev() {
        const proc = globalThis;
        return (proc.process !== undefined && proc.process.env?.NODE_ENV === "development");
    }
}
/**
 * A loaded leptonica instance — one wasm module instantiation with its
 * own heap. Handles are instance-scoped.
 */
export class Leptonica {
    /** @internal — live wrappers, for close() and leak warnings. */
    #live = new Set();
    #registry;
    /** @internal — binary-op operand table (M4 review B1): op.other ids. */
    #operands = new Map();
    #nextOperandId = 1;
    /** @internal — closed flag: close() poisons the arena permanently. */
    #closed = false;
    /** @internal — a fatal trap retires the heap without calling into it again. */
    #retiredByTrap = false;
    constructor(module) {
        nativeModules.set(this, module);
        // Decision ④: FinalizationRegistry only WARNS (dev mode); explicit
        // dispose is the contract. typeof process guard keeps browsers clean.
        // M4 review N3: register() requires target !== holdings — a Pix used
        // as both throws synchronously in dev mode, which is exactly when the
        // registry exists. The Set already holds the wrapper strongly, so a
        // unique object as holdings costs nothing and keeps the held value
        // meaningful for the leak warning.
        this.#registry =
            Pix.isDev()
                ? new FinalizationRegistry((holder) => {
                    if (this.#live.has(holder.pix)) {
                        console.warn("leptonica-wasm: Pix was garbage-collected without dispose()");
                    }
                })
                : null;
    }
    /**
     * Create a 32bpp Pix from RGBA bytes. The data is copied into the wasm
     * heap; the input is not retained.
     */
    fromRGBA(data, w, h) {
        this.#assertOpen("fromRGBA");
        if (!Number.isInteger(w) || !Number.isInteger(h) || w <= 0 || h <= 0) {
            throw new RangeError(`fromRGBA: bad dimensions ${w}x${h}`);
        }
        const len = data.byteLength;
        if (len !== w * h * 4) {
            throw new RangeError(`fromRGBA: expected ${w * h * 4} bytes, got ${len}`);
        }
        const handle = this.callNative("fromRGBA", () => nativeModuleFor(this).fromRGBA(data, w, h));
        if (handle === null)
            throw new Error("fromRGBA: allocation failed");
        return this.adopt(handle);
    }
    /** Start a chain on a source Pix. The source is not consumed by run(). */
    chain(src) {
        this.#assertOpen("chain");
        this.assertOwns(src, "chain");
        if (src.isPoisoned())
            throw new ReferenceError("chain: source Pix is disposed");
        return new ChainBuilder(this, src);
    }
    /** Destroy every live Pix and poison the arena. Instance is unusable after. */
    close() {
        if (this.#closed || this.#retiredByTrap)
            return;
        this.#closed = true;
        const live = [...this.#live];
        for (const pix of live) {
            pix.poisonForClose();
            this.#registry?.unregister(pix);
        }
        this.#live.clear();
        this.#operands.clear();
        let firstError;
        for (const pix of live) {
            try {
                this.#callNativeUnchecked(() => nativeModuleFor(this).destroyPix(nativeHandleFor(pix)));
            }
            catch (error) {
                if (shouldRetireWasmInstance(error))
                    throw error;
                firstError ??= error;
            }
        }
        if (firstError !== undefined)
            throw firstError;
    }
    /** @internal — the sole trap-aware boundary for curated native calls. */
    callNative(what, operation) {
        this.#assertOpen(what);
        return this.#callNativeUnchecked(operation);
    }
    /** @internal */
    adopt(handle) {
        this.#assertOpen("adopt");
        const pix = createPix(handle, this);
        this.#live.add(pix);
        this.#registry?.register(pix, { pix }, pix);
        return pix;
    }
    /** @internal */
    unregister(pix) {
        this.#live.delete(pix);
        this.#registry?.unregister(pix);
    }
    /** @internal — register a binary-op operand; returns its wire id. */
    registerOperand(pix) {
        const id = this.#nextOperandId++;
        this.#operands.set(id, pix);
        return id;
    }
    /** @internal — resolve a binary-op operand id (recorded in an Op). */
    resolveOperand(id, what) {
        const pix = this.#operands.get(id);
        if (pix === undefined) {
            throw new ReferenceError(`${what}: operand ${id} is not registered on this instance`);
        }
        if (pix.isPoisoned()) {
            throw new ReferenceError(`${what}: operand Pix was disposed before run()`);
        }
        return pix;
    }
    /** @internal */
    assertOwns(pix, what) {
        if (ownerFor(pix) !== this) {
            throw new TypeError(`${what}: Pix belongs to a different Leptonica instance`);
        }
    }
    #assertOpen(what) {
        if (this.#retiredByTrap) {
            throw new ReferenceError(`Leptonica instance retired after a fatal WebAssembly trap (call: ${what})`);
        }
        if (this.#closed) {
            throw new ReferenceError(`Leptonica instance is closed (call: ${what})`);
        }
    }
    #callNativeUnchecked(operation) {
        try {
            return operation();
        }
        catch (error) {
            if (shouldRetireWasmInstance(error))
                this.#retireAfterTrap();
            throw error;
        }
    }
    #retireAfterTrap() {
        if (this.#retiredByTrap)
            return;
        this.#retiredByTrap = true;
        // A trap can indicate corrupted or unreachable native state. Poison all
        // wrappers and abandon this heap; invoking destroyPix here would cross the
        // same fatal boundary again and could conceal the original trap.
        for (const pix of this.#live) {
            pix.poisonForClose();
            this.#registry?.unregister(pix);
        }
        this.#live.clear();
        this.#operands.clear();
    }
}
