#!/usr/bin/env lua

--[[
 - ltkimage.lua
 -
 - an example for some ltk image stuff and idle callbacks
 -
 - Gunnar Zötl <gz@tset.de>, 2010.
 - Released under MIT/X11 license. See file LICENSE for details.
--]]

require "ltk"

img = ltk.image{'create', 'photo', width=256, height=256}
imgcmd = ltk.wcmd(img)

function drawimg()
	local drawfn
	drawfn = coroutine.wrap(function()
		local x, y, z, col
		z = 0
		while true do
			for x=0, 255 do
				for y=0, 255 do
					col = string.format("#%02X%02X%02X", x, y, z)
					imgcmd{'put', col, to = ltk.vals(x, y)}
					if y%63 == 0 then
						ltk.after{'idle', drawfn}
						coroutine.yield()
					end
				end
			end
			z = (z + 51) % 256
		end
	end)
	ltk.after{'idle', drawfn}
end

c=ltk.canvas { width=256, height=256 }
ccmd = ltk.wcmd(c)
ccmd{'create', 'image', 0, 0, image=img, anchor='nw'}

b = ltk.button {text="Close", command=function() ltk.exit() end}

ltk.grid{c, row=1}
ltk.grid{b, row=2}
-- show window and all
ltk.update()

-- initial image
drawimg()

-- and run
ltk.mainloop()

