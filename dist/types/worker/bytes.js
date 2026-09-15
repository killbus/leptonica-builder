/**
 * Return an exact, transferable ArrayBuffer for a byte view.
 *
 * Full views over ordinary ArrayBuffers are already safe to transfer. Partial
 * views and SharedArrayBuffer-backed views require one exact copy so callers
 * neither expose unrelated backing bytes nor place a non-transferable buffer
 * in a transfer list.
 */
export function toTransferableArrayBuffer(view) {
    if (view.buffer instanceof ArrayBuffer &&
        view.byteOffset === 0 &&
        view.byteLength === view.buffer.byteLength) {
        return view.buffer;
    }
    const source = new Uint8Array(view.buffer, view.byteOffset, view.byteLength);
    const copy = new Uint8Array(view.byteLength);
    copy.set(source);
    return copy.buffer;
}
