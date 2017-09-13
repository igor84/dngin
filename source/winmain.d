module winmain;

version (Windows):

pragma(lib, "user32");
pragma(lib, "gdi32");
pragma(lib, "winmm");
pragma(lib, "opengl32");

import core.runtime;
import core.sys.windows.windows;
import std.windows.syserror;
import std.experimental.logger.core;

bool GlobalRunning = true;

enum uint  KB = 1 << 10;
enum uint  MB = 1 << 20;
enum ulong GB = 1 << 30;
enum ulong TB = GB << 10; 

version(unittest) {
    void main() {}
} else {
    extern (Windows)
    int WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
        int result;

        try {
            Runtime.initialize();

            result = myWinMain(hInstance, hPrevInstance, lpCmdLine, nCmdShow);

            Runtime.terminate();
        } catch (Throwable o) {
            // catch any uncaught exceptions
            import std.utf;
            MessageBox(null, o.toString().toUTFz!LPCTSTR, "Error", MB_OK | MB_ICONEXCLAMATION);
            result = 1;
        }

        return result;
    }
}

int myWinMain(HINSTANCE instance, HINSTANCE prevInstance, LPSTR cmdLine, int cmdShow) {
    WNDCLASS windowClass = {
        style: CS_HREDRAW | CS_VREDRAW | CS_OWNDC | CS_DBLCLKS,
        lpfnWndProc: cast(WNDPROC)&win32MainWindowCallback,
        hInstance: instance,
        hCursor: LoadCursor(null, IDC_ARROW),
        lpszClassName: "DNginWindowClass",
    };

    if (!RegisterClass(&windowClass)) {
        reportSysError("Failed to register window class");
        return 1;
    }

    enum DWORD dwExStyle = 0;
    enum DWORD dwStyle = WS_OVERLAPPEDWINDOW|WS_VISIBLE;

    enum windowWidth = 1366;
    enum windowHeight = 768;

    RECT windowRect = {0, 0, windowWidth, windowHeight};
    AdjustWindowRectEx(&windowRect, dwStyle, false, dwExStyle);

    HWND window = CreateWindowEx(
                                 dwExStyle,                     // extended window style
                                 windowClass.lpszClassName,     // previously registered class to create
                                 "DNgin",                       // window name or title
                                 dwStyle,                       // window style
                                 CW_USEDEFAULT,                 // X
                                 CW_USEDEFAULT,                 // Y
                                 windowRect.right - windowRect.left,
                                 windowRect.bottom - windowRect.top,
                                 null,                          // Parent Window
                                 null,                          // Menu
                                 instance,                      // module instance handle
                                 null                           // lpParam for optional additional data to store with the win
                                );
    if (!window){
        reportSysError("Failed creating a window");
        return 1;
    }

    HDC hdc = GetDC(window);
    if (!hdc) {
        reportSysError("Failed fetching of window device context");
        return 1;
    }

    if (!initOpenGL(hdc)) return 1;

    initMainAllocator();
    import util.windebuglogger;
    MakeWinDebugLoggerDefault();

    initRawInput(window);

    import glrenderer;
    import assetdb;

    auto loadres = loadBmpImage("test.bmp");
    uint textureId;
    if (loadres.status == LoadImageStatus.ok) {
        with (loadres.image) textureId = createTexture(width, height, pixels);
    }

    timeBeginPeriod(1); // We change the Sleep time resolution to 1ms
    initViewport(windowWidth, windowHeight);

    auto shaderProgram = textureId ? GLShaderProgram.textureFill : GLShaderProgram.plainFill;
    auto rect = textureId ? GLObject.textureRect : GLObject.rect;

    import core.time;
    auto oldt = MonoTime.currTime;
    while (GlobalRunning) {
        import std.random;
        import core.thread;
        enum targetDur = dur!"msecs"(40);

        MSG msg;
        while (PeekMessage(&msg, null, 0, 0, PM_REMOVE)) {
            if (!preprocessMessage(msg)) {
                TranslateMessage(&msg);
                DispatchMessage(&msg);
            }
        }

        clearColorBuffer();

        shaderProgram.use();
        rect.draw(textureId);
        SwapBuffers(hdc);

        auto newt = MonoTime.currTime;
        auto fdur = newt - oldt;
        auto i = 0;
        if (fdur < targetDur) {
            Thread.sleep(targetDur - fdur);
            newt = MonoTime.currTime;
            while (newt - oldt < targetDur) {
                newt = MonoTime.currTime;
                i++;
            }
        }
        auto usecs = (newt - oldt).total!"usecs" / 1000f;
        //infof("Frame Time: %sms, FPS: %s, empty loops: %s", usecs, 1000f / usecs, i);
        oldt = newt;
    }

    return 0;
}

