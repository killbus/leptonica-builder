/**
 * Return an exact, transferable ArrayBuffer for a byte view.
 *
 * Full views over ordinary ArrayBuffers are already safe to transfer. Partial
 * views and SharedArrayBuffer-backed views require one exact copy so callers
 * neither expose unrelated backing bytes nor place a non-transferable buffer
 * in a transfer list.
 */
export declare function toTransferableArrayBuffer(view: ArrayBufferView): ArrayBuffer;
