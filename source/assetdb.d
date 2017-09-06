module assetdb;

import std.experimental.allocator;

version(DigitalMars) version(X86_64) version(D_SIMD) version = DMDSIMD;

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

	uint redMask;       // Mask identifying bits of red component
	uint greenMask;     // Mask identifying bits of green component
	uint blueMask;      // Mask identifying bits of blue component
	uint alphaMask;     // Mask identifying bits of alpha component
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
}

struct ImageData {
    int width;
    int height;
    uint[] pixels;
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

    if (header.fileType != 0x4d42) return result;
    if (header.width < 1 || header.height == 0) return result;
    if (header.compression != 3) return result;
    if (header.bitmapOffset < WinBmpFileHeader.sizeof) return result;
    if (header.bitsPerPixel != 32) return result;
    
    auto bottomUp = true;
    if (header.height < 0) {
        header.height = -header.height;
        bottomUp = false;
    }

    if (file.content.length < header.bitmapOffset + header.width * header.height * uint.sizeof) return result;

    ImageData tresult = {header.width, header.height, };
    tresult.pixels = (cast(uint*)(file.content.ptr + header.bitmapOffset))[0..tresult.width * tresult.height];

    assert(header.redMask);
    assert(header.greenMask);
    assert(header.blueMask);
    assert(header.alphaMask);

    // Convert to RGBA format
    import core.time;
    auto start = MonoTime.currTime;
    
    import core.bitop;
    int rPos = bsf(header.redMask);
    int gPos = bsf(header.greenMask);
    int bPos = bsf(header.blueMask);
    int aPos = bsf(header.alphaMask);

    void[] rpixels = theAllocator.alignedAllocate(tresult.width * tresult.height * uint.sizeof, 16);
    rpixels[] = tresult.pixels[];
    tresult.pixels = (cast(uint*)rpixels.ptr)[0..rpixels.length / 4];

    auto pixelsToProcess = tresult.pixels;

    version(DMDSIMD) {
        import core.cpuid : ssse3;
        if (ssse3) {
            import core.simd;

            ubyte16[] pixels = (cast(ubyte16*)(tresult.pixels.ptr))[0..tresult.pixels.length / 4];
            immutable uint mask = (aPos << 21) | (bPos << 13) | (gPos << 5) | (rPos >> 3);
            immutable uint[4] maskArray = [mask, mask + 0x04040404, mask + 0x08080808, mask + 0x0c0c0c0c];
            ubyte16* masks = cast(ubyte16*)maskArray.ptr;

            foreach (ref c; pixels) {
                c = __simd(XMM.PSHUFB, c, *masks);
            }
            // Reset pixelsToProcess to point to leftover pixels if there are any
            pixelsToProcess = tresult.pixels[($ & ~3) .. $];
        }
    }

    // TODO(igors): Change this to LDC once I figure out how to make it work
    // Or just leave the code bellow since LDC seems to optimize it to SIMD instructions pretty good.
    version(none) {
        import core.cpuid : ssse3;
        if (ssse3) {
            import core.simd;
            import ldc.gccbuiltins_x86;

            ubyte16* pixels = cast(ubyte16*)(tresult.pixels.ptr);
            immutable uint mask = (aPos << 21) | (bPos << 13) | (gPos << 5) | (rPos >> 3);
            uint[4] maskArray = [mask, mask + 0x04040404, mask + 0x08080808, mask + 0x0c0c0c0c];
            ubyte16* masks = cast(ubyte16*)maskArray.ptr;

            foreach (ref c; pixels[0..tresult.pixels.length / 4]) {
                c = __builtin_ia32_pshufb128(c, *masks);
            }
            pixelsToProcess = tresult.pixels[($ & ~3) .. $];
        }
    }

    foreach (ref c; pixelsToProcess) {
        uint r = (c & header.redMask) >> rPos;
        uint g = (c & header.greenMask) >> gPos;
        uint b = (c & header.blueMask) >> bPos;
        uint a = (c & header.alphaMask) >> aPos;

        c = (a << 24) | (b << 16) | (g << 8) | (r << 0);
    }
    result = (MonoTime.currTime - start).total!"usecs" / 1000f;
    return result;
}