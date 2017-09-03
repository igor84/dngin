module util.winfile;

import std.experimental.allocator;

enum FileReadStatus {
    ok,
    openFailed,
    fetchingFileSizeFailed,
    memoryAllocationFailed,
    readFileFailed,
    readSizeBad,
}

bool isOk(FileReadStatus status) {
    return status == FileReadStatus.ok;
}

struct FileReadResult {
    FileReadStatus status;
    byte[] content;
}

FileReadResult ReadEntireFile(const(char)[] path, IAllocator allocator = theAllocator)
in {
    assert(path.length);
}
body {
    import core.sys.windows.windows;

    HANDLE file = CreateFileA(path.ptr,
                              GENERIC_READ,         // Desired access
                              FILE_SHARE_READ,      // Share mode
                              null,                 // Security Attributes
                              OPEN_EXISTING,        // Desired action
                              0,                    // File attributes
                              null);                // Template file, not used when reading file

    if (file == INVALID_HANDLE_VALUE) return FileReadResult(FileReadStatus.openFailed);
    scope(exit) CloseHandle(file);

    LARGE_INTEGER size;
    if (!GetFileSizeEx(file, &size)) return FileReadResult(FileReadStatus.fetchingFileSizeFailed);

    byte[] content = allocator.makeArray!byte(size.QuadPart);
    if (content is null) return FileReadResult(FileReadStatus.memoryAllocationFailed);

    FileReadResult result = ReadFileIntoBuffer(file, content);

    if (!result.status.isOk()) theAllocator.dispose(content);

    return result;
}

private FileReadResult ReadFileIntoBuffer(void* file, byte[] buffer)
in {
    assert(file);
    assert(buffer);
}
body {
    import core.sys.windows.windows;

    DWORD BytesRead;
    if (!ReadFile(file, buffer.ptr, cast(DWORD)buffer.length, &BytesRead, null)) {
        return FileReadResult(FileReadStatus.readFileFailed);
    }

    if (BytesRead != buffer.length) return FileReadResult(FileReadStatus.readSizeBad);

    FileReadResult result;
    result.content = buffer;

    return result;
}