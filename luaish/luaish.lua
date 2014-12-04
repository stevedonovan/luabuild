local have_ml,ml = pcall(require, 'ml')
local posix = require 'posix'
local linenoise = require 'linenoise'
local lsh = { tostring = tostring }
local append = table.insert

io.write "luaish (c) Steve Donovan 2012-2014\n"

local our_completions, our_history = {}
local  our_shortcuts = {}

local home = os.getenv 'HOME'

local push, pop = append, table.remove

local function at(s,i)
    return s:sub(i,i)
end

local function safe_dofile(fname,complain)
    local f = io.open(fname,'r')
    if f then
        f:close()
        dofile(fname)
        return true
    elseif complain then
        print("no file '"..name.."' found")
    end
    return false
end

------- autocompletion ------------------
local function append_candidates(res,t,prefix,name)
    if not res then res = {} end
    local all = name == ''
    for k,v in pairs(t) do if type(k) == 'string' then
        if all or k:sub(1,#name) == name then
            append(res,prefix..k)
        end
   end end
   return res
end

local function expand_dollar(line,i1)
    local name = line:match '%$(%S+)$'
    if not name then return end
    if not it then
        i1 = line:find '%S+$'
    end    
    local prefix = line:sub(1,i1-1)
    if name:match '^%d+$' then -- a file index
        local f = lsh.file_by_index(name)
        if not f then return end
        return {prefix..f} 
    elseif name == '_' then -- last command
        return {prefix..(_G['__'] or '')}
    else -- environment variable?
    	prefix = line:sub(1,i1)
        return append_candidates(nil,posix.getenv(),prefix,name)
    end
end

local function is_pair_iterable(t)
    local mt = getmetatable(t)
    return type(t) == 'table' or (mt and mt.__pairs)
end

local function lua_candidates(line)
    -- might be expanding $n
    local res = expand_dollar(line)
    if res then return res end

    -- identify the expression - identifier with maybe field or method access
    local i1,i2 = line:find('[.:%w_]+$')
    if not i1 then return end
    local front,partial = line:sub(1,i1-1), line:sub(i1)
    if i1 > 1 and at(line,i1-1) == "'" then
	    local res = {}	    
	    for _,f in ipairs(posix.dir(path)) do 
	        if f:sub(1,#partial)==partial then
	            push(res,front..f)
	        end
	    end
	    return res
    end
    local prefix, last = partial:match '(.-)([^.:]*)$'
    local t = _G
    if #prefix > 0 then        
        local P = prefix:sub(1,-2)
        for w in P:gmatch '[^.:]+' do
            t = t[w]
            if not t then return end
        end
    end
    prefix = front .. prefix
    res = {}
    local mt = getmetatable(t)
    if is_pair_iterable(t) then
        append_candidates(res,t,prefix,last)
    end
    if mt and is_pair_iterable(mt.__index) then
        append_candidates(res,mt.__index,prefix,last)
    end
    -- smallest matches first
    table.sort(res,function(a,b)
        return #a < #b
    end)    
    return res
end

local function command_history_candidates(line)
    local esc = at(line,1)
    line = line:sub(1)
    local cmd = ("grep '^%s' %s/.luai-history"):format(_G.SHELL_ESC,home)
    local f = io.popen(cmd,'r')
    local matches = {}
    for line in f:lines() do
        append(matches,line)
    end
    f:close()
    local cc = {}
    for i = #matches,1,-1 do
        if matches[i]:sub(1,#line) == line then
            append(cc,matches[i])
        end
    end
    return cc
end

local function is_directory(path)
    return posix.stat(path,'type') == 'directory'
end

----- auto-completion used in shell mode ---
local function path_candidates(line)
    local i1,front,path,name
    i1 = line:find '%S+$'
    if at(line,i1) == '$' then
        return expand_dollar(line,i1)
    elseif not i1 then
        return
    end
    if line:match '^.[%w_]+$' then
        return command_history_candidates(line)    
    end
    front, path = line:sub(1,i1-1), line:sub(i1)
    i1 = path:find '[.%w_%-]*$'
    if not i1 then return end
    path,name = path:sub(1,i1-1), path:sub(i1)
    local fullpath, sc, dpath = path,at(path,1),path
    if sc == '~' then
        path = home..'/'..path:sub(3)
        fullpath = path 
    elseif sc ~= '/' then
        fullpath = posix.getcwd()
        if path ~= '' then
            fullpath = fullpath ..'/'..path
        else
            path = '.'
            dpath = ''
        end
    end
    if not is_directory(fullpath) then return end
    local res = {}
    local all = name == ''
    for _,f in ipairs(posix.dir(path)) do 
        if not (f=='.' or f=='..') and (all or f:sub(1,#name)==name) then
            push(res,front..dpath..f)
        end
    end
    -- smallest matches first
    table.sort(res,function(a,b)
        return #a < #b
    end)
    return res
end

local auto_shell_mode

local function shell_mode(s)
    return at(s,1) == _G.SHELL_ESC or auto_shell_mode
end

function lsh.get_prompt(firstline)
    if not auto_shell_mode then return nil
    else
        return '$> '
    end
end

local function completion_handler(c,s)
    local cc
    if shell_mode(s) then -- shell path completion
        cc = path_candidates(s)
        if not cc then return end
    else -- otherwise Lua...
        -- shortcuts like fn -> function, rt -> return
        for sc,value in pairs(our_shortcuts) do
            local idx = #s - #sc + 1
            if s:sub(idx)==sc then
                cc = {s:sub(1,idx-1)..value}
                break
            end
        end
        --- Lua variable completion
        if not cc then
            cc = lua_candidates(s)
        end
    end
    if cc then
        for _,name in ipairs(cc) do
            linenoise.addcompletion(c,name)
        end
    end
end

function lsh.set_tostring(ts)
    local old_tostring = lsh.tostring
    lsh.tostring = ts
    return old_tostring
end

function lsh.set_shortcut(name,exp)
    our_shortcuts[name] = exp
end

function lsh.add_completion(pat,cf)
    our_completions[pat] = cf
end

local file_list = {}

function lsh.add_to_file_list(file)
    if type(file) == 'table' and #file > 0 then
        for i = 1,#file do
            lsh.add_to_file_list(file[i])
        end
    else
        append(file_list,file)
        print(('%2d %s'):format(#file_list,file))
    end
end

function lsh.reset_file_list()
    file_list = {}
end

function lsh.file_by_index(idx)
    idx = tonumber(idx)    
    if idx > 0 and idx <= #file_list then
        return file_list[idx]
    end
end

function lsh.saveline (s)
    linenoise.historyadd(s)
    linenoise.historysave(our_history)
end

function lsh.readline(prmt)
   local line, err = linenoise.linenoise(prmt)
   if not line then	
        if err == 'cancel' then
            print '<control-c>'
            line = linenoise.linenoise(prmt)
        else
            return nil
        end
    end
    if #file_list > 0 and line then
        line = line:gsub('%$(%d+)',function(num)
            return lsh.file_by_index(num) or 'que?'
        end)
        lsh.lines = file_list
    end 
   return line
end

local shell_command_handler

function lsh.checkline(b)
    if shell_mode(b) then
        local err, res = pcall(shell_command_handler,b)
        if not err then
            print('luaish error',res)
            os.exit(1)
        end
        if res then
            lsh.saveline(b)
            return false -- we handled this, keep reading
        end
    end
   return true -- line for Lua interpreter
end

-------- Lua output filters --------
-- a shell command like '.ls | sort |-name'
-- will be put through a Lua function called 'name' in the luaish global table.
-- This function is passed the file object from popen

-- this filter prints lines with line numbers, and the lines can
-- subsequently be accessed with $n from the prompt (all modes)
function lsh.lf (f)
    lsh.reset_file_list()
    for line in f:lines() do
        lsh.add_to_file_list(line)
    end
end

-- this filter is used to implement the built-in command export
function lsh.lsetenv (f)
    local line = f:read()
    local var, value = line:match '^(%S+) "(.-)"$'
    posix.setenv(var,value)
end

-- copy output of command into a Lua table, e.g. 'head file |-> lines'
lsh ['>'] = function(f,name)
    local res = {}
    for line in f:lines() do
        append(res,line)
    end
    _G[name] = res
end

-- dump a table in the Lua global 'name' and pipe to a command
lsh.print = function(f,name)
    local val = _G[name]
    if not val then
        io.write(("'%s' is not a Lua global\n"):format(name))
        return
    end
    for _,line in ipairs(_G[name]) do
        f:write(line,'\n')
    end
end

--- managing directory stack----
local dirstack = {}

local function set_title(msg)
    msg = msg or posix.getcwd()
    io.write("\027]2;luaish "..msg.."\007")
    print(msg)
end

local function change_directory(dir)    
    dir = dir:gsub('^~',home)
    posix.chdir(dir)
    set_title(posix.getcwd())
end

local function back()
    local odir = pop(dirstack)
    if odir then
        change_directory(odir)
    else
        print 'dir stack is empty'
    end
end

local function dirs_remove_dups()
    local ls, dups = {},{}
    local user = home..'/'
    for i = 1,#dirstack do
        local d = dirstack[i]
        d = d:gsub(user,'~/')
        if not dups[d] then
            append(ls,d)
            dups[d] = true
        end
    end
    return ls
end

local function dirs()
    lsh.reset_file_list()
    lsh.add_to_file_list(dirs_remove_dups())
end

local function dir_at_index(idx)
    if idx > 0 and idx <= #dirstack then
        return dirstack[idx]
    end
end

local last_command

local function exec (line)
    local i1,_,filter,at_start
    i1,_,lfilter = line:find '|%s*%-(.+)$'
    if not i1 then
        at_start = true
        _,i1,lfilter = line:find '%s*%-([^|]+)|'
    end
    if i1 then
        if at_start then
            line = line:sub(i1+1)
        else
            line = line:sub(1,i1-1)
        end
        local lfun,arg = lfilter:match '(%S+)%s+(.-)%s*$'
        if not lfun then
            lfun = lfilter 
        end
        if not lsh[lfun] then
            io.write (lfun,' is not a Lua filter\n')
            return true
        end
        local f = io.popen(line,at_start and 'w' or 'r')
        local ok, res = pcall(lsh[lfun],f,arg)
        f:close()
        if not ok then
            io.write(res,'\n')
        end
        return true
    else
        os.execute(line)
    end
    return true
end

local alias

function lsh.add_alias(name,cmd)
    alias[name] = cmd
end

function lsh.show_aliases()
    for k,v in pairs(alias) do
        print(k,v)
    end
end

local function expand_lua_globals(line)    
    return line:gsub('%$([%w_]+)',function(name)
        if name == '_' then name = '__' end
        local val = _G[name]
        if val then return tostring(val)
        else return '$'..name
        end
    end)
end

function shell_command_handler (line)
    if not auto_shell_mode then
        line = line:sub(2)
    end
    line = line:gsub ('^%s*','')
    if line == "" then
        auto_shell_mode = true
        return true
    elseif line == 'exit' then
        if auto_shell_mode then
            auto_shell_mode = false
        end
        return true
    end
    line = expand_lua_globals(line)
    local cmd,args = line:match '^(%S+)%s*(.*)$'
    if not args then
        io.write 'bad command syntax\n'
        return true
    end
    _G.__ = line
    if alias[cmd] then
        line = alias[cmd]:format(args)
        cmd,args = line:match '^(%S+)(.*)$'
    end    
    args = args:gsub('^%s*','')
    if cmd:match '^%d+$' then
    	arg = dir_at_index(tonumber(cmd))
    	if not arg then print 'no such index'; return true end
    	push(dirstack,posix.getcwd())
    	change_directory(arg)
    elseif cmd == 'cd' then
        if args == '' then
            dirs()
            return true
        end
        local arg = args:match '^(%S+)'
        local idx = arg:match '^$(%d+)$'
        if idx then
            arg = dir_at_index(tonumber(idx))
            if not arg then
                print 'no such index in dir stack'
                return true
            end
        else
            local _,k = arg:find '^%-+$'
            if k then
                arg = arg:gsub('%-','../',k)
            end
            arg = arg:gsub('^~',os.getenv 'HOME')
            if not is_directory(arg) then
                arg = posix.dirname(arg)
            end                
        end
        push(dirstack,posix.getcwd())
        change_directory(arg)      
    elseif cmd == 'l' then
        if args == '' then
            args = last_command
        end        
        if not args then
            print 'no script file specified'
            return true
        end
        safe_dofile(args,true)
        last_command = args
    elseif cmd == 'back' then
        back()
    elseif cmd == 'hist' then
        return exec(("tail %s | grep '^%s' |-lf"):format(our_history,SHELL_ESC))
    elseif cmd == 'export' then
        local var = args:match '^(.-)='
        local cmd = (('%s && echo %s \\"$%s\\" |-lsetenv'):format(args,var,var))
        return exec(cmd)
    elseif cmd == 'set' then
        if args:match '^%s*$' then
            lsh.show_aliases()
            return true
        end        
        local name,exp = args:match '(%S+)%s+(.+)'
        if not name then
            print("syntax is 'set name command'")
        else
            lsh.add_alias(name,exp)
        end
    else -- plain shell command
    	if DBG then
        	print(line)
        end
        return exec(line)
    end
    return true
end

linenoise.setcompletion(completion_handler)
our_history = home..'/.luai-history'
linenoise.historyload(our_history)	

-- microlight isn't essential, but it gives you better
-- output; tables will be printed out
if have_ml then
    lsh.set_tostring(ml.tstring)
    _G.ml = ml
end
local ok
ok,_G.config = pcall(require,'config')

lsh.set_shortcut ('fn', "function ")
lsh.set_shortcut('rt','return')

_G.SHELL_ESC='!'
_G.posix = posix
_G.luaish = lsh -- global for rc file

local data

if not safe_dofile(home..'/.luairc.lua') then
    print("customize with ~/.luairc.lua")
end
local pfile = home..'/.luai-data'
local chunk = loadfile(pfile)
if chunk then
    data = chunk()
end
if data then
    dirstack = data.dirs
    alias = data.alias
else
    data = {}
end
if not alias then
    alias = {}
    lsh.add_alias('dir','ls -1 %s |-lf')
    lsh.add_alias('locate','locate %s |-lf')
    data.alias = alias
end

function lsh.close()
    local f = io.open(pfile,'w')
    data.dirs = dirs_remove_dups()
    f:write('return '..lsh.tostring(data),'\n')
    f:close()
end

return lsh
