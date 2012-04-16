local lua = arg[-1]
io.stderr:write '----LuaSocket test: should take about a minute\n'
if package.config:match '^/' then -- i.e. Unix...
    os.execute (lua..' testsrvr.lua &')
else
    os.execute('start '..lua..' testsrvr.lua')
end
os.execute (lua..' testclnt.lua')

