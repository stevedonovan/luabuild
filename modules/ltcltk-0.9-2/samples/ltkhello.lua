#!/usr/bin/env lua

--[[
 - ltkhello.lua
 -
 - a somewhat involved Hello World example.
 -
 -
 - Gunnar Zötl <gz@tset.de>, 2010.
 - Released under MIT/X11 license. See file LICENSE for details.
--]]

require("ltk")

-- multipurpose destroy event handler, just displays some info.
function destroy(hash, t, T, W, X)
	print(string.format("destroy called, #='%s', t='%s', T='%s', W='%s', X='%s'", hash, t, T, W, X))
	print("Widget " .. W)
end

-- create a button with a simple action that just terminates the program.
-- attach a destroy handler to it just for the sake of doing it
--
function finished()
	ltk.exit()
end
b = ltk.button { }
-- the following could also have been an option for the creation of the button
ltk.wcmd(b){'configure', text='OK'}
ltk.wcmd(b){'configure', command=finished}
ltk.bind{b, '<Destroy>', {destroy, '%#', '%t', '%T', '%W', '%X'}}

-- create a text widget with a click handler, that inserts additional stuff.
-- also attach a destroy handler to it, again just for the sake of doing it
--
t = ltk.text {width=40, height=20}
function click(b, x, y)
	-- get insert position
	local pos = ltk.wcmd(t){'index', 'end'}
	-- get char position
	local cpos = ltk.wcmd(t){'index', '@'..x..','..y}
	ltk.wcmd(t){'insert', pos, string.format("click <%s> at %s\n", b, cpos)}
end
ltk.bind{t, '<Destroy>', {destroy, '%#', '%t', '%T', '%W', '%X'}}
ltk.bind{t, '<ButtonPress>', {click, '%b', '%x', '%y'}}
-- add some initial text
ltk.wcmd(t){'insert', '0.0', "Hello Lua!\n"}

-- now for the layout, one under the other
ltk.grid{'configure', t, row=1}
ltk.grid{'configure', b, row=2}

-- attach a <Destroy> handler to the main window
ltk.bind{'.', '<Destroy>', {destroy, '%#', '%t', '%T', '%W', '%X'}}

-- and go.
ltk.mainloop()

