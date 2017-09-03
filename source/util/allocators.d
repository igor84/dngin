module util.allocators;

import std.experimental.allocator.building_blocks.null_allocator;
import std.experimental.allocator.common;
import std.typecons : Flag, Yes, No;
import core.atomic : cas, atomicOp;

@safe @nogc nothrow pure
bool isGoodStaticAlignment(uint x)
{
    import std.math : isPowerOf2;
    return x.isPowerOf2;
}

/**
Returns `n` rounded up to a multiple of alignment, which must be a power of 2.
*/
@safe @nogc nothrow pure
size_t roundUpToAlignment(size_t n, uint alignment)
{
    import std.math : isPowerOf2;
    assert(alignment.isPowerOf2);
    immutable uint slack = cast(uint) n & (alignment - 1);
    const result = slack ? n + alignment - slack : n;
    assert(result >= n);
    return result;
}

/**
Advances the beginning of `b` to start at alignment `a`. The resulting buffer
may therefore be shorter. Returns the adjusted buffer, or null if obtaining a
non-empty buffer is impossible.
*/
@nogc nothrow pure
void[] roundUpToAlignment(void[] b, uint a)
{
    auto e = b.ptr + b.length;
    auto p = cast(void*) roundUpToAlignment(cast(size_t) b.ptr, a);
    if (e <= p) return null;
    return p[0 .. e - p];
}

/**
Returns `n` rounded down to a multiple of alignment, which must be a power of 2.
*/
@safe @nogc nothrow pure
size_t roundDownToAlignment(size_t n, uint alignment)
{
    import std.math : isPowerOf2;
    assert(alignment.isPowerOf2);
    return n & ~size_t(alignment - 1);
}

/**
Returns `true` if `ptr` is aligned at `alignment`.
*/
@nogc nothrow pure
bool alignedAt(T)(T* ptr, uint alignment)
{
    return cast(size_t) ptr % alignment == 0;
}

/**
Aligns a pointer up to a specified alignment. The resulting pointer is greater
than or equal to the given pointer.
*/
@nogc nothrow pure
void* alignUpTo(void* ptr, uint alignment)
{
    import std.math : isPowerOf2;
    assert(alignment.isPowerOf2);
    immutable uint slack = cast(size_t) ptr & (alignment - 1U);
    return slack ? ptr + alignment - slack : ptr;
}

shared(void)* alignUpTo(shared(void)* ptr, uint alignment)
{
    import std.math : isPowerOf2;
    assert(alignment.isPowerOf2);
    immutable uint slack = cast(size_t) ptr & (alignment - 1U);
    return slack ? ptr + alignment - slack : ptr;
}

/**
A $(D Region) allocator allocates memory straight from one contiguous chunk.
There is no deallocation, and once the region is full, allocation requests
return $(D null). Therefore, $(D Region)s are often used (a) in conjunction with
more sophisticated allocators; or (b) for batch-style very fast allocations
that deallocate everything at once.

The region only stores three pointers, corresponding to the current position in
the store and the limits. One allocation entails rounding up the allocation
size for alignment purposes, bumping the current pointer, and comparing it
against the limit.

If $(D ParentAllocator) is different from $(D NullAllocator), $(D Region)
deallocates the chunk of memory during destruction.

The $(D minAlign) parameter establishes alignment. If $(D minAlign > 1), the
sizes of all allocation requests are rounded up to a multiple of $(D minAlign).
Applications aiming at maximum speed may want to choose $(D minAlign = 1) and
control alignment externally.

IMPORTANT: This is shared implementation that can be used as processAllocator.
This should be sacked once Phobos implements this.

*/
struct SharedRegion(ParentAllocator = NullAllocator,
    uint minAlign = platformAlignment,
    Flag!"growDownwards" growDownwards = No.growDownwards)
{
    static assert(minAlign.isGoodStaticAlignment);
    static assert(ParentAllocator.alignment >= minAlign);

    import std.traits : hasMember;
    import std.typecons : Ternary;

    // state
    /**
    The _parent allocator. Depending on whether $(D ParentAllocator) holds state
    or not, this is a member variable or an alias for
    `ParentAllocator.instance`.
    */
    static if (stateSize!ParentAllocator)
    {
        ParentAllocator parent;
    }
    else
    {
        alias parent = ParentAllocator.instance;
    }
    private void* _current, _begin, _end;

    /**
    Constructs a region backed by a user-provided store. Assumes $(D store) is
    aligned at $(D minAlign). Also assumes the memory was allocated with $(D
    ParentAllocator) (if different from $(D NullAllocator)).

    Params:
    store = User-provided store backing up the region. $(D store) must be
    aligned at $(D minAlign) (enforced with $(D assert)). If $(D
    ParentAllocator) is different from $(D NullAllocator), memory is assumed to
    have been allocated with $(D ParentAllocator).
    n = Bytes to allocate using $(D ParentAllocator). This constructor is only
    defined If $(D ParentAllocator) is different from $(D NullAllocator). If
    $(D parent.allocate(n)) returns $(D null), the region will be initialized
    as empty (correctly initialized but unable to allocate).
    */
    this(ubyte[] store) shared
    {
        auto mem = cast(shared(ubyte)[])(store.roundUpToAlignment(alignment));
        mem = mem[0 .. $.roundDownToAlignment(alignment)];
        assert(mem.ptr.alignedAt(minAlign));
        assert(mem.length % minAlign == 0);
        _begin = mem.ptr;
        _end = mem.ptr + mem.length;
        static if (growDownwards)
            _current = _end;
        else
            _current = mem.ptr;
    }

    /// Ditto
    static if (!is(ParentAllocator == NullAllocator) && !hasMember!(ParentAllocator, "deallocate"))
    {
        this(size_t n) shared
        {
            this(cast(shared(ubyte)[])parent.allocate(n.roundUpToAlignment(alignment)));
        }
    }

    /**
    If `ParentAllocator` is not `NullAllocator` and defines `deallocate`, the region defines a destructor that uses `ParentAllocator.delete` to free the
    memory chunk, but only if this Region wasn't copied to another and now memory has another reference to it.
    */
    static if (!is(ParentAllocator == NullAllocator)
        && hasMember!(ParentAllocator, "deallocate"))
    {
        void[] memoryToFree;

        this(size_t n) shared
        {
            memoryToFree = cast(shared(void)[])parent.allocate(n.roundUpToAlignment(alignment));
            // We need space for short in order to do reference counting to this memory
            auto refCount = cast(shared(short)*)memoryToFree.ptr;
            *refCount = 0;
            this(cast(ubyte[])memoryToFree[short.sizeof .. $]);
        }

        this(this) shared
        {
            auto refCount = cast(shared(short)*)memoryToFree.ptr;
            if (atomicOp!"+="(*refCount, 1) <= 0) {
                _current = null;
                _begin = null;
                _end = null;
                refCount = null;
            }
        }

        ~this() shared
        {
            auto refCount = cast(shared(short)*)memoryToFree.ptr;
            if (refCount && atomicOp!"-="(*refCount, 1) < 0) parent.deallocate(cast(void[])memoryToFree);
        }

        ref typeof(this) opAssign(ref typeof(this) rhs) //Doesn't compile if shared???
        {
            auto refCount = cast(shared(short)*)memoryToFree.ptr;
            if (refCount && atomicOp!"-="(*refCount, 1) < 0) parent.deallocate(cast(void[])memoryToFree);
            this = rhs;
            return this;
        }
    }


    /**
    Alignment offered.
    */
    alias alignment = minAlign;

    /**
    Allocates $(D n) bytes of memory. The shortest path involves an alignment
    adjustment (if $(D alignment > 1)), an increment, and a comparison.

    Params:
    n = number of bytes to allocate

    Returns:
    A properly-aligned buffer of size $(D n) or $(D null) if request could not
    be satisfied.
    */
    void[] allocate(size_t n) shared
    {
        static if (growDownwards)
        {
            static if (minAlign > 1)
                const rounded = n.roundUpToAlignment(alignment);
            else
                alias rounded = n;
            if (available < rounded) return null;
            typeof(_current) curCurrent;
            do {
                curCurrent = _current;
                auto result = (_current - rounded)[0 .. n];
                assert(result.ptr >= _begin);
            } while (!cas(&_current, curCurrent, result.ptr));
            assert(owns(result) == Ternary.yes);
            return result;
        }
        else
        {
            static if (minAlign > 1)
                const rounded = n.roundUpToAlignment(alignment);
            else
                alias rounded = n;
            typeof(_current) curCurrent;
            typeof(_current) newCurrent;
            void[] result;
            do {
                curCurrent = _current;
                newCurrent = curCurrent + rounded;
                if (newCurrent > _end) return null;
                result = cast(void[])_current[0 .. n];
            } while (!cas(&_current, curCurrent, newCurrent));
            return result;
        }
    }

    /**
    Allocates $(D n) bytes of memory aligned at alignment $(D a).

    Params:
    n = number of bytes to allocate
    a = alignment for the allocated block

    Returns:
    Either a suitable block of $(D n) bytes aligned at $(D a), or $(D null).
    */
    void[] alignedAllocate(size_t n, uint a) shared
    {
        import std.math : isPowerOf2;
        assert(a.isPowerOf2 && a > minAlign);
        static if (growDownwards)
        {
            void[] result;
            typeof(_current) curCurrent;
            typeof(_current) newCurrent;
            do {
                curCurrent = _current;
                newCurrent = (curCurrent - n).alignDownTo(a);
                if (newCurrent < _begin) return null;
                result = newCurrent[0 .. n];
            } while (!cas(&_current, curCurrent, newCurrent));
            return result;
        }
        else
        {
            static if (minAlign > 1)
                const rounded = n.roundUpToAlignment(alignment);
            else
                alias rounded = n;
            typeof(_current) curCurrent;
            typeof(_current) newCurrent;
            void[] result;
            do {
                curCurrent = _current;
                auto start = curCurrent.alignUpTo(a);
                newCurrent = start + rounded;
                if (newCurrent > _end) return null;
                result = cast(void[])start[0 .. n];
            } while (!cas(&_current, curCurrent, newCurrent));
            return result;
        }
    }

    /// Allocates and returns all memory available to this region.
    void[] allocateAll() shared
    {
        void[] result;
        static if (growDownwards)
        {
            typeof(_current) curCurrent;
            do {
                curCurrent = _current;
                result = _begin[0 .. available];
            } while (!cas(&_current, curCurrent, _begin));
        }
        else
        {
            typeof(_current) curCurrent;
            do {
                curCurrent = _current;
                result = cast(void[])curCurrent[0 .. available];
            } while (!cas(&_current, curCurrent, _end));
        }
        return result;
    }

    /**
    Deallocates all memory allocated by this region, which can be subsequently
    reused for new allocations.
    */
    bool deallocateAll() shared
    {
        static if (growDownwards)
        {
            _current = _end;
        }
        else
        {
            _current = _begin;
        }
        return true;
    }

    /**
    Queries whether $(D b) has been allocated with this region.

    Params:
    b = Arbitrary block of memory ($(D null) is allowed; $(D owns(null))
    returns $(D false)).

    Returns:
    $(D true) if $(D b) has been allocated with this region, $(D false)
    otherwise.
    */
    Ternary owns(void[] b) const shared
    {
        return Ternary(b.ptr >= _begin && b.ptr + b.length <= _end);
    }

    /**
    Returns `Ternary.yes` if no memory has been allocated in this region,
    `Ternary.no` otherwise. (Never returns `Ternary.unknown`.)
    */
    Ternary empty() const shared
    {
        return Ternary(_current == _begin);
    }

    /// Nonstandard property that returns bytes available for allocation.
    size_t available() const shared
    {
        static if (growDownwards)
        {
            return _current - _begin;
        }
        else
        {
            return _end - _current;
        }
    }
}