extern(Windows)
LRESULT win32MainWindowCallback(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    LRESULT Result;

    switch(message) {
        case WM_QUIT, WM_CLOSE:
            GlobalRunning = false;
            break;

        case WM_CHAR:
            wchar c = cast(wchar)wParam;
            break;

        default:
            Result = DefWindowProc(window, message, wParam, lParam);
            break;
    }

    return Result;
}

void initMainAllocator() {
    import std.experimental.allocator;
    import std.experimental.allocator.mmap_allocator;
    version(LDC) import std.experimental.allocator.building_blocks.region;
    import util.allocators;
    import std.conv : emplace;
    // Calls the getter once before setting it with a new value so it won't override that value later
    // TODO(igors): Once Phobos fixes this remove this line
    processAllocator;

    version(LDC) alias DefRegion = Region!();
    else alias DefRegion = shared SharedRegion!();
    auto memory = cast(ubyte[])MmapAllocator.instance.allocate(1024*MB);
    auto a = cast(DefRegion*)memory.ptr;
    emplace(a, memory[DefRegion.sizeof..$]);
    version(LDC) {
        processAllocator = allocatorObject(a);
        theAllocator = processAllocator;
    } else processAllocator = sharedAllocatorObject(a);
}

bool initOpenGL(HDC hdc) {
    PIXELFORMATDESCRIPTOR pfd = {
        PIXELFORMATDESCRIPTOR.sizeof, // Size Of This Pixel Format Descriptor
        1,                            // Version
        PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER, // Format must support drawing to window and OpenGL
        PFD_TYPE_RGBA,
        24,
        0, 0, 0, 0, 0, 0, 0, 0, // Color Bits Ignored
        0, 0, 0, 0, 0, // No Accumulation Buffer
        0, // Z-Buffer (Depth Buffer)
        0, // No Stencil Buffer
        0, // No Auxiliary Buffer
        0, // Layer type, ignored
        0, // Reserved
        0, 0, 0 // Layer Masks Ignored
    };

    int pixelFormat = ChoosePixelFormat(hdc, &pfd);
    if (!pixelFormat) {
        reportSysError("Failed to find needed pixel format");
        return false;
    }

    if (!SetPixelFormat(hdc, pixelFormat, &pfd)) {
        reportSysError("Failed to set needed pixel format");
        return false;
    }

    HGLRC hrc = wglCreateContext(hdc);
    if (!hrc) {
        reportSysError("Failed to create OpenGL context");
        return false;
    }

    import glrenderer;
    wglMakeCurrent(hdc, hrc);
    DerelictGL3.load();
    return initGLContext();
}

