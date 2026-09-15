/**
 * Operator protocol — the serializable op descriptions shared by the sync
 * core, the Worker client, and the native oracle harness (design §5.1).
 *
 * The chain builder records Ops on the main thread; run() sends the whole
 * array as one message; the sync core replays it. The native harness parses
 * the same JSON shape so oracle comparisons exercise one description.
 */
export const OP_DEPTH_RULES = {
    // pixConvertTo8 accepts any depth (pixconv.c — the cmap and 1bpp paths
    // expand; 32/24/16 flatten via pixConvertRGBToGrayFast or the weighted
    // path). Output is always 8bpp.
    toGray: { requires: null, produces: 8 },
    // pixThresholdToBinary (binarize.c): 4bpp (per-level cmap semantics)
    // and 8bpp (level threshold) accepted; other depths return null. The
    // 4bpp path is unreachable from the curated API (fromRGBA is 32bpp and
    // only toGray produces 8bpp), so [8] is the honest contract.
    threshold: { requires: [8], produces: 1 },
    otsu: { requires: [8], produces: 1 },
    // pixSauvolaBinarizeTiled (binarize.c): requires 8bpp.
    sauvola: { requires: [8], produces: 1 },
    cleanBackgroundToWhite: { requires: [8, 32], produces: (d) => d },
    sauvolaTiled: { requires: [8], produces: 1 },
    selectByArea: { requires: [1], produces: 1 },
    maskOverColorPixels: { requires: [32], produces: 1 },
    // pixDeskewGeneral (skew.c): for non-1bpp inputs pixConvertTo1 is used
    // only to FIND the angle; the output is pixRotate(origImage) or
    // pixClone(origImage) — any depth accepted, depth preserved.
    deskew: { requires: null, produces: (d) => d },
    // pixRotate/pixScale/pixHShearCenter/pixVShearCenter/pixTranslate/
    // pixClipRectangle/pixAddBorder: depth-preserving on every accepted
    // depth; they return null only on invalid sizes, not on depth.
    rotate: { requires: null, produces: (d) => d },
    scale: { requires: null, produces: (d) => d },
    shear: { requires: null, produces: (d) => d },
    clip: { requires: null, produces: (d) => d },
    translate: { requires: null, produces: (d) => d },
    dilate: { requires: [1], produces: 1 },
    erode: { requires: [1], produces: 1 },
    open: { requires: [1], produces: 1 },
    close: { requires: [1], produces: 1 },
    or: { requires: [1], produces: 1 },
    and: { requires: [1], produces: 1 },
    xor: { requires: [1], produces: 1 },
    // pixBlend (blend.c): accepts nearly any pairing except d1==1 when
    // d2>1; the output takes pixs1's depth. The curated surface only
    // reaches it at 32bpp (fromRGBA), so [32] is the reachable contract.
    blend: { requires: [32], produces: 32 },
    addBorder: { requires: null, produces: (d) => d },
    sobel: { requires: [8], produces: 8 },
};
