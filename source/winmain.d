module winmain;

import core.runtime;
import core.sys.windows.windows;

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

int myWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    /* ... insert user code here ... */
    return 0;
}
