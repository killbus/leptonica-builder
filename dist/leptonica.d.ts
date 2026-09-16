// TypeScript bindings for emscripten-generated code.  Automatically generated at compile time.
interface WasmModule {
}

export interface ClassHandle {
  isAliasOf(other: ClassHandle): boolean;
  delete(): void;
  deleteLater(): this;
  isDeleted(): boolean;
  // @ts-ignore - If targeting lower than ESNext, this symbol might not exist.
  [Symbol.dispose](): void;
  clone(): this;
}
export interface Pix extends ClassHandle {
}

interface EmbindModule {
  Pix: {};
  toGray(_0: Pix | null): Pix | null;
  bitwiseOr(_0: Pix | null, _1: Pix | null): Pix | null;
  bitwiseAnd(_0: Pix | null, _1: Pix | null): Pix | null;
  bitwiseXor(_0: Pix | null, _1: Pix | null): Pix | null;
  destroyPix(_0: Pix | null): void;
  pixWidth(_0: Pix | null): number;
  pixHeight(_0: Pix | null): number;
  pixDepth(_0: Pix | null): number;
  threshold(_0: Pix | null, _1: number): Pix | null;
  maskOverColorPixels(_0: Pix | null, _1: number, _2: number): Pix | null;
  deskew(_0: Pix | null, _1: number): Pix | null;
  clip(_0: Pix | null, _1: number, _2: number, _3: number, _4: number): Pix | null;
  translate(_0: Pix | null, _1: number, _2: number): Pix | null;
  morphDilate(_0: Pix | null, _1: number, _2: number): Pix | null;
  morphErode(_0: Pix | null, _1: number, _2: number): Pix | null;
  morphOpen(_0: Pix | null, _1: number, _2: number): Pix | null;
  morphClose(_0: Pix | null, _1: number, _2: number): Pix | null;
  addBorder(_0: Pix | null, _1: number, _2: number): Pix | null;
  countPixels(_0: Pix | null): number;
  toGrayWeighted(_0: Pix | null, _1: number, _2: number, _3: number): Pix | null;
  otsu(_0: Pix | null, _1: number, _2: number): Pix | null;
  sauvola(_0: Pix | null, _1: number, _2: number): Pix | null;
  cleanBackgroundToWhite(_0: Pix | null, _1: number, _2: number, _3: number): Pix | null;
  sauvolaTiled(_0: Pix | null, _1: number, _2: number, _3: number, _4: number): Pix | null;
  scale(_0: Pix | null, _1: number, _2: number): Pix | null;
  blend(_0: Pix | null, _1: Pix | null, _2: number): Pix | null;
  fromRGBA(_0: any, _1: number, _2: number): Pix | null;
  selectByArea(_0: Pix | null, _1: number, _2: number, _3: any): Pix | null;
  rotate(_0: Pix | null, _1: number, _2: any): Pix | null;
  shear(_0: Pix | null, _1: any, _2: number): Pix | null;
  sobel(_0: Pix | null, _1: any): Pix | null;
  findSkew(_0: Pix | null): any;
  connComp(_0: Pix | null): any;
  histogram(_0: Pix | null): any;
  average(_0: Pix | null): any;
  toPNG(_0: Pix | null): any;
  toJPEG(_0: Pix | null, _1: number): any;
  toRGBA(_0: Pix | null): any;
  toMask(_0: Pix | null): any;
}

export type MainModule = WasmModule & EmbindModule;
export default function MainModuleFactory (options?: unknown): Promise<MainModule>;
