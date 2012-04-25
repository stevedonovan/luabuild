--- srlua
-- Driver script for luabuild and srlua
local usage = [[
srlua: [options] scriptname
    -o outputname (an .exe will be appended for Windows)
    --modules,-m modlist
        Explicit list of modules; otherwise we read soar.out
]]

local loadstring, append = loadstring or load, table.insert
local join = path.join

local manifest = 'soar.out'

--- let's see if we can find the Luabuild directory
local lb_dir = os.getenv 'LUABUILD_DIR'
if not lb_dir then
    -- assume that soar is a script in the LB/bin directory
    local soar = utils.which('soar'..choose(WINDOWS,'.bat',''))
    if soar then
        local soar_path, check = path.splitpath(soar)
        lb_dir,check = soar_path:gsub('[/\\]bin$','')
        if check ~= 1 then
            quit("buggered "..soar_path)
        end
    else
        quit "soar is not on luabuild path, and LUABUILD_DIR variable has not been set"
    end
end

local function lb_path(f)
    return join(lb_dir,f)
end

local function lb_binpath(f)
    return lb_path(join('bin',f))..EXE_EXT
end

local function execute(cmd)
    print(cmd)
    return utils.execute(cmd)
end

local scriptname, outfile, binmods
local i = 1
while i <= #arg do
    local a = arg[i]
    if a == '-o' then
        i = i + 1
        outfile = arg[i]
    elseif a == '-m' or a == '--modules' then
        i = i + 1
        binmods = utils.split(arg[i])
    else
        scriptname = a
    end
    i = i + 1
end

if not scriptname then quit(usage) end
if not outfile then
    local _,file = path.splitpath(scriptname)
    outfile = path.splitext(file)
end
if WINDOWS and path.extension_of(outfile) == '' then
    outfile = outfile..EXE_EXT
end

if not binmods then
    local modstr, err = file.read(manifest)
    if not modstr then quit ("srlua "..err) end
    local mods = loadstring('return '..modstr)()

    -- find our binary modules!
    binmods = {}
    for mod,path in pairs(mods) do
        if path == 1010 then
            append(binmods,mod)
        end
    end
end
table.sort(binmods)

-- this defines the canonical name for srlua executables
-- if there were no bin modules, then we'll just use the static executable
local were_mods = #binmods > 0
local canon = 'lua-'..table.concat(were_mods and binmods or {'static'},'-')

local uses_linenoise = list.index(binmods,'linenoise')

local fullpath = lb_binpath(join('srluab',canon))
if not path.exists(fullpath) then
    -- this srlua exe has not been built yet
    -- so we ask luabuild to make it
    local config = lb_path(canon..'.config')
    local f = io.open(config,'w')
    if uses_linenoise then
        f:write 'readline = "linenoise"\n'
    end
    if were_mods then
        f:write('include = "',table.concat(binmods,' '),'"\n')
    end
    f:write('srlua = "',canon,'"\n')
    f:close()
    local cmd = 'lua '..lb_path'lake'..' -d '..lb_dir..' CONFIG='..canon..'.config'
    if not execute(cmd) then quit '----we had a problem----' end
end

--- can now glue the srlua exe to the script
execute(lb_binpath'glue'..' '..fullpath..' '..scriptname..' '..outfile)





