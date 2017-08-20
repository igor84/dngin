# DNgin Journal

## 1. Where to start

Starting decisions:

	- Use D Language (there are enough C++ engines)
	- Everything must be well documented from day one and I need to come up with nice way to organize documentation
	- I want the engine to be made of modules that can have different implementation but same API
	- I should be able to build the modules as DLL or to statically link them at any time
	- Every change must be tested with both DMD and LDC in debug and in release mode so I can detect problematic stuff as soon as I add it
	- After each change check the executable size so I can determine what affects it the most
	- Initial plan is basic windows platform layer, then android, maybe iOS and maybe Linux
	- I am targeting minimal external dependencies and if I need some library available in C or C++ I should consider rewriting it in D

First day I setup a Visual Studio project and dub build and I make basic window app that just opens a window and shuts down on window close.

Next step is to initialize OpenGL and display a triangle.

## 2. OpenGL Initialization
After basic OpenGL initialization I needed to find OpenGL bindings for D in order to call OpenGL functions. I first looked if I can use DerelictGLES since I want to support mobile platforms but it seems DerelictGLES only supports Windows and Mac. Will have to check this on the forum. According to [this site](https://www.saschawillems.de/?page_id=1822) using GLES on windows is also not straightforward so I just decided to use DerelictGL3 for now.

I added it to dub dependencies and run `dub upgrade` but to my disappointment it didn't download the packages in the project directory but somewhere under Windows Users dir. This meant I can't easily use them from Visual Studio so I decided to also add them as git submodules, create and setup VS projects for them and mark them as dependant projects. After testing all configurations I found that 32 bit builds under LDC and only Release 32 bit build under DMD crash when calling `DerelictGL3.reload()`. After a bit of debugging I found that it actually happens afer ret instruction from glloader's `bindGLFunc`. Will also have to ask about this on the forum.

At least on 64bit builds I now have a beautiful window filled with hideous purple :).