local have_ml,ml = pcall(require, 'ml')
local posix = require 'posix'
local linenoise = require 'linenoise'
local lsh = { tostring = tostring }
local append = table.insert

io.write "luaish (c) Steve Donovan 2012\n"

local our_completions, our_history = {}
local  our_line_handlers, our_shortcuts = {} ,{}

local function is_pair_iterable(t)
    local mt = getmetatable(t)
    return type(t) == 'table' or (mt and mt.__pairs)
end

local function lua_candidates(line)
  -- identify the expression!
  local i1,i2 = line:find('[.:%w_]+$')
  if not i1 then return end
  local front,partial = line:sub(1,i1-1), line:sub(i1)
  local prefix, last = partial:match '(.-)([^.:]*)$'
  local t, all = _G
  if #prefix > 0 then        
    local P = prefix:sub(1,-2)
    all = last == ''
    for w in P:gmatch '[^.:]+' do
      t = t[w]
      if not t then return end
    end
  end
  prefix = front .. prefix
  local res = {}
  local function append_candidates(t)  
    for k,v in pairs(t) do
      if all or k:sub(1,#last) == last then
        append(res,prefix..k)
      end
    end
  end
  local mt = getmetatable(t)
  if is_pair_iterable(t) then
    append_candidates(t)
  end
  if mt and is_pair_iterable(mt.__index) then
    append_candidates(mt.__index)
  end
  return res
end

local function completion_handler(c,s)
  local cc
  for pat, cf in pairs(our_completions) do
      if s:match(pat) then
        cc = cf(s)
        if not cc then return end
      end
  end
  for sc,value in pairs(our_shortcuts) do
    local idx = #s - #sc + 1
    if s:sub(idx)==sc then
      cc = {s:sub(1,idx-1)..value}
      break
    end
  end
  if not cc then
    cc = lua_candidates(s)
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

function lsh.set_shortcuts(shortcuts)
  our_shortcuts = shortcuts
end

function lsh.add_line_handler (h)
  append(our_line_handlers, h)
end

function lsh.add_completion(pat,cf)
  our_completions[pat] = cf
end  

local file_list = {}

function lsh.add_to_file_list(file)
    append(file_list,file)
    print(('%2d %s'):format(#file_list,file))
end

function lsh.reset_file_list()
    file_list = {}
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
	    num = tonumber(num)
	    return file_list[num] or 'que?'
	end)
	lsh.lines = file_list
    end   
   return line
end

function lsh.checkline(b)
    for _,h in ipairs(our_line_handlers) do    
      local res = h(b)
      if res then
        lsh.saveline(b)
        return false -- we handled this, keep reading
     end
   end
   return true -- line for Lua interpreter
end

-------- Lua output filters --------
-- a shell command like '.ls | sort |=name'
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

lsh ['>'] = function(f,name)
    local res = {}
    for line in f:lines() do
	append(res,line)
    end
    _G[name] = res
end

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

local function at(s,i)
    return s:sub(i,i)
end

local push, pop = append, table.remove
local dirstack = {}

local function is_directory(path)
    return posix.stat(path,'type') == 'directory'
end

function path_candidates(line)
    local i1,front,path,name
    i1 = line:find '%S+$'
    if not i1 then return end
    front, path = line:sub(1,i1-1), line:sub(i1)
    i1 = path:find '[.%w%-]*$'
    if not i1 then return end
    path,name = path:sub(1,i1-1), path:sub(i1)
    local fullpath, sc, dpath = path,at(path,1),path
    if sc == '~' then
        path = os.getenv 'HOME'..'/'..path:sub(3)
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
        if all or f:sub(1,#name)==name then
            push(res,front..dpath..f)
        end
    end
    table.sort(res,function(a,b)
        return #a < #b
    end)
    return res
end

local function set_title(msg)
    msg = msg or posix.getcwd()
    io.write("\027]2;luai "..msg.."\007")
end

local function change_directory(dir)    
    posix.chdir(dir)
    set_title(posix.getcwd())
    print(dir)
end

local function back()
    local odir = pop(dirstack)
    if odir then
        change_directory(odir)
    else
        print 'dir stack is empty'
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

local alias = {}

function lsh.add_alias(name,cmd)
    alias[name] = cmd
end

local function expand_alias(cmd,args)
    return alias[cmd]:format(args)
end

local function expand_lua_globals(line)
    return line:gsub('%$(%a+)',function(name)
	local val = _G[name]
	if val then return tostring(val)
	else return '$'..name
	end
    end)
end

function shell_command_handler (line)
    if at(line,1) == '.' then        
        line = line:gsub('^%.%s*','')
	line = expand_lua_globals(line)
        local cmd,args = line:match '^(%S+)(.*)$'
	if not args then
	    io.write 'bad command syntax\n'
	    return true
	end
	if alias[cmd] then
	    line = expand_alias(cmd,args)
	    cmd,args = line:match '^(%a+)(.*)$'
	end
        args = args:gsub('^%s*','')
        if cmd == 'cd' then
            local arg = args:match '^(%S+)'
            local _,k = arg:find '^%-+$'
            if k then
                arg = arg:gsub('%-','../',k)
            end
            arg = arg:gsub('^~',os.getenv 'HOME')
	    if not is_directory(arg) then
		arg = posix.dirname(arg)
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
            dofile(args)
            last_command = args
        elseif cmd == 'back' then
            back()
	elseif cmd == 'h' then
	    return exec(('tail %s |-lf'):format(our_history))
	elseif cmd == 'export' then
	    local var = args:match '^(.-)='
	    local cmd = (('%s && echo %s \\"$%s\\" |-lsetenv'):format(args,var,var))
	    return exec(cmd)
        else -- plain shell command
	    return exec(line)
        end
        return true
    end
end

local home = os.getenv 'HOME'  	
linenoise.setcompletion(completion_handler)
our_history = home..'/.luai-history'
linenoise.historyload(our_history)	
lsh.add_line_handler(shell_command_handler)
lsh.add_completion('^%.',path_candidates)

-- microlight isn't essential, but it gives you better
-- output; tables will be printed out
if have_ml then
	lsh.set_tostring(ml.tstring)
        _G.ml = ml
end
local ok
ok,_G.config = pcall(require,'config')

lsh.set_shortcuts {
	fn = "function ",
	rt = "return ",
}	

_G.posix = posix
_G.luaish = lsh -- global for rc file

lsh.add_alias('dir','ls -1 %s |-lf')
lsh.add_alias('locate','locate %s |-lf')

local luarc =  home..'/.luairc.lua'
local f = io.open(luarc,'r')
if f then
	f:close()		
	dofile(luarc)
else
	--print 'no ~/.luairc.lua found'
end

return lsh
