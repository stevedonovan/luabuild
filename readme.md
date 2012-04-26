# Luabuild, A Custom Lua 5.2 Builder

## Rationale

Deploying Lua applications as standalone applications can be tricky, as it is in all dynamic languages. The first thing that needs to happen is that all the external Lua dependencies of the application need to be found and a standalone single Lua file generated.  This is what Mathew Wild's [Squish](http://matthewwild.co.uk/projects/squish/home) and Jay Carlson's [Soar](http://lua-users.org/lists/lua-l/2012-02/msg00609.html) do for us. The result can be made executable (by shebang or batch file) and depends on the currently installed Lua distribution. This file can be glued to a stub executable using Luiz Henrique de Figueiredo's [srlua](http://www.tecgraf.puc-rio.br/~lhf/ftp/lua/#srlua) to provide a standalone executable. This is particularly useful on platforms where there is no system package manager that can easily deliver Lua.

However, most non-trivial Lua applications will depend on external binary modules, since the Lua core is deliberately kept compact and conforming to what is provided by the C89 standard. So (for instance) iterating over files and directories requires LuaFileSystem. So we need to statically link these external C modules with Lua to get a stub executable with no external dependencies apart from the C runtime.

This turns out to be particularly straightforward with Lua 5.2; [linit.c](http://www.lua.org/source/5.2/linit.c.html) provides a list of built-in Lua modules to be included, and a separate list of external modules which will be pre-loaded. The core of Luabuild is a flexible way to build Lua 5.2 with a modified `linit.c` that will optionally _exclude_ standard modules and _include_ external modules.

The build system uses [Lake](https://github.com/stevedonovan/Lake) which allows us to write the build logic in a higher-level, platform-independent way. (I've included a very _fresh_ version in this distribution for convenience). `lake` does need Lua and LuaFileSystem, which gives us a classic bootstrapping situation where you do need an existing Lua (5.1 or 5.2) to get things going.  `lake` allows a single build script to cope with both Microsoft and Gnu compilers on Windows, and abstracts away some of the more irritating platform preculiarities (for instance, how to create a shared C extension on OS X, etc)

If you don't have a suitable lua.exe available, then a standalone [lake.exe](http://stevedonovan.github.com/files/lake.exe) is available for Windows.

## Included Modules

Lua C extensions are usually shipped with makefiles, which are designed to build shared libries or DLLs. Makefiles are usually a mess, despite the best intentions of the authors, and have a tendency to be either hard to read or specific to the author's machine. Luabuild contains a number of common/convenient C extensions that are available for static linking:

 * [LuaFileSystem](http://www.keplerproject.org/luafilesystem/) File System Support
 * [lcomplex](http://www.tecgraf.puc-rio.br/~lhf/ftp/lua/#lcomplex) Complex number Support (requires C99)
 * [LPeg](http://www.inf.puc-rio.br/~roberto/lpeg.html)
 * [LuaSocket](http://www.tecgraf.puc-rio.br/luasocket/) Networking
 * [luaposix](https://github.com/rrthomas/luaposix)  POSIX API
 * [winapi](https://github.com/stevedonovan/winapi) Minimal Windows API
 * [ltcltk](http://www.tset.de/ltcltk/) Binding to Tcl/Tk
 * [LuaSQLite3](http://lua.sqlite.org/index.cgi/index)
 * [lua-linenoise](https:/github.com/hoelzro/lua-linenoise)

 These are all all Lua 5.2 compatible, which required some extra (but necessary) work. Some of these (luaposix and winapi) are very platform-dependent; ltcltk could be in principle built on Windows, but Tcl/Tk is an awkward dependency on that platform. I don't claim that these modules represent some kind of ideal extended core, simply that they are (a) widely used and (b) small enough to link in statically.  'Small enough' is a tough requirement when contemplating GUI toolkits in particular, because even the _bindings_ to common cross-platform kits like wxWidgets and Qt get rather large.

The available modules are listed in `modules/manifest` and there may be a corresponding `.lake` file. For instance, `complex.lake`

    if CC == 'cl' then
        quit "MSVC does not do C99 complex"
    end

    luabuild.test 'test.lua'

    return c99.library{LIBDIR..'complex',src='lcomplex',args=ARGS}

They are plain Lua files invoked from the main lakefile, and have the usual `lake` globals available - here we can complain about Microsoft's C99 support. Luabuild defines some globals like `LIBDIR` (which is `$LB/lib/`) and `ARGS` which provides the common default settings, like the include directory and the base directory for finding the sources.

Expressing the build in this higher-level way makes it very flexible; we don't have to worry about the platform details of making a C99 library, whether static or dynamic.

A more complete example is for the `socket.core` module of luasocket:

    ----- building socket/core -----
    COMMON='timeout buffer auxiliar options io'
    COMMON = COMMON..' '..choose(WINDOWS,'wsocket','usocket')
    SCORE=COMMON..' luasocket inet tcp udp except select'

    luabuild.lua('ftp.lua http.lua smtp.lua tp.lua url.lua','socket')
    luabuild.lua('socket.lua mime.lua ltn12.lua')
    luabuild.test 'test-driver.lua'

    defines='LUASOCKET_DEBUG'
    if not luabuild.config.no_lua51_compat then
        defines = defines..' LUA_COMPAT_ALL'
    end

    return c.library {LIBDIR..'socket/core',src=SCORE,needs='sockets',defines=defines,
        args = ARGS
    }

Note how any pure Lua components can be copied as well; these go into the `lua` directory, and will be on the module path for the default `lua52` executable.

The global `luabuild` provides the means to add a test file. It became clear that Luabuild needed to do more than statically link an appropriate executable; without the means to easily test the result. And it was going to be necessary to also provide the traditional shared library versions of these modules and put them in a convenient place.  Since some of these modules have a Lua part as well, these needed to be copied onto the module path as well. In this way, Luabuild has moved from a quick hack to being a small, flexible, source-based Lua 5.2 distribution. This was not my original intention, since there is already [two] big source-based distributions. But their bigness means that it will take a while for them to become Lua 5.2 compatible. It seems that the [Luadist](https://github.com/LuaDist) project understands that provision for static linking provides the means to customize the Lua executable, see [this comment](https://github.com/LuaDist/Repository/issues/80) by David Manura. It's possible because that project uses another high-level build platform, CMake.

## Using luabuild

The default build is controlled by `default.config`:

    ----- Luabuild default configuration
    OPTIMIZE='O2'
    -- or you can get a debug build
    --DEBUG = true

    -- this is the default; build with as much 5.1 compatibility as possible
    no_lua51_compat = false

    if  not STATIC then
        build_shared = true
        --the excutable/lib will find its modules in $LB/libs and $LIB/lua
        custom_lua_path = true
        -- default to linking against linenoise - set READLINE if you really
        -- want the old dog back
        readline = READLINE and true or 'linenoise'
    else
        --it will be a statically-linked executable that can't link dynamically
        no_dlink = true
        -- can switch off readline (useful for self-contained executables)
        readline = false
    end

    -- set this if you want MSVC builds to link against runtime
    -- (they will be smaller but less portable)
    dynamic = DYNAMIC

    if not STATIC then
        name = 'lua52'
    else
        name = 'lua52s'  -- for 'static'
    end

    if PLAT == 'Windows' then
        dll = name
    end

    if PLAT == 'Windows' then
        include = 'lfs winapi socket.core mime.core lpeg struct'
        if CC ~= 'cl' then -- sorry, MSVC does not do C99 complex...
            include = include .. ' complex'
        end
    else
        include = 'lfs socket.core mime.core lpeg complex posix_c struct '
        if not READLINE then
            include = include .. ' linenoise '
        end
        -- either satisfy external requirements, or just leave these out
        include = include .. ' curses_c ltcl lxp lsqlite3'
    end

Again, it's a Lua file, and any global variables (defined as uppercase names) are available.  Setting any uppercase name makes this available as a `lake` global, so you can trivially get a debug build of Lua 5.2 and the modules by using `DEBUG`, or a cross-platform build using `PREFIX`. For instance, to build for ARM Linux, I needed to add just one line:

    PREFIX = 'arm-linux'

And thereafter the compiler, etc would become `arm-linux-gcc` and so forth.

Note `custom_lua_path`: the default build will put shared libraries in `libs/` and Lua files in `lua/` and will modify the Lua module path to look in these directories - this is the only major patch to the 5.2 sources. This is particularly useful on non-Windows platforms where the default module path is only superuser-writable, and you wish to have a 'sandboxed' Lua build.

The default build makes a fairly conventional Lua 5.2 executable (or DLL on Windows) with the external modules as shared libraries. (On POSIX systems there is an option link against `readline`, but you can choose to statically-link in `linenoise` instead.)

    $ lua lake

It may complain about missing development headers, such as `ncurses` and `tcl`; for a clean Debian install I needed the `libncurses-dev`, `libreadline-dev` and `libtcl8.4-dev` (plus `Tk8.4` for the `tk` part; this appears to be available out of the box for OS X machines). Or you can leave out the problematic modules and concentrate on the core modules.

To build everything, including the 'fat' Lua 5.2 executable with the modules linked in statically:

    $ ./build-all

This will also make wrappers for the `soar` and `srlua` tools in the `bin` directory.

The tests can now be run:

    $ ./test-dynamic && ./test-static

This can take a few minutes, particularly LuaSocket. (The LuaFileSystem tests take a lot longer on Windows because directory iteration is much more expensive.)

If you get into trouble, the best solution is to clean things out first (in the usual way) with:

    $ lua lake clean

There was recently a discussion on the Lua mailing list about the pitfalls of mixing GPL projects with MIT. The usual `readline` library is actually _GPL_, so authorities are divided on whether it's appropriate for a MIT-licensed project to even link against it. In any case, as the man page for `readline` says, "It's too big and too slow".  So in luabuild there is support for using [linenoise](https://github.com/antirez/linenoise) which is so dinky that statically linking it into your application only adds a few KB.  This is the default; modify `default.config` (or pass it READLINE=1) if you really want `readline`.

This also creates the `lua-linenoise` binding, so that your interactive apps can also provide simple line editing and history management. (It can also do tab completion: see  `modules/lua-linenoise/example.lua`)

## Gluing Things Together

At this point, it is useful to put Luabuild's `bin` directory on your path. This makes the tools `soar52` and `srlua` available, as well as the Lua executables `lua52` and `lua52s` (the fat executable).

Say I want to package Lake as a standalone executable:

    d:\dev\lua\luabuild> srlua -m lfs lake -o lake

This will build an appropriate static Lua executable (`lua-lfs.exe` in this case) and glue the `lake` script to it, giving `lake.exe`.

(For purposes of building standalone Lua executables, mingw is the best choice, since it generates executables with no funny run-time dependencies. It's possible to build against MSVC, but the runtime is statically linked by default and rather larger; dynamic linking produces a smaller executable that depends on the _particular_ MSVC runtime)

In this case, we knew that `lake` was a single script with a known external dependency on LuaFileSystem.

`soar` will analyze all the dependencies dynamicallly, internal or external, and create an archive script:

    D:\dev\lua\LDoc>soar52 -o ldoc ldoc.lua .
    soar ---------- running ldoc.lua --------------
    reading configuration from config.ld
    output written to d:\dev\lua\ldoc\out
    soar ---------- analysis over -------------
    ldoc.prettify   D:\dev\lua\LDoc\ldoc\prettify.lua
    pl.tablex       C:\Program Files\Lua\5.1\lua\pl\tablex.lua
    ...
    ---- binary dependencies ---
    lfs     *BINARY*
    batch file written to: ldoc.bat
    output written to: ldoc-all.lua

Here ldoc-all.lua is over 10,000 lines of Lua, with only `lfs` as the external dependency. Note that dynamic analysis requires the program to be run by `soar`, and the program must either end naturally or explicitly call the patched `os.exit`. (The `-s` flag makes `soar` analyze statically.)

This can now be made into a standalone executable. In this case `srlua` reads the output file `soar.out` to find what binary modules to be included.

    D:\dev\lua\LDoc> srlua -o ldoc ldoc-all.lua
    d:\dev\lua\luabuild\bin\glue.exe d:\dev\lua\luabuild\bin\srlua\lua-lfs.exe ldoc-all.lua ldoc.exe

The result is over 450K, but it does work.

`ldoc` is not a good candidate, since it's a Lua programmer's tool, and there are better ways to deploy it. But it illustrates the principle; _providing_ that luabuild knows about the modules you need, soar/srlua can make it into an executable. This is probably more useful on platforms without package managers; you can distribute the packed archive (if you can assume that the person has the external modules).

## Lua 5.2

Of course, this package isn't useful unless your source is Lua 5.2-compatible. Most porting problems actually come from old Lua 5.0 deprecated features that have finally expired (like implicit `arg` table in varargs functions). The best approach to porting is to use a compatibility library - for instance, requiring the [pl.utils](https://github.com/stevedonovan/Penlight/blob/2a66849a99a088432272d90846c36447747a5574/lua/pl/utils.lua) module from Penlight (which can be used on its own without the rest of the library), or using David Manura's [lua-compat-env](https://github.com/davidm/lua-compat-env) module.

Adapting luabuild for Lua 5.1.4 would be straightforward, although already this seems like an historical exercise.

## Future Directions

There are of course limitations; it's unreasonable to try capture every possible module that people might need to link statically, and that role will (hopefully) be taken over by LuaDist, which is dedicated to tracking and building all the important Lua modules.  (In particular, your favourite GUI toolkit is unlikely to be ever supported by luabuild.)

However, a side-effect of this project has been the successful porting of a number of key projeccts to Lua 5.2, and I'll continue to port any small modules that seem to be useful for embedding purposes.

Lua is famous for the small size of its core, and so it isn't surprising that most of the size of a packed Lua application is the Lua sources included. As an optimization, it would be good to include a source code shrinker (aka 'minimizer') like [LuaSrcDiet}(http://code.google.com/p/luasrcdiet/) in luabuild. But usually you would want to distribute programs as compressed files anyway (`ldoc.exe` in the above example goes down to 150K using `zip`).

Another motivation for luabuild was to give `lake` a good solid exercise, and it has proved to be a flexible way to organize tricky builds. In particular, being able to partition the building of particular targets into groups makes it straightforward to customize the compilation of individual files.  For example, building the Lua static library was easier because `loadlib.c` could be done as a special case; it turns out that gcc 4.6's default optimization causes trouble with the `longjmp` error mechansion in `ldo.c`, at least on Windows for static builds - it was straightforward to treat this as a separate case that would not use the 'omit frame pointer' optimization.


