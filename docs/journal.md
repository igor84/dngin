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

### 8. Supporting common bmp format
Unfortunately most applications seem to still save bitmaps in 24bit per pixel format so I decided to add
support for loading that format as well. I also refactored the code a bit to make it cleaner and so I can
write unittest for color channel manipulations and made SIMD work under LDC. It turned out I needed to add
align(16) to the definition of maskArray.

Thinking a bit about error handling I realized that code mostly only cares if function succeeds or fails
and only the programmer cares about exact reason of failure so functions should log exact errors and just
return failed status in most of the cases. Thus next step should be to enable logging and I should first
try to do it through std.experimental.logger.

### 9. Experimental logger and some memory profiling
While I was reading on std.experimenta.logger I came upon profile-gc build option that writes a log of all
GC allocations your program makes. I tried it and it turned out that great majority of allocations are
done by DerelictGL3 in glloader.registerExtensionLoader function. I then tried to use DerelictGL3_Contexts
and those allocations were gone. But I needed a better reason to use this and have to write "context."
before every gl call. I read a bit about using multiple GL contexts which this feature should make easy
and it turned out it is useful when you want to compile shaders and load textures to GPU memory from
another thread and not block your application which does sound useful. So I decided to keep it.

As for the logger by default it uses appender!string and so GC allocations, but it does give you a
possibility to override a few methods and manage memory yourself. Because of current differences in Phobos
versions between DMD and LDC this is now complicated to implement so I decided to use it like this for now.

### 10. Rendering the texture
Now that I have image loading I implemented creating and rendering a texture on a quad following the same
tutorial at https://learnopengl.com.

### 11. Preparing for optimized rendering of many quads
The next step I wanted to try is to render a lot of defferent positioned rects. First I started thinking
how can I efficiently call these shaders with proper data. First obvious solution is to generate a separate
VAO (vertex array object) for each rect with its own vertex data and texture coordinate data. That way I
can keep one shader bound but each frame create and bind separate VAO for each rect and maybe a separate
texture too. Better solution is, if I can read all rect images from one textures, to collect all rect points
and generate just one VAO for them all. But generating VAOs each frame feels expensive. So I came to an
idea to place indexes in VAO and then for each rect just bind uniforms with needed data that will be indexed
by data from VAO. In this case VAO just needs to contain 4 uvec2, one for each rect point. Then we can pass
two uniforms:

- vec4 coords where if rect should be drown from (x1, y1) to (x2, y2) should be equal to vec4(x1, y1, x2, y2)
- vec2 texCoord[4] which contains 4 texture coordinates for top-left, top-right, bottom-right and bottom-left
corner in that order

GLSL already provides us with gl_VertexID variable that is equal to the vertex's index which we can use for
indexing texCoord array. I refactored the code to support this in about an hour and then spent another 7h
thinking about ways to debug and determine why it isn't working. I learned a bit about apitrace tool and
I installed NVidia Nsight only to determine my laptop and desktop GPUs don't support shader debugging. After
a lot of point drawing I conlcuded that uvec2 in the shader receives 0 when I pass 0 and received some crazy
huge values when I pass anything else. I tryed switching it everywhere to floats and vec3 and then casting
it to uint in the shader and that finally worked. I still have no idea why uvec3 behaved so wierd. Next time
I want to actually add drawing of multiple rects with this code and then measure just how slower is to
precalcuate points to clip space on CPU or pass needed data and do it on GPU.

### 12. Measuring drawRect performance
So after some tinkering it turned out that drawing up to about 500 rects transforming vertices to clip space
on CPU is actually just a tiny bit faster then on GPU, but above that GPU starts to win. With 1000 rects it
still performs only slightly better. Next improvement to try is to use instancing.

### 13. Generating VAO every frame
After reading about instancing I concluded it is useful when besides vertex specific data you also have data
that should be same across all vertexes of one mesh instance, but different for each instance. I keep
imagining how I will use all these rects for UI drawing so I only need per vertex data. So I made a test
where I collect all draw calls into a vertex and indices buffer and then generate and submit one VAO for
all rects to be drawn. This approach is about 10 times faster on 1000 rects but for some reason it looses
a lot of performance around 3000 rects. Up to it it does all drawing in about 0.6ms and somewhere above
that number it goes to 30ms.