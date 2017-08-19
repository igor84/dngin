# DNgin Journal

## 1. Where to start

Starting decisions:

	- Use D Language (there are enough C++ engines)
	- Everything must be well documented from day one and we need to come up with nice way to organize documentation
	- We want the engine to be made of modules that can have different implementation but same API
	- We should be able to build the modules as DLL or to statically link them at any time
	- Every change must be tested with both DMD and LDC in debug and in release mode so we can detect problematic stuff as soon as we add it
	- After each change check the executable size so we can determine what affects it the most
	- Initial plan is basic windows platform layer, then android, maybe iOS and maybe Linux
	- We are targeting minimal external dependencies and if we need some library available in C or C++ we should consider rewriting it in D