module winmain;

version (Windows):

pragma(lib, "gdi32");
pragma(lib, "winmm");
pragma(lib, "opengl32");

import core.runtime;
import core.sys.windows.windows;
import derelict.opengl;

bool GlobalRunning = true;

extern (Windows)
int WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    int result;

    try {
        Runtime.initialize();

        result = myWinMain(hInstance, hPrevInstance, lpCmdLine, nCmdShow);

        Runtime.terminate();
    } catch (Throwable o) {
        // catch any uncaught exceptions
        result = 1;
    }

    return result;
}

int myWinMain(HINSTANCE instance, HINSTANCE prevInstance, LPSTR cmdLine, int cmdShow) {
    WNDCLASS WindowClass = {
        style: CS_HREDRAW | CS_VREDRAW | CS_OWNDC | CS_DBLCLKS,
        lpfnWndProc: cast(WNDPROC)&Win32MainWindowCallback,
        hInstance: instance,
        hCursor: LoadCursor(null, IDC_ARROW),
        lpszClassName: "DNginWindowClass",
    };

    if (!RegisterClass(&WindowClass)) return 1;

    enum DWORD dwExStyle = 0;
    enum DWORD dwStyle = WS_OVERLAPPEDWINDOW|WS_VISIBLE;

    enum WindowWidth = 1366;
    enum WindowHeight = 768;

    RECT windowRect = {0, 0, WindowWidth, WindowHeight};
    AdjustWindowRectEx(&windowRect, dwStyle, false, dwExStyle);

    HWND Window = CreateWindowEx(
                                 dwExStyle,                     // extended window style
                                 WindowClass.lpszClassName,     // previously registered class to create
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
    if (!Window){
        //TODO: Error handling
        return 1;
    }

    HDC hdc = GetDC(Window);
    if (!hdc) {
        //TODO: Error handling
        return 1;
    }

    if (!initOpenGL(hdc)) return 1;

    timeBeginPeriod(1); // We change the Sleep time resolution to 1ms
    glViewport(0, 0, WindowWidth, WindowHeight);

    import core.time;
    auto oldt = MonoTime.currTime;
    while (GlobalRunning) {
        import std.random;
        import core.thread;
        enum targetDur = dur!"msecs"(40);

        MSG msg;
        while (PeekMessage(&msg, null, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }

        glClearColor(1.0f, uniform(0f, 0.4f), 1.0f, 0.0f);
        glClear(GL_COLOR_BUFFER_BIT);
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
        Log!"Frame Time: %sms, FPS: %s, empty loops: %s"(usecs, 1000f / usecs, i);
        oldt = newt;
    }

    return 0;
}

extern(Windows)
LRESULT Win32MainWindowCallback(HWND Window, UINT Message, WPARAM WParam, LPARAM LParam) {
    LRESULT Result;

    switch(Message) {
        case WM_QUIT, WM_CLOSE:
            GlobalRunning = false;
            break;

        default:
            Result = DefWindowProc(Window, Message, WParam, LParam);
            break;
    }

    return Result;
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
        //TODO: Error handling
        return false;
    }

    if (!SetPixelFormat(hdc, pixelFormat, &pfd)) {
        //TODO: Error handling
        return false;
    }

    HGLRC hrc = wglCreateContext(hdc);
    if (!hrc) {
        //TODO: Error handling
        return false;
    }

    wglMakeCurrent(hdc, hrc);
    DerelictGL3.load();
    //DerelictGL3.reload();
    return true;
}

import std.traits : isSomeString;
void Log(alias message, Args...)(Args args) if (isSomeString!(typeof(message))) {
    static if (args.length == 0) {
        OutputDebugStringA(message ~ "\n");
    } else {
        import std.format;
        char[400] buf;
        auto res = buf[].sformat(message ~ "\n\0", args);
        OutputDebugStringA(res.ptr);
    }
}