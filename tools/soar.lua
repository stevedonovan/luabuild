local function usage(msg)
    if msg then
    print("soar: "..msg)
    end
    print[[
soar: Analyze required packages and generate a standalone archive
      of pure Lua scripts

Usage: soar [opts] scriptname [args]

options:
    --static, -s
        Use static analysis on scriptname to find module dependencies.
        Uses luac for source analysis, only finds literal require"mod".
        Otherise,  run scriptname using [args] and exit to print module
        dependencies found dynamically during run.
    --analyze, -a
        only do analysis and write dependencies to solua.out
        Otherwise, generate a standalone archive after analysis
    --pack, -p
        only pack an archive using existing dependency file
    -o filename
        Write output to this file. Otherwise write to standard output
    --exclude, -x  (dir or modules)
        Do not include the named modules in output.  Multiple modules
        can be put in quotes and separated by spaces. Alternatively,
        can specify a directory (ending in /) from which any Lua modules
        will be ignored.
    --debian, -d  
        Do not include Debian installed modules. Equivalent to -x /usr/share/lua/
    -I package
        Include everything in the specified Lua package
]]
os.exit(1)
end

local ml=require "ml"
local loadstring = loadstring or load
local set, update, append = ml.invert, ml.import, table.insert

local function tdump(t,f)
    f = f or io.stdout
    f:write(ml.tstring(t),'\n')
end

local function assertq (condn,msg)
    if not condn then
    io.stderr:write(msg or 'assertion failed')
    os.exit(1)
    end
    return condn
end

local function warn(s)
    io.stderr:write("*-* "..s.."\n")
end

local LUA_DIRSEP = package.config:sub(1,1)

local tinsert = table.insert

-- soar: generate a standalone archive of pure lua scripts from a manifest
--
-- Reads from solua.out, writes to standard out. Depends on the input modules
-- being well-formed Lua code, which should be the case with soluadep output.

-- Arguably, this should create another loader at the end instead of
-- preload; perhaps the user has more up-to-date versions of modules
-- available.

function soar (lua, infile, manifest, outfile)
    local readfile = ml.throw(ml.readfile,true)
    local solua_out = "return "..readfile(manifest)
    local asources = loadstring(solua_out)()
    assertq(asources._main, "No main chunk listed")
    local main = asources._main
    asources._main = nil

    local out
    local original_outfile = outfile
    if outfile then
        if LUA_DIRSEP == "\\" and not outfile:match("%.lua$") then
            outfile = outfile .. "-all.lua"
        end
        out = assert(io.open(outfile,"w"))
    else
        out = io.stdout
    end

    local binary_modules = {}
    local excluded_modules = {}
    local sources = {}
    for mod,path in pairs(asources) do
        if path == true then
            tinsert(excluded_modules, mod)
        elseif path == 1010 then
            tinsert(binary_modules, mod)
        else
            sources[mod] = path
        end    
    end
    
    if not next(sources) then
        print '----- no packing necessary ----'
        return
    end
    
    table.sort(binary_modules)
    table.sort(excluded_modules)

    local _main = readfile(main)
    local _, tailindex, shebang = string.find(_main, "^(#!.-)\r?\n")
    if shebang then
        _main = string.sub(_main, tailindex)
    else
        shebang = "#!/usr/bin/env "..lua
    end

    out:write(shebang, "\n")

    local function banner(mods, b)
        if #mods > 0 then
            out:write("--# ", b, ": ")
            for _,m in ipairs(mods) do
                out:write(m, " ")
            end
            out:write("\n")
        end
    end
    banner(excluded_modules, "Modules not included")
    banner(binary_modules, "Required binary modules")

    -- that funny looking line is both a magic cookie and a way of confusing
    -- lua-mode.el.
    -- The ARG business is to prevent old Lua 5.0 behaviour from
    -- upsetting everyone else

    out:write[==[
    local ARG = arg
    local function _(...)STANDALONE_LUA[=[]]end]=]--archive, contains modules at end
    local arg = ARG
    ]==]

    out:write(_main)
    out:write([[----------------- main script ends here; referenced libraries follow
    --------------------------------------------------------------------
    end
    function STANDALONE_LUA() end
    ]])

    for mod,filename in pairs(sources) do
    if type(filename) == 'string' then -- i.e. not explicitly excluded
        out:write("\n----------------- begin ", mod)
        if not hide_filenames then
            out:write(" (from ", filename, ")")
        end
        local modstr = readfile(filename)
        -- some modules (like markdown) actually have a shebang..
        local i1,i2 = modstr:find '^#!/(.-)\n'
        if i1 == 1 then
        modstr = modstr:sub(i2+1)
        end
        out:write("\nlocal function __(...)\nlocal arg = ARG\n", modstr)
        out:write(ml.expand([[

end
package.preload["${mod}"] = __
----------------- end ${mod}
]], {mod=mod}))
    end
    end

     out:write[[

    -- Invoking the main body; the script from the top of the program runs here.
    _(...)
    ]]

    if outfile then
        out:close()
        if LUA_DIRSEP == "/" then print 'making executable'
            os.execute("chmod +x "..outfile)
        else
            local batfile = original_outfile:gsub('%.lua$','')..".bat"
            -- little hack to get us the Windows current working directory!
            local here = io.popen("echo %CD%"):read()
            local f = io.open(batfile,"w")
            f:write(('@echo off\n"%s" "%s\\%s" %s\n'):format(lua,here,outfile,'%*'))
            f:close()
            print("batch file written to: "..batfile)
        end
        print("output written to: "..outfile)
    end

end

-- We need to exclude what's already present. Unfortunately LUA_INIT
-- and this module itself use modules, so this is not quite the right thing:
--
-- local standalone_package_loaded = update({},package.loaded)
--

--
-- Instead, just list things we do know about as of 2012.
local standalone_package_loaded = set{"string", "debug", "package", "_G",
                 "io", "os", "table", "math", "coroutine"}
                 
-- modules added subsequently by Lua 5.2 and 5.3...
if _G.bit32 then
    standalone_package_loaded.bit32 = true
end
if _G.utf8 then
    standalone_package_loaded.utf8 = true
end

package.standalone_package_loaded = standalone_package_loaded

-- If you're targeting another lua executable, add bit32 or whatever.

-- If you know you're using, say, LuaSocket and there's no chance supplying
-- it with an architecture-independent archive, arrange to place it here:

-- for Luabuild purposes, the more the merrier - we'll need to check whether
-- these external needs can be satisfied later.
package.binonly_module = {}


local explictly_excluded_modules = {}
local explictly_listed_modules = {}
local manifest, explictly_excluded_path, explicit_includes

local function warn_binonly(mod)
    --warn("Unable to find module |"..mod.."|; should it be in --binary or SOLUA_BINONLY?")
    package.binonly_module[mod] = '1010'
end

-- I'll use compat-5.1's search because it works better than mine. By the way,
-- is there some way of getting at the default path lua 5.2's ";;" component
-- specifies?

