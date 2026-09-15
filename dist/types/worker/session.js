/**
 * Worker session client (design §5) — the recommended entry point.
 *
 * Pix handles live in the worker's arena; the main thread holds light
 * proxy objects carrying numeric handle ids. session.close() releases
 * every live Pix at once and poisons the session (decision ⑭: arena
 * model, no per-object remote dispose in v1). terminate() kills the
 * worker thread outright — the whole wasm heap dies with it.
 */
import { toTransferableArrayBuffer } from "./bytes.js";
const remoteHandles = new WeakMap();
const remotePixConstructionToken = Symbol("leptonica-wasm RemotePix construction");
let createRemotePix;
function remoteHandleFor(pix) {
    const handle = remoteHandles.get(pix);
    if (handle === undefined)
        throw new ReferenceError("RemotePix handle is unavailable");
    return handle;
}
/** Main-thread proxy for a Pix living in the worker. */
export class RemotePix {
    /** @internal — session backref for request dispatch. */
    #session;
    /** Width in pixels. */
    width;
    /** Height in pixels. */
    height;
    /** Bit depth of the remote Pix. */
    depth;
    #poisoned = false;
    static {
        createRemotePix = (session, id, width, height, depth) => new RemotePix(session, id, width, height, depth, remotePixConstructionToken);
    }
    /** Constructed by WorkerSession only. */
    constructor(session, id, width, height, depth, token) {
        if (token !== remotePixConstructionToken) {
            throw new TypeError("RemotePix cannot be constructed directly");
        }
        this.#session = session;
        remoteHandles.set(this, id);
        this.width = width;
        this.height = height;
        this.depth = depth;
    }
    /** @internal — poisoning read (close() marks every proxy dead). */
    isPoisoned() {
        return this.#poisoned;
    }
    /** @internal — liveness gate for extract dispatch. */
    assertAlive(what) {
        this.#assertAlive(what);
    }
    /** @internal — close() marks every proxy dead without a round trip. */
    poison() {
        this.#poisoned = true;
    }
    #assertAlive(what) {
        if (this.#poisoned || this.#session.isClosed()) {
            throw new ReferenceError(`RemotePix is not usable (call: ${what})`);
        }
    }
    /** Encode to PNG bytes; the buffer transfers back to this thread. */
    toPNG() {
        // Liveness gates reject (not throw synchronously): these methods
        // return promises, and a poisoned proxy surfacing as a rejection is
        // the uniform failure shape across close()/terminate()/worker death.
        return this.#session.extract(this, "png");
    }
    /** Encode to JPEG bytes at quality 0-100. */
    toJPEG(quality) {
        return this.#session.extract(this, "jpeg", quality);
    }
    /** Extract RGBA bytes (32bpp only). */
    toRGBA() {
        return this.#session.extract(this, "rgba");
    }
    /** Extract a compact, row-major MSB-first mask (1bpp only). */
    async toMask() {
        await Promise.resolve().then(() => this.#assertAlive("toMask"));
        if (this.depth !== 1)
            throw new TypeError(`toMask: requires 1bpp, got ${this.depth}bpp`);
        const data = await this.#session.extract(this, "mask");
        return {
            data,
            width: this.width,
            height: this.height,
            strideBytes: Math.ceil(this.width / 8),
            bitOrder: "msb-first",
            foregroundBit: 1,
        };
    }
    /** Query: deskew angle estimate (1bpp only). */
    async findSkew() {
        // Async method: liveness refusals surface as rejections, uniform
        // with toPNG/load/run (a poisoned proxy must never throw
        // synchronously out of a promise-returning method).
        await Promise.resolve().then(() => this.#assertAlive("findSkew"));
        return this.#session.query(this, { query: "findSkew" }).then((v) => {
            if (v.kind !== "findSkew")
                throw new TypeError("worker: findSkew response kind mismatch");
            return { angle: v.angle, confidence: v.confidence };
        });
    }
    /** Query: count of ON pixels (1bpp only). */
    async countPixels() {
        await Promise.resolve().then(() => this.#assertAlive("countPixels"));
        return this.#session.query(this, { query: "countPixels" }).then((v) => {
            if (v.kind !== "countPixels")
                throw new TypeError("worker: countPixels response kind mismatch");
            return v.count;
        });
    }
    /** Query: connected components, 8-connectivity (1bpp only). */
    async connComp() {
        await Promise.resolve().then(() => this.#assertAlive("connComp"));
        return this.#session.query(this, { query: "connComp" }).then((v) => {
            if (v.kind !== "connComp")
                throw new TypeError("worker: connComp response kind mismatch");
            return v.boxes;
        });
    }
    /** Query: 256-bin gray histogram (8bpp). */
    async histogram() {
        await Promise.resolve().then(() => this.#assertAlive("histogram"));
        return this.#session.query(this, { query: "histogram" }).then((v) => {
            if (v.kind !== "histogram")
                throw new TypeError("worker: histogram response kind mismatch");
            return v.bins;
        });
    }
    /** Query: mean gray value. */
    async average() {
        await Promise.resolve().then(() => this.#assertAlive("average"));
        return this.#session.query(this, { query: "average" }).then((v) => {
            if (v.kind !== "average")
                throw new TypeError("worker: average response kind mismatch");
            return v.value;
        });
    }
}
/** A live worker session. Obtain via createSession(). */
export class WorkerSession {
    /** @internal — postMessage-shaped transport (DOM Worker or worker_threads.Worker). */
    #post;
    /** @internal — live proxies, poisoned wholesale on close. */
    #live = new Set();
    /** @internal — pending request resolvers. */
    #pending = new Map();
    /** @internal — adapter teardown, fired at most once. */
    #teardown;
    #tornDown = false;
    #nextRequestId = 1;
    #closed = false;
    #terminated = false;
    #terminationReason = null;
    /** Transport-level constructor used by the browser and Node adapters. */
    constructor(post, onMessage, 
    /** @internal — adapter hook: kill the platform worker once the session is dead. */
    teardown) {
        this.#post = post;
        this.#teardown = teardown;
        onMessage((response) => this.#onResponse(response));
    }
    /** @internal */
    isClosed() {
        return this.#closed || this.#terminated;
    }
    /** @internal — run the adapter teardown exactly once. */
    #runTeardown() {
        if (this.#tornDown)
            return;
        this.#tornDown = true;
        this.#teardown?.();
    }
    /**
     * @internal — handshake: let the worker load the wasm module (with an
     * optional wasmPath override) before the first user request. The
     * adapters call this right after wiring message handlers.
     */
    init(wasmPath) {
        return this.#request({ id: this.#nextRequestId++, type: "init", ...(wasmPath !== undefined ? { wasmPath: String(wasmPath) } : {}) }).then((r) => {
            if (!r.ok || r.type !== "init")
                throw new Error(`init: unexpected response ${JSON.stringify(r)}`);
            this.#assertOpen("init");
        });
    }
    /**
     * Load RGBA bytes as a new 32bpp Pix in the worker's arena.
     * A full view over an ArrayBuffer is transferred and detaches. Partial or
     * SharedArrayBuffer-backed views are copied exactly before transfer.
     */
    load(data, w, h) {
        // Async API: refusals surface as rejections, uniform with the
        // poisoned-proxy path (see toPNG).
        try {
            this.#assertOpen("load");
        }
        catch (err) {
            return Promise.reject(err);
        }
        if (!Number.isInteger(w) || !Number.isInteger(h) || w <= 0 || h <= 0) {
            throw new RangeError(`load: bad dimensions ${w}x${h}`);
        }
        if (data.byteLength !== w * h * 4) {
            throw new RangeError(`load: expected ${w * h * 4} bytes, got ${data.byteLength}`);
        }
        const buffer = toTransferableArrayBuffer(data);
        return this.#request({ id: this.#nextRequestId++, type: "load", buffer, w, h }, [buffer]).then((r) => {
            if (!r.ok || r.type !== "load")
                throw new Error(`load: unexpected response ${JSON.stringify(r)}`);
            // A transport may synchronously deliver another response before this
            // continuation runs. Do not publish a fresh proxy after a same-turn
            // fatal response or close has already retired the session.
            this.#assertOpen("load");
            const pix = createRemotePix(this, r.handle, r.width, r.height, r.depth);
            this.#live.add(pix);
            return pix;
        });
    }
    /**
     * Chain ops on a source Pix. The whole op array goes over as ONE
     * message (design §5.1: builder IS the protocol — run() is the only
     * round trip, one await).
     */
    async run(source, ops) {
        try {
            this.#assertOpen("run");
            this.#assertOwns(source, "run");
        }
        catch (err) {
            return Promise.reject(err);
        }
        if (source.isPoisoned())
            throw new ReferenceError("run: source RemotePix is not usable");
        const r = await this.#request({ id: this.#nextRequestId++, type: "run", source: remoteHandleFor(source), ops: [...ops] });
        if (!r.ok || r.type !== "run")
            throw new Error(`run: unexpected response ${JSON.stringify(r)}`);
        this.#assertOpen("run");
        const pix = createRemotePix(this, r.handle, r.width, r.height, r.depth);
        this.#live.add(pix);
        return pix;
    }
    /** Every live Pix in the worker's arena is released; the session is poisoned. */
    async close() {
        // A terminated session is already fully torn down (markTerminated
        // released the worker and poisoned every proxy); close() after
        // worker death must stay a no-op resolve, not throw — callers
        // routinely reach for close() in cleanup/finally paths after
        // observing the death. Without this guard the farewell request
        // hits #request's isClosed() gate and rejects.
        if (this.isClosed())
            return;
        // Send the close request BEFORE flipping the flag — #request() gates
        // on isClosed() and would reject our own farewell message.
        const farewell = this.#request({ id: this.#nextRequestId++, type: "close" });
        for (const pix of this.#live)
            pix.poison();
        this.#live.clear();
        try {
            this.#closed = true;
            // close is an instruction, not a request that needs the worker's
            // confirmation: if the worker dies mid-handshake (exit event
            // arriving while the farewell is in flight), the pending farewell
            // is rejected by markTerminated — swallowing it keeps close()
            // usable in finally/cleanup paths without masking the original
            // error the caller is already handling.
            await farewell.catch(() => { });
        }
        finally {
            this.#rejectPending(new Error("session closed"));
            this.#runTeardown();
        }
    }
    /**
     * Kill the worker thread outright — the whole wasm heap dies with it
     * (design §5: the nuclear option). In-flight requests reject with
     * "worker terminated"; every live proxy is poisoned; close() after
     * this is a no-op resolve. Use when close() cannot drain fast enough
     * (a long-running op holds the farewell FIFO slot indefinitely).
     */
    terminate() {
        this.markTerminated();
    }
    /** @internal — mark terminated without a round trip (worker died). */
    markTerminated(reason = new Error("worker terminated")) {
        if (this.#terminated)
            return;
        this.#terminated = true;
        this.#terminationReason = reason;
        for (const pix of this.#live)
            pix.poison();
        this.#live.clear();
        this.#rejectPending(reason);
        this.#runTeardown();
    }
    /** @internal — extract dispatch with session ownership and liveness checks. */
    extract(pix, format, quality) {
        try {
            this.#assertUsablePix(pix, `extract:${format}`);
        }
        catch (err) {
            return Promise.reject(err);
        }
        const req = { id: this.#nextRequestId++, type: "extract", handle: remoteHandleFor(pix), format, ...(quality !== undefined ? { quality } : {}) };
        return this.#request(req).then((r) => {
            if (!r.ok || r.type !== "extract")
                throw new Error(`extract: unexpected response ${JSON.stringify(r)}`);
            this.#assertOpen(`extract:${format}`);
            return new Uint8Array(r.buffer);
        });
    }
    /** @internal — query dispatch with session ownership and liveness checks. */
    query(pix, query) {
        try {
            this.#assertUsablePix(pix, `query:${query.query}`);
        }
        catch (err) {
            return Promise.reject(err);
        }
        return this.#request({ id: this.#nextRequestId++, type: "query", handle: remoteHandleFor(pix), query }).then((r) => {
            if (!r.ok || r.type !== "query")
                throw new Error(`query: unexpected response ${JSON.stringify(r)}`);
            this.#assertOpen(`query:${query.query}`);
            return r.value;
        });
    }
    #request(msg, transfer) {
        if (this.isClosed()) {
            return Promise.reject(new ReferenceError("WorkerSession is closed"));
        }
        return new Promise((resolve, reject) => {
            this.#pending.set(msg.id, { resolve, reject });
            try {
                this.#post(msg, transfer);
            }
            catch (error) {
                // A synchronous transport failure means no response can complete this
                // request. Remove its resolver immediately so a malformed or delayed
                // message cannot revive stale state, and so a live session does not
                // retain one pending entry per failed post.
                this.#pending.delete(msg.id);
                reject(error);
            }
        });
    }
    #onResponse(response) {
        // Fatal is a session-wide control signal, so it remains authoritative
        // even if its request was already rejected locally. Check only the
        // explicit discriminator here: ordinary stale responses must be ignored
        // without inspecting their payload (the transport may already have
        // invalidated or detached it).
        if ("fatal" in response && response.fatal === true) {
            const error = new WebAssembly.RuntimeError(`worker retired after fatal WebAssembly trap: ${response.error}`);
            this.markTerminated(error);
            return;
        }
        const pending = this.#pending.get(response.id);
        if (pending === undefined) {
            // A response for a request we already rejected (e.g. after close).
            return;
        }
        this.#pending.delete(response.id);
        if (response.ok) {
            pending.resolve(response);
        }
        else {
            pending.reject(new Error(response.error));
        }
    }
    #rejectPending(err) {
        for (const { reject } of this.#pending.values())
            reject(err);
        this.#pending.clear();
    }
    #assertOwns(pix, what) {
        if (!this.#live.has(pix)) {
            throw new TypeError(`${what}: RemotePix belongs to a different session`);
        }
    }
    #assertUsablePix(pix, what) {
        this.#assertOpen(what);
        this.#assertOwns(pix, what);
        pix.assertAlive(what);
    }
    #assertOpen(what) {
        if (this.#terminated) {
            throw new ReferenceError(`WorkerSession is terminated (call: ${what}; reason: ${this.#terminationReason?.message ?? "worker terminated"})`);
        }
        if (this.#closed) {
            throw new ReferenceError(`WorkerSession is closed (call: ${what})`);
        }
    }
}
