module assetdb;

import std.experimental.allocator;

private struct ColorChannelMasks {
    align(1):
    uint r;    // Mask identifying bits of red component
    uint g;    // Mask identifying bits of green component
    uint b;    // Mask identifying bits of blue component
    uint a;    // Mask identifying bits of alpha component
}

private struct WinBmpFileHeader {
    align(1):
    ushort fileType;     // File type, always 4D42h ("BM")
    uint   fileSize;     // Size of the file in bytes
    ushort reserved1;    // Always 0
    ushort reserved2;    // Always 0
    uint   bitmapOffset; // Starting position of image data in bytes

    uint   size;            // Size of this header in bytes
    int   width;           // Image width in pixels
    int   height;          // Image height in pixels, if positive then bottom up rows
    ushort planes;          // Number of color planes, always 1
    ushort bitsPerPixel;    // Number of bits per pixel
    uint   compression;     // Compression methods used, for >=16bit always 3
    uint   sizeOfBitmap;    // Size of bitmap in bytes
    int   horzResolution;  // Horizontal resolution in pixels per meter
    int   vertResolution;  // Vertical resolution in pixels per meter
    uint   colorsUsed;      // Number of colors in the image, 0 for >=16bit
    uint   colorsImportant; // Minimum number of important colors

    ColorChannelMasks masks;

    /+
    // We are not interested in color space data
    uint csType;        // Color space type
    int  redX;          // X coordinate of red endpoint
    int  redY;          // Y coordinate of red endpoint
    int  redZ;          // Z coordinate of red endpoint
    int  greenX;        // X coordinate of green endpoint
    int  greenY;        // Y coordinate of green endpoint
    int  greenZ;        // Z coordinate of green endpoint
    int  blueX;         // X coordinate of blue endpoint
    int  blueY;         // Y coordinate of blue endpoint
    int  blueZ;         // Z coordinate of blue endpoint
    uint gammaRed;      // Gamma red coordinate scale value
    uint gammaGreen;    // Gamma green coordinate scale value
    uint gammaBlue;     // Gamma blue coordinate scale value
    +/
}

struct ImageData {
    int width;
    int height;
    uint[] pixels;
}

pragma(inline, true)
T[] asArrayOf(T, V)(const ref V[] inArray) {
    return (cast(T*)inArray.ptr)[0..(inArray.length * V.sizeof / T.sizeof)];
}

float loadBmpImage(const(char)[] path) {
    import util.winfile;
    import std.experimental.allocator.mmap_allocator;
    import std.experimental.allocator.building_blocks.region;

    auto tmpAllocator = Region!MmapAllocator(100 * 1024 * 1024);
    FileReadResult file = ReadEntireFile(path, allocatorObject(&tmpAllocator));
    float result = 0f;

    if (!file.status.isOk) return result;

    if (file.content.length <= WinBmpFileHeader.sizeof) return result;

    auto header = cast(WinBmpFileHeader*)file.content.ptr;

    // Validate file data
    if (header.fileType != 0x4d42) return result;
    if (header.width <= 0) return result;
    if (header.height <= 0) return result; // We only support bottom up format where height is positive
    if (header.compression != 3 && header.compression != 0) return result;
    if (header.bitmapOffset < 40) return result;
    if (header.bitsPerPixel < 24) return result;
    if ((header.bitsPerPixel == 32) && (!header.masks.r || !header.masks.g || !header.masks.b || !header.masks.a)) return result;
    
    auto numpixels = header.width * header.height;
    auto numbytes = numpixels * (header.bitsPerPixel >> 3);

    if (file.content.length < header.bitmapOffset + numbytes) return result;
    ubyte[] rawpixels = (cast(ubyte*)(file.content.ptr + header.bitmapOffset))[0..numbytes];

    import core.time;
    auto start = MonoTime.currTime;

    ubyte[] apixels = cast(ubyte[])theAllocator.alignedAllocate(numpixels * uint.sizeof, 16);
    ImageData tresult = {header.width, header.height};

    if (header.bitsPerPixel == 32) {
        tresult.pixels = rawpixels.ensureRgbaOrder(header.masks, apixels);
    } else {
        tresult.pixels = rawpixels.convert24to32Rgba(apixels);
    }
    result = (MonoTime.currTime - start).total!"usecs" / 1000f;
    return result;
}

version(DigitalMars) version(X86_64) version(D_SIMD) version = DLANGSIMD;
version(LDC) version(X86_64) version = DLANGSIMD;

