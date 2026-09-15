/**
 * Module shape of the Emscripten factory emitted by the curated build —
 * the content twin of emscripten-glue.d.ts (ambient form). gen-types.mjs
 * and any paths-mapped resolution consume this file; the ambient form
 * stays authoritative for the source-tree typecheck.
 */
export interface EmscriptenModuleArg {
  wasmBinary?: ArrayBuffer | Uint8Array;
  instantiateWasm?(
    imports: WebAssembly.Imports,
    receiveInstance: (instance: WebAssembly.Instance) => void,
  ): unknown;
  [key: string]: unknown;
}

/** Embind class handle for PIX. Opaque — the curated layer wraps it. */
export interface PixHandle {
  delete(): void;
  deleteLater(): this;
  isDeleted(): boolean;
}

/** The curated bindings surface (cpp/bindings.cpp EMSCRIPTEN_BINDINGS). */
export interface CuratedModule {
  destroyPix(pix: PixHandle | null): void;
  pixWidth(pix: PixHandle | null): number;
  pixHeight(pix: PixHandle | null): number;
  pixDepth(pix: PixHandle | null): number;
  fromRGBA(data: Uint8Array | ArrayBufferView, w: number, h: number): PixHandle | null;
  toGray(pix: PixHandle | null): PixHandle | null;
  toGrayWeighted(pix: PixHandle | null, r: number, g: number, b: number): PixHandle | null;
  threshold(pix: PixHandle | null, level: number): PixHandle | null;
  otsu(pix: PixHandle | null, tile: number, factor: number): PixHandle | null;
  sauvola(pix: PixHandle | null, whsize: number, factor: number): PixHandle | null;
  cleanBackgroundToWhite(pix: PixHandle | null, gamma: number, blackval: number, whiteval: number): PixHandle | null;
  sauvolaTiled(pix: PixHandle | null, whsize: number, factor: number, nx: number, ny: number): PixHandle | null;
  selectByArea(pix: PixHandle | null, thresholdArea: number, connectivity: 4 | 8, relation: "lt" | "gt" | "lte" | "gte"): PixHandle | null;
  maskOverColorPixels(pix: PixHandle | null, thresholdDiff: number, minDistance: number): PixHandle | null;
  deskew(pix: PixHandle | null, reduction: number): PixHandle | null;
  rotate(pix: PixHandle | null, angle: number, quality: string): PixHandle | null;
  scale(pix: PixHandle | null, fx: number, fy: number): PixHandle | null;
  shear(pix: PixHandle | null, direction: string, angle: number): PixHandle | null;
  clip(pix: PixHandle | null, x: number, y: number, w: number, h: number): PixHandle | null;
  translate(pix: PixHandle | null, dx: number, dy: number): PixHandle | null;
  morphDilate(pix: PixHandle | null, w: number, h: number): PixHandle | null;
  morphErode(pix: PixHandle | null, w: number, h: number): PixHandle | null;
  morphOpen(pix: PixHandle | null, w: number, h: number): PixHandle | null;
  morphClose(pix: PixHandle | null, w: number, h: number): PixHandle | null;
  bitwiseOr(a: PixHandle | null, b: PixHandle | null): PixHandle | null;
  bitwiseAnd(a: PixHandle | null, b: PixHandle | null): PixHandle | null;
  bitwiseXor(a: PixHandle | null, b: PixHandle | null): PixHandle | null;
  blend(a: PixHandle | null, b: PixHandle | null, frac: number): PixHandle | null;
  addBorder(pix: PixHandle | null, t: number, val: number): PixHandle | null;
  sobel(pix: PixHandle | null, orientation: string): PixHandle | null;
  findSkew(pix: PixHandle | null): { angle: number; confidence: number } | null;
  countPixels(pix: PixHandle | null): number;
  connComp(pix: PixHandle | null): Array<{ x: number; y: number; w: number; h: number }> | null;
  histogram(pix: PixHandle | null): number[] | null;
  average(pix: PixHandle | null): number | null;
  toPNG(pix: PixHandle | null): Uint8Array | null;
  toJPEG(pix: PixHandle | null, quality: number): Uint8Array | null;
  toRGBA(pix: PixHandle | null): Uint8Array | null;
  toMask(pix: PixHandle | null): Uint8Array | null;
}