-- BEGIN compat-5.1
-- Copyright Kepler Project 2004-2006 (http://www.keplerproject.org/compat)
-- According to Lua 5.1
-- $Id: compat-5.1.lua,v 1.22 2006/02/20 21:12:47 carregal Exp $


local function findfile (name, path, find)
    find = find or ml.exists
    name = name:gsub ("%.", LUA_DIRSEP)
    for c in path:gmatch ("[^;]+") do
        c = c:gsub ("%?", name)
        local res = find(c)
        if res then return res end
    end
    return nil -- not found
end

-- END compat-5.1


local modulepaths = {}

-- ml.expand has a bug: if foo contains "$bar" then "${foo}" will be
-- double-substituted.

-- The static analysis is totally a rerun from lualint. Back once
-- again with the ill behavior.

local function popen_luac(sourcepath)
    assertq(sourcepath,"no sourcepath available")
    assertq(ml.exists(sourcepath), "no file "..sourcepath)
    local badchar = sourcepath:match("[^%w :_/.-]+")
    if badchar then
    assertq(true,
        ml.expand(
        'popen does not have any defined cross-platform quoting '..
            'semantics; unknown character "$badchar" found '..
            'in "$sourcepath".',
        {badchar=badchar, sourcepath=sourcepath}))
    end

    return assertq(io.popen('luac -p -l "'..sourcepath..'"'))
end

local function find_requires(sourcepath)
    -- This function is super-cautious because "luac -l" is not at all
    -- a documented interface, and blowing up on unexpected conditions
    -- is better than blithely plowing on.

    local f = popen_luac(sourcepath)

    assertq(f:read() == "", "my luac returns a blank first line")
    assertq(f:read():match("^main <"), "unanticipated first line")
    assertq(f:read():match("^0%+ params,"), "main chunk takes parameters??")

    -- A typical line:
    -- 	11	[9]	GETTABLE 	4 2 -7	; "assert_arg"

    -- Match the mandatory part of each listing line up to the semicolon;
    -- capture line, opcode, and any semicolon clause.
    -- If this fails to match, we don't understand anything about the listing.
    local pat = "^%s+[0-9]+%s+%[([0-9]+)]%s+([A-Z]+)%s+[-0-9%s]+(.*)"

    local requires = {}
    local state = "none"
    local candidate_module
    local lua52 = not _VERSION:match '5%.1$'

    for line in f:lines() do
    if line:match("^%s*$") then
        -- Blank line marks end of the chunk. Stop looking.
        break
    end
    -- we're looking for a sequence of "GETGLOBAL require", a LOADK
    -- of the module name, and a CALL. Anybody who did local require=require
    -- has outsmarted us (and probably themselves too).
    -- Lua 5.2+ has a new opcode here, since it's an upvalue of _ENV
    local linenumber,opcode,tail = line:match(pat)
    assertq(linenumber, "unknown assembly format")
    if state == "none" then
        if lua52 then
            if opcode == "GETTABUP" and tail:match('"require"$') then
                state = "found-require"
            end
        else
            if opcode == "GETGLOBAL" and tail:match("^; require") then
                state = "found-require"
            end
        end
    elseif state == "found-require" then
        -- 9	[8]	LOADK    	4 -6	; "pl.lexer"
        module_name = tail:match('^; "(.*)"%s*$')
        if opcode == "LOADK" and module_name then
            candidate_module = module_name
            state = "found-loadk"
        else
            state = "none"
        end
    elseif state == "found-loadk" then
        if opcode == "CALL" then
            requires[#requires+1] = candidate_module
        end
        state = "none"
    else asserteq(true,"bug in state machine") end
    end
    return requires
end

local function is_explicitly_excluded(mod)
    if explictly_excluded_modules[mod] then return true end
    if not explictly_excluded_path then return false end
    local path = findfile(mod, package.path)
    if not path then return false end
    local i1,i2 = path:find(explictly_excluded_path)
    if i1 == 1 and i2 == #explictly_excluded_path then
        explictly_excluded_modules[mod] = true
        return true
    end
    return false
end

local function is_unloadable_module(mod)
    return package.binonly_module[mod] or package.standalone_package_loaded[mod] or is_explicitly_excluded(mod)
end

local function trace_static_dependencies_of_main(filename)
    local static_dependencies={}

    local trace_static_dependencies
    function trace_static_dependencies(rootmod, filename)
        static_dependencies[rootmod] = filename
        local found_requires = find_requires(filename)
        for _,mod in ipairs(found_requires) do
            -- Skip if we've already registered it.
            if not static_dependencies[mod] and not is_unloadable_module(mod) then
                local sub_filename = findfile(mod, package.path)
                if sub_filename then
                    trace_static_dependencies(mod, sub_filename)
                else
                    warn_binonly(mod)
                end
            end
        end
    end
    trace_static_dependencies("_main", filename)
    return static_dependencies
end


-- And something to call at the end, if you like dynamic analysis:
local function find_dynamic_dependencies()
    local depends = {}
    for mod,_ in pairs(package.loaded) do
        if not is_unloadable_module(mod) then
            local filename = findfile(mod, package.path)
            if filename then
                depends[mod] = filename
            else
                -- Well, we can't find where we loaded this module. This will
                -- be true for anything on cpath.
                warn_binonly(mod)
            end
        end
    end
    return depends
end

-- sadly another approach, to deal with our own ml dependency
local real_require = require
package.explicit_require = {}
function require(mod)
    package.explicit_require[mod] = true
    return real_require(mod)
end

local function dump_deps(deps)
    update(deps, explictly_excluded_modules)
    update(deps, explictly_listed_modules)
    for k,_ in pairs(package.binonly_module) do
        deps[k] = 1010 -- binary, get it?
    end
    local bindeps, excluded = {},{}
    for k,v in pairs(deps) do
        if type(v) == 'string' then
            print(k,v)
        elseif v == 1010 then
            append(bindeps,k)
        else
            append(excluded,k)
        end
    end
    if #excluded > 0 then
        print '---- excluded dependencies --'
        for _,dep in ipairs(excluded) do print(dep,true) end
    end
    if #bindeps > 0 then
        print '---- binary dependencies ---'
        for _,dep in ipairs(bindeps) do print(dep,'*BINARY*') end
    end
    local f = assertq(io.open(manifest, "w"))
    tdump(deps, f)
    f:close()
end

-- In case we replace during script runs.
local real_os_exit=os.exit

local function SOLUA_END(n)
    -- let's not force ml down everyone's throat if they didn't ask for it
    if not package.explicit_require["ml"] then
        package.loaded.ml = nil
    end
    print('soar ---------- analysis over -------------')
    dump_deps(find_dynamic_dependencies())
--    real_os_exit(n) *SJD* we aim to keep going...
end

function files(pat)
    local tmpfile = '/tmp/soar'
    local cmd = 'ls -1 '..pat..' > '..tmpfile..' 2> /dev/null'
    --print(cmd)
    if os.execute(cmd) ~= 0 then return nil end
    local res = {}
    for line in io.lines(tmpfile) do
        append(res,line)
    end
    return res
end

if arg then
    --print(ml.tstring(findfile('macro.*',package.path, files)))
    --os.exit()
    

    if #arg < 1 then
        usage()
    end

    local deps, scriptname, outfile
    local only_analyze, only_pack = false, false
    local static = false

    local i = 0
    while i < #arg do
        i = i + 1
        local a = arg[i]
        if a == "--exclude" or a == "-x" then
            i = i + 1
            if not arg[i] then usage("--exclude needs an argument") end
            a = arg[i]
            if a:match '^%S+/$' then
                explictly_excluded_path = a
            else
                update(explictly_excluded_modules, set(ml.split(a)))
            end
        elseif a == "--debian" or a == "-d" then
            explictly_excluded_path = "/usr/share/lua/"
        elseif a == "--static" or a == "-s" then
            static = true
        elseif a == "--analyze" or a == "-a" then
            only_analyze = true
        elseif a == "--pack" or a == "-p" then
            only_pack = true
        elseif a == "-o" then
            i = i + 1
            outfile = arg[i]
        elseif a == '-I' then
            i = i + 1
            if not arg[i] then usage("-I expects a package name") end
            local P = arg[i]..'.*'
            local explicit_includes = findfile(P,package.path,files)
            if explicit_includes == nil then usage("-I not given valid Lua package") end	    
            for _,file in ipairs(explicit_includes) do
                local _,f = ml.splitpath(file)
                local mod = arg[i]..'.'..ml.splitext(f)
                explictly_listed_modules[mod] = file
            end
        else
            if scriptname then break end
            scriptname = a
            break
        end
    end
    if not outfile  then
        _,outfile = ml.splitpath(scriptname)
        outfile = ml.splitext(scriptname)
        if outfile == scriptname and not only_analyze then
            usage("cannot deduce output name; same as scriptname; use -o")
        end
    end
    if not scriptname then usage("no scriptname provided") end
    local lua = arg[-1]
    arg = ml.sub(arg, i+1)
    arg[0] = scriptname
    arg[-1] = lua
    manifest = "soar.out"
    if static then
        deps = trace_static_dependencies_of_main(scriptname)
        dump_deps(deps)
    elseif not only_pack then
        explictly_listed_modules._main = scriptname
        os.exit = SOLUA_END
        print('soar ---------- running '..scriptname..' --------------')
        dofile(scriptname)
        -- Oh, I'll do it for you.
        os.exit(0)
    end

    if not only_analyze then
        soar(lua, scriptname, manifest, outfile)
    end
end
