#!/usr/bin/env lua

--[[
 - ltkoptionmenu.lua
 -
 - an example for optionmenus - ltk style.
 -
 -
 - Gunnar Zötl <gz@tset.de>, 2010.
 - Released under MIT/X11 license. See file LICENSE for details.
--]]

require "ltk"

function handle(om, val)
	print("optionMenu '"..om.."' was set to '"..tostring(val).."'")
end

-- optionmenu with a function
om1, m1 = ltk.tk_optionMenu{handle, 'Func Option 1', 'Func Option 2', 'Func Option 3'}
print("optionMenu '"..om1.."' was created, menu widget is '"..m1.."'")

-- optionmenu writing selection to tcl variable
om2, m2 = ltk.tk_optionMenu{'optvar', 'Var Option 1', 'Var Option 2', 'Var Option 3'}
print("optionMenu '"..om2.."' was created, menu widget is '"..m2.."'")

var = ""
function checkvar()
	if ltk.var.optvar ~= var then
		var = ltk.var.optvar
		print("optionMenu '"..om2.."' was set to '"..var.."'")
	end
	ltk.after{100, checkvar}
end
-- every now and then check wether the variable for the 2nd option menu has changed,
-- for reporting purposes
ltk.after{100, checkvar}

ltk.grid{om1, om2}
ltk.mainloop()
