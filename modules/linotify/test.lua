local inotify = require 'inotify'
local posix = require 'posix'

posix.unlink 'frodo'

local handle = inotify.init()
local wd = handle:addwatch(posix.getcwd(),inotify.IN_CREATE)

if  posix.fork() == 0 then
    posix.nanosleep(0,20*1e6)
    os.execute 'cp README frodo'
    posix._exit(0)
end

local events = handle:read()
print(events[1].name)
assert(events[1].name == "frodo")
handle:close()