bool preprocessMessage(const ref MSG msg) {
    switch (msg.message) {
        case WM_INPUT:
            RAWINPUT raw;
            UINT size = RAWINPUT.sizeof;
            GetRawInputData(cast(HRAWINPUT)msg.lParam, RID_INPUT, &raw, &size, RAWINPUTHEADER.sizeof);

            if (raw.header.dwType != RIM_TYPEKEYBOARD) return false;

            // Each keyboard will have a different heandle
            HANDLE hd = raw.header.hDevice;

            auto rawKB = &raw.data.keyboard;
            UINT virtualKey = rawKB.VKey;
            UINT flags = rawKB.Flags;
             
            // discard "fake keys" which are part of an escaped sequence
            if (virtualKey == 255) return false;

            if (virtualKey == VK_SHIFT) {
                // correct left-hand / right-hand SHIFT
                virtualKey = MapVirtualKey(rawKB.MakeCode, MAPVK_VSC_TO_VK_EX);
            }

            immutable bool isE0 = (flags & RI_KEY_E0) != 0;
            immutable bool isE1 = (flags & RI_KEY_E1) != 0;

            import std.algorithm.comparison : max;
            enum vkMappingCount = max(
                                    VK_CONTROL, VK_MENU, VK_RETURN, VK_INSERT, VK_DELETE,
                                    VK_HOME, VK_END, VK_PRIOR, VK_NEXT,
                                    VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN, VK_CLEAR
                                    ) + 1;
            static immutable UINT[vkMappingCount] vkMappings = () {
                UINT[vkMappingCount] res;
                res[VK_CONTROL] = VK_RCONTROL;
                res[VK_MENU] = VK_RMENU;
                res[VK_RETURN] = VK_SEPARATOR;
                res[VK_INSERT] = VK_NUMPAD0;
                res[VK_DELETE] = VK_DECIMAL;
                res[VK_HOME] = VK_NUMPAD7;
                res[VK_END] = VK_NUMPAD1;
                res[VK_PRIOR] = VK_NUMPAD9;
                res[VK_NEXT] = VK_NUMPAD3;
                res[VK_LEFT] = VK_NUMPAD4;
                res[VK_RIGHT] = VK_NUMPAD6;
                res[VK_UP] = VK_NUMPAD8;
                res[VK_DOWN] = VK_NUMPAD2;
                res[VK_CLEAR] = VK_NUMPAD5;
                return res;
            }();

            if (isE0) {
                if (virtualKey < vkMappings.length && vkMappings[virtualKey] > 0) {
                    virtualKey = vkMappings[virtualKey];
                }
            } else if (virtualKey == VK_CONTROL) {
                virtualKey = VK_LCONTROL;
            } else if (virtualKey == VK_MENU) {
                virtualKey = VK_LMENU;
            }


            // a key can either produce a "make" or "break" scancode. this is used to differentiate between down-presses and releases
            // see http://www.win.tue.nl/~aeb/linux/kbd/scancodes-1.html
            immutable bool isKeyUp = (flags & RI_KEY_BREAK) != 0;

            // TODO: Do we need to give some raw inputs to OS or can we just eat them all?
            // auto praw = &raw;
            // DefRawInputProc(&praw, 1, RAWINPUTHEADER.sizeof);

            return true;

        default:
            return false;
    }
}

bool initRawInput(HWND hWnd) {
    // TODO: See about disabling win key in full screen: https://msdn.microsoft.com/en-us/library/windows/desktop/ee416808(v=vs.85).aspx
    RAWINPUTDEVICE device;
    device.usUsagePage = 0x01;
    device.usUsage = 0x06;
    // If we do not want to generate legacy messages such as WM_KEYDOWN set this to RIDEV_NOLEGACY.
    // Note that in that case things like ALT+F4 will stop working
    device.dwFlags = 0;
    device.hwndTarget = hWnd;
    if (!RegisterRawInputDevices(&device, 1, device.sizeof)) {
        reportSysError("Failed to register raw keyboard input");
        return false;
    }

    version(none) {
        enum maxDevices = 100;
        UINT nDevices = maxDevices;
        RAWINPUTDEVICELIST[maxDevices] rawInputDeviceList;
        UINT rawDeviceCount = GetRawInputDeviceList(rawInputDeviceList.ptr, &nDevices, RAWINPUTDEVICELIST.sizeof);
        if (rawDeviceCount == cast(UINT)-1) {
            // Failed fatching the list
            return false;
        }
        foreach(i; 0..rawDeviceCount) {
            RAWINPUTDEVICELIST r = RawInputDeviceList[i];
            RID_DEVICE_INFO buf;
            UINT size = buf.sizeof;
            UINT res = GetRawInputDeviceInfoA(r.hDevice, RIDI_DEVICEINFO, &buf, &size);
            if (res == cast(UINT)-1) continue;
            if (buf.dwType == RIM_TYPEKEYBOARD) {
                RID_DEVICE_INFO_KEYBOARD keyboard = buf.keyboard;
                if (keyboard.dwNumberOfKeysTotal < 15) {
                    // Some very specific "gaming keyboards" can have only the necessary few keys
                    // but if it is under 15 we consider this invalid keyboard
                    // TODO: Should we use this list so the API can return a list of available keyboards?
                }
            }
        }
    }

    return true;
}

void reportSysError(string error) {
    import std.utf;
    string msg = error ~ ": " ~ sysErrorString(GetLastError());
    MessageBox(null, msg.toUTFz!LPCTSTR, "Error", MB_OK | MB_ICONEXCLAMATION);
}
