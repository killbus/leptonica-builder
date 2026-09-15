/**
 * Raw C-ABI escape hatch (design §4.3).
 *
 * Loads the full-abi build (dist/full-abi/) and hands you the C ABI
 * with loose types. This module is documented danger: no semver, no
 * ownership, no validation. Prefer the curated layer unless you need
 * a leptonica function it does not expose.
 */
import { rawMemory } from "./types.js";
export { rawMemory, } from "./types.js";
let factoryPromise = null;
async function importFactory() {
    // The full-abi artifacts live at dist/full-abi/ and are exposed as a
    // package subpath (see package.json "exports" "./raw"). Node resolves
    // this at runtime relative to the package root; bundlers follow the
    // subpath export.
    const mod = await import("@killbus/leptonica/full-abi/leptonica.mjs");
    return mod.default;
}
/**
 * Instantiate the full-abi wasm build.
 *
 * The -O2 full-abi glue does not expose HEAP views on the module object,
 * so the memory export is captured at instantiation and exposed as heap
 * views on the result (see rawMemory). Views are re-derived per read to
 * survive heap growth (ALLOW_MEMORY_GROWTH).
 */
export async function loadRaw(options) {
    if (options.wasmBinary == null || options.wasmBinary.byteLength === 0) {
        throw new Error("loadRaw: wasmBinary is required — read or fetch the full-abi wasm" +
            " (subpath export \"leptonica-wasm/full-abi/leptonica.wasm\") and pass its bytes");
    }
    factoryPromise ??= importFactory();
    const factory = await factoryPromise;
    let memory;
    let instantiationFailed = () => { };
    const failure = new Promise((_, reject) => {
        instantiationFailed = reject;
    });
    const module = factory({
        wasmBinary: options.wasmBinary,
        instantiateWasm(imports, receiveInstance) {
            WebAssembly.instantiate(options.wasmBinary, imports).then((result) => {
                const mem = result.instance.exports.memory;
                if (mem instanceof WebAssembly.Memory)
                    memory = mem;
                receiveInstance(result.instance);
            }, (error) => {
                // Emscripten's instantiateWasm callback has no error channel: the
                // factory promise would hang forever (receiveInstance is never
                // called). Reject the race below with the real cause instead.
                instantiationFailed(error);
            });
        },
    });
    // The factory promise hangs if instantiation fails (receiveInstance is
    // never called), so race it against the failure side-channel. A factory
    // rejection (import failure, compile failure outside instantiateWasm)
    // settles the race directly with the real error.
    const raw = await Promise.race([module, failure]);
    if (!memory) {
        throw new Error("full-abi module did not export its memory");
    }
    return { raw, memory: rawMemory(memory) };
}