version(LDC) import ldc.attributes; //Needed for LDC ssse3
else private struct target { string specifier; }
@target("ssse3")
private uint[] ensureRgbaOrder(ubyte[] rawpixels, const ref ColorChannelMasks masks, ubyte[] apixels) {
    import core.bitop;

    // Just copy raw pixels to aligned memory
    apixels[] = rawpixels[];
    auto result = apixels.asArrayOf!uint();

    if (masks.r == 0xff && masks.g == 0xff00 && masks.b == 0xff0000) return result;

    int rPos = bsf(masks.r);
    int gPos = bsf(masks.g);
    int bPos = bsf(masks.b);
    int aPos = bsf(masks.a);

    uint[] pixelsToProcess = apixels.asArrayOf!uint();

    version(DLANGSIMD) {
        // If possible use SSSE3 shuffle instruction to process 4 pixels at once
        import core.cpuid : ssse3;
        if (ssse3) {
            import core.simd;

            ubyte16[] pixels = apixels.asArrayOf!ubyte16();
            immutable uint mask = (aPos << 21) | (bPos << 13) | (gPos << 5) | (rPos >> 3);
            align(16) immutable uint[4] maskArray = [mask, mask + 0x04040404, mask + 0x08080808, mask + 0x0c0c0c0c];
            ubyte16* simdMasks = cast(ubyte16*)maskArray.ptr;

            foreach (ref c; pixels) {
                version(LDC) {
                    import ldc.gccbuiltins_x86;
                    c = __builtin_ia32_pshufb128(c, *simdMasks);
                } else {
                    c = __simd(XMM.PSHUFB, c, *simdMasks);
                }
            }
            // Reset pixelsToProcess to point to leftover pixels if there are any
            pixelsToProcess = pixelsToProcess[($ & ~3) .. $];
        }
    }

    foreach (ref c; pixelsToProcess) {
        uint r = (c & masks.r) >> rPos;
        uint g = (c & masks.g) >> gPos;
        uint b = (c & masks.b) >> bPos;
        uint a = (c & masks.a) >> aPos;

        c = (a << 24) | (b << 16) | (g << 8) | r;
    }

    return result;
}

unittest {
    ubyte[24] rawpixels = [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24];
    align(16) ubyte[24] apixels;
    auto masks = ColorChannelMasks(0xff, 0xff0000, 0xff000000, 0xff00);
    auto res = rawpixels[].ensureRgbaOrder(masks, apixels[]);
    assert(res == [0x02040301, 0x06080705, 0x0a0c0b09, 0x0e100f0d, 0x12141311, 0x16181715]);
    masks = ColorChannelMasks(0xff, 0xff00, 0xff0000, 0xff000000);
    res = rawpixels[].ensureRgbaOrder(masks, apixels[]);
    assert(res == [0x04030201, 0x08070605, 0x0c0b0a09, 0x100f0e0d, 0x14131211, 0x18171615]);
}

private uint[] convert24to32Rgba(ubyte[] rawpixels, ubyte[] apixels) {
    uint[] destpixels = apixels.asArrayOf!uint();
    uint d = 0;
    for (auto i = 0; i + 11 < rawpixels.length; i += 12) {
        // Layout will be:
        // InMemory: B1G1R1 B2G2R2 B3G3R3 B4G4R4 -> R1G1B1FF R2G2B2FF R3G3B3FF R4G4B4FF
        // InRegisters: B2R1G1B1 G3B3R2G2 R4G4B4R3 -> FFB1G1R1 FFB2G2R2 FFB3G3R3 FFB4G4R4

        auto p = rawpixels[i..i+12];
        destpixels[d++] = 0xff000000 | (p[0] << 16) | (p[1] << 8) | p[2];
        destpixels[d++] = 0xff000000 | (p[3] << 16) | (p[4] << 8) | p[5];
        destpixels[d++] = 0xff000000 | (p[6] << 16) | (p[7] << 8) | p[8];
        destpixels[d++] = 0xff000000 | (p[9] << 16) | (p[10] << 8) | p[11];
    }
    auto left = rawpixels.length % 12;
    if (left > 0) {
        auto p = rawpixels[$-left..$];
        destpixels[d++] = 0xff000000 | (p[0] << 16) | (p[1] << 8) | p[2];
        if (left > 3) destpixels[d++] = 0xff000000 | (p[3] << 16) | (p[4] << 8) | p[5];
        if (left > 6) destpixels[d] = 0xff000000 | (p[6] << 16) | (p[7] << 8) | p[8];
    }

    return apixels.asArrayOf!uint();
}

unittest {
    ubyte[24] rawpixels = [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24];
    align(16) ubyte[32] pixelBuffer;
    ubyte[] apixels = pixelBuffer[0..24];
    auto res = rawpixels[0..18].convert24to32Rgba(apixels);
    assert(res == [0xff010203, 0xff040506, 0xff070809, 0xff0a0b0c, 0xff0d0e0f, 0xff101112]);

    apixels = pixelBuffer;
    res = rawpixels[].convert24to32Rgba(apixels);
    assert(res == [0xff010203, 0xff040506, 0xff070809, 0xff0a0b0c, 0xff0d0e0f, 0xff101112, 0xff131415, 0xff161718]);
}