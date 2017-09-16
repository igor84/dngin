module util.helpers;

enum uint  KB = 1 << 10;
enum uint  MB = 1 << 20;
enum ulong GB = 1 << 30;
enum ulong TB = GB << 10; 

pragma(inline, true)
bool isOk(T)(T status) if (is(T == enum) && is(typeof(T.ok))) {
    return status == T.ok;
}