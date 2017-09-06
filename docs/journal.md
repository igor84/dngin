# DNgin Journal

### 1. Where to start

Starting decisions:

- Use D Language (there are enough C++ engines)
- Everything must be well documented from day one and I need to come up with nice way to organize documentation
- I want the engine to be made of modules that can have different implementation but same API
- I should be able to build the modules as DLL or to statically link them at any time
- Every change must be tested with both DMD and LDC in debug and in release mode so I can detect problematic stuff as soon as I add it
- After each change check the executable size so I can determine what affects it the most
- Initial plan is basic windows platform layer, then android, maybe iOS and maybe Linux
- I am targeting minimal external dependencies and if I need some library available in C or C++ I should consider rewriting it in D

First day I setup a Visual Studio project and dub build and I make basic window app that just opens a window
and shuts down on window close.

Next step is to initialize OpenGL and display a triangle.

### 2. OpenGL Initialization
After basic OpenGL initialization I needed to find OpenGL bindings for D in order to call OpenGL functions.
I first looked if I can use DerelictGLES since I want to support mobile platforms but it seems DerelictGLES
only supports Windows and Mac. Will have to check this on the forum. According to
[this site](https://www.saschawillems.de/?page_id=1822) using GLES on windows is also not straightforward so
I just decided to use DerelictGL3 for now.

I added it to dub dependencies and run `dub upgrade` but to my disappointment it didn't download the packages
in the project directory but somewhere under Windows Users dir. This meant I can't easily use them from
Visual Studio so I decided to also add them as git submodules, create and setup VS projects for them and mark
them as dependant projects. After testing all configurations I found that 32 bit builds under LDC and only
Release 32 bit build under DMD crash when calling `DerelictGL3.reload()`. After a bit of debugging I found that
it actually happens after ret instruction from glloader's `bindGLFunc`. Will also have to ask about this on the forum.

At least on 64bit builds I now have a beautiful window filled with hideous purple :).

### 3. First hurdles
First I added a clean Log function that calls OutputDebugStringA so I easier try some things. I learned here
that LDC uses older version of Phobos standard library and it doesn't have sformat version that takes format
string as template param. So I next decided to try and make FPS fixed.

After some searching how OpenGL vsync is done (wglSwapIntervalEXT) I found that Derelict doesn't have this
function although it did have it in earlier version. DLang forum is not working so I couldn't learn anything
there. Instead of using vsync for now I added Thread.Sleep to get targeted frame rate and I ended up reading
about [timeBeginPeriod](https://randomascii.wordpress.com/2013/07/08/windows-timer-resolution-megawatts-wasted/)
in order to increase the resolution of the Sleep timer.

The reason I want to have fixed FPS is so that I can next work on input handling and testing it in conditions
where main thread has some busy period between processing events, which is realistic behaviour for games.

### 4. Keyboard Input
Started implementing keyboard input based on [this](https://blog.molecular-matters.com/2011/09/05/properly-handling-keyboard-input/).
Got info that DerelictGLES is not maintained for some time and that DerelictGL3 is missing some functions because
it is in beta and they are in progress. I managed to find why 32 bit builds were crashing on DerelictGL3.reload call.
It turned out `extern(C)` on getProcAddress should have been `extern(Windows)`. I reported it on github.
I also added some error handling.

### 5. OpenGL
Following a great tutorial at https://learnopengl.com I implemented OpenGL code for drawing a rectangle.

### 6. Loading images, actually memory allocation
Now that I have a rectangle I want to try a texture. I looked through existing image loading libs like
dlib and imageformats but there were a few minor things I didn't like there and I mostly wanted to learn
about formats I want to load so I decided to implement it myself. Next I looked at file IO Phobos provides
but it turned out all its functions rely on GC so it turns out I have to write this too :). After reading
on CreateFile, GetFileSizeEx and ReadFile on MSDN I got something implemented but now I need to get the
memory for it from somewhere. So I did more reading on std.experimental.allocator package in Phobos. It
promissed so much but turned out pretty buggy. I couldn't get this to work:
```
theAllocator = allocatorObject(Region!MmapAllocator(1024*MB));
```
First issue was that Region struct that is created here is also immediatelly destroyed thus releasing
just allocated memory. Next I tried this:
```
theAllocator = allocatorObject(Region!()(cast(ubyte[])MmapAllocator.instance.allocate(1024*MB)));
```
This also didn't work because if I got it right it turned out allocatorObject constructed around
this allocator never sets its internal impl variable to the given allocator. After a lot of debugging
and reading through the issues I finally got it working by actually passing a pointer to the allocator
to allocatorObject function:
```
auto newAlloc = Region!()(cast(ubyte[])MmapAllocator.instance.allocate(1024*MB));
theAllocator = allocatorObject(&newAlloc);
```
This is far from ideal because newAlloc must now be defined in main function so it remains alive throughout
program's execution since it is on stack. Better solution is to emplace the Region into memory allocated 
from MmapAllocator. At this point I also realized I actually want this to be shared allocator but Region
doesn't have a shared implementation. After a few days of reading, implementing and debugging I finally
wrote and succesfuly used a shared region allocator. I also tried to fix the defficiency of the first method
by reserving first two bytes of allocated memory for counting references to that memory so I can only free
it in the destructor if atomic decrease puts it bellow 0. Unfortunately I couldn't get it to compile since
I kept getting that destructor is not defined for non-shared object although I didn't have a non-shared
object anywhere. I tried removing shared from the destructor but then I just got the error that destructor
for shared object is not defined on another place, and I couldn't find a way to define both shared and
non-shared destructor.

### 7. Now really loading images
By following bmp file format documentation I found online and the code I wrote earlier while translating
Casey Muratori's Handmade Hero I implemented basic loading of bitmap. I only support one compression format.
I also included the code to rearrange color channels so they are in order OpenGL can later receive them.
Here I found one more bug with the allocators: if processAllocator getter is called for the first time after
setting it to something the getter will overwrite the set value with default processAllocator. After I
solved that I also got interested in trying to reorder channels with SIMD instructions. I managed to find
that SSSE3 PSHUFB instruction can do what I need and implemented it. This made reordering 8 times faster.
Next I tried it with LDC but it turned out it doesn't support core.simd package __simd function. I got
some suggestions on the forum to try ldc.gccbuiltins_x86 package, but it just gave me some LLVM error. I
also tried looking what kind of code is produced by LDC in optimized build and it turned out it actually
produced SIMD instructions but there is a number of them so it seems it went through a bit more complicated
process to arrive to the same result. It is only 1.5 times slower then DMD version, so I think it is good
enough. Next steps will be to add support to other common BMP formats and structure this code a bit better.