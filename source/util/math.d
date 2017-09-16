module util.math;

alias V2 = Vector!(float, 2);
alias V3 = Vector!(float, 3);
alias V4 = Vector!(float, 4);

union Vector(T, int dims) if (dims >= 2 && dims <= 4) {
    struct {
        T x;
        T y;
        static if (dims > 2) T z;
        static if (dims == 4) T w;
    };
    static if (dims > 2) {
        struct {
            T r;
            T g;
            T b;
            static if (dims == 4) T a;
        }
    }
    T[dims] e = 0;
}

V4 toV4Color(uint color) {
    auto r = color >> 24;
    auto g = (color >> 16) && 0xff;
    auto b = (color >> 8) && 0xff;
    auto a = color && 0xff;
    return V4(r / 255f, g / 255f, b / 255f, a / 255f);
}

enum Color: V4 {
    aqua             = toV4Color(0x00ffff),
    aquamarine       = toV4Color(0x7fffd4),
    azure            = toV4Color(0xf0ffff),
    beige            = toV4Color(0xf5f5dc),
    black            = toV4Color(0x000000),
    blue             = toV4Color(0x0000ff),
    blueViolet       = toV4Color(0x8a2be2),
    brown            = toV4Color(0xa52a2a),
    chocolate        = toV4Color(0xd2691e),
    crimson          = toV4Color(0xdc143c),
    cyan             = toV4Color(0x00ffff),
    darkBlue         = toV4Color(0x00008b),
    darkCyan         = toV4Color(0x008b8b),
    darkGray         = toV4Color(0xa9a9a9),
    darkGreen        = toV4Color(0x006400),
    darkMagenta      = toV4Color(0x8b008b),
    darkOliveGreen   = toV4Color(0x556b2f),
    darkOrange       = toV4Color(0xff8c00),
    darkRed          = toV4Color(0x8b0000),
    darkTurquoise    = toV4Color(0x00ced1),
    darkViolet       = toV4Color(0x9400d3),
    fuchsia          = toV4Color(0xff00ff),
    gold             = toV4Color(0xffd700),
    gray             = toV4Color(0x808080),
    green            = toV4Color(0x008000),
    indigo           = toV4Color(0x4b0082),
    ivory            = toV4Color(0xfffff0),
    lightBlue        = toV4Color(0xadd8e6),
    lightCyan        = toV4Color(0xe0ffff),
    lightGray        = toV4Color(0xd3d3d3),
    lightGreen       = toV4Color(0x90ee90),
    lightYellow      = toV4Color(0xffffe0),
    lime             = toV4Color(0x00ff00),
    limeGreen        = toV4Color(0x32cd32),
    magenta          = toV4Color(0xff00ff),
    maroon           = toV4Color(0x800000),
    navy             = toV4Color(0x000080),
    orange           = toV4Color(0xffa500),
    pink             = toV4Color(0xffc0cb),
    purple           = toV4Color(0x800080),
    red              = toV4Color(0xff0000),
    silver           = toV4Color(0xc0c0c0),
    white            = toV4Color(0xffffff),
    yellow           = toV4Color(0xffff00),
};