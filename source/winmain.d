module winmain;

version (Windows):

pragma(lib, "gdi32");
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

    while (GlobalRunning) {
        glViewport(0, 0, WindowWidth, WindowHeight);
        glClearColor(1.0f, 0.0f, 1.0f, 0.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        SwapBuffers(hdc);

        MSG msg;
        while (PeekMessage(&msg, null, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
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
    DerelictGL3.reload();
    return true;
}