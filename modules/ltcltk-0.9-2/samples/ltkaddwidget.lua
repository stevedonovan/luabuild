#!/usr/bin/env lua

--[[
 - ltkaddwidget.lua
 -
 - an example for ltk.addwidget.
 -
 - Gunnar Zötl <gz@tset.de>, 2010.
 - Released under MIT/X11 license. See file LICENSE for details.
--]]

require "ltk"

-- these widget types already exist, this is just to demonstrate how
-- ltk.addtkwidget() works
ltk.addtkwidget('button', {'command'})

ltk.addtkwidget('text', {'xscrollcommand', 'yscrollcommand'}, {
	['create'] = {'create'},
	['window'] = {'create'},
	['bind'] = {3}
})

function pressme()
	local txt = ltk.wcmd(mytxt) {'get', '0.0', ltk.wcmd(mytxt){'index', 'end'}}
	io.write(txt)
	ltk.exit()
end

mytxt = ltk.x_text {}
mybtn = ltk.x_button {text="Press me!", command=pressme}

ltk.pack {mybtn, side="bottom"}
ltk.pack {mytxt, side="top"}

ltk.mainloop()
