module util.windebuglogger;

import std.experimental.logger.core;
import std.experimental.allocator;

class WinDebugLogger : Logger {
    this(LogLevel lv) @safe {
        super(lv);
    }

    override void finishLogMsg() {
        static if (isLoggingActive) {
            msgAppender.put("\n\0");
            super.finishLogMsg();
        }
    }

    override void writeLogMsg(ref LogEntry payload) @trusted {
        import core.sys.windows.windows : OutputDebugStringA;
        OutputDebugStringA(payload.msg.ptr);
    }
}

void makeWinDebugLoggerDefault(IAllocator a = theAllocator) {
    stdThreadLocalLog; // Calling getter once so it doesn't later override the value we set
    stdThreadLocalLog = a.make!(WinDebugLogger)(LogLevel.all);
}