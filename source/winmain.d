module winmain;

version (Windows):

import core.runtime;
import core.sys.windows.windows;

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
        style: CS_HREDRAW | CS_VREDRAW,
        lpfnWndProc: cast(WNDPROC)&Win32MainWindowCallback,
        hInstance: instance,
        hCursor: LoadCursor(null, IDC_ARROW),
        lpszClassName: "DNginWindowClass",
    };

    if (!RegisterClass(&WindowClass)) return 1;

    enum WindowWidth = 1366;
    enum WindowHeight = 768;

    HWND Window = CreateWindowEx(
                                 0, //WS_EX_TOPMOST|WS_EX_LAYERED,       // extended window style
                                 WindowClass.lpszClassName,          // previously registered class to create
                                 "DNgin",                            // window name or title
                                 WS_OVERLAPPEDWINDOW|WS_VISIBLE,     // window style
                                 CW_USEDEFAULT,                      // X
                                 CW_USEDEFAULT,                      // Y
                                 WindowWidth,
                                 WindowHeight,
                                 null,                               // Parent Window
                                 null,                               // Menu
                                 instance,                           // module instance handle
                                 null                                // lpParam for optional additional data to store with the win
                                );
    if (!Window) return 1;

    while (GlobalRunning) {
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
