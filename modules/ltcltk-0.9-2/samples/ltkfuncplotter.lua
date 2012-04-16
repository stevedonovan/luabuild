#!/usr/bin/env lua

--[[
 - ltkfuncplotter.lua
 -
 - simple function plotter, sample for ltk
 -
 - This is not intended to be a first class function plotter app, just
 - to provide a starter on how to use ltk.
 -
 - Gunnar Zötl <gz@tset.de>, 2010.
 - Released under MIT/X11 license. See file LICENSE for details.
--]]

require "ltk"

-- application window title
apptitle = "ltk Function Plotter"

-- filetypes we use
myfiletype = {{{'LtkFuncplotter'}, {'.func'}}}
psfiletype = {{{'PostScript'}, {'.ps'}}}

-- widgets. for the canvas widget, we create a widget command function in order
-- to make it more easily usable.
w_canvas = ltk.canvas {background='white'}
canvas = ltk.wcmd(w_canvas)
-- this is the menu bar
w_bar = ltk.menu {['type']='menubar'}
-- other ui widgets
w_lxmin = ltk.label {text="Minimum x"}
w_xmin = ltk.entry {background='white'}
w_lxmax = ltk.label {text="Maximum x"}
w_xmax = ltk.entry {background='white'}
w_lymin = ltk.label {text="Minimum y"}
w_ymin = ltk.entry {background='white'}
w_lymax = ltk.label {text="Maximum y"}
w_ymax = ltk.entry {background='white'}
w_lfunc = ltk.label {text="Function(x)"}
w_func = ltk.entry {background='white', text='x'}
w_plot = ltk.button {text="Plot"}

-- the environment in which functions will be evaluated.
local fenv = {}
for name, func in pairs(math) do fenv[name] = func end

-- evaluate the function passed as a string for one value
function evaluate(func, x)
	local f = loadstring("return "..func)
	fenv['x'] = x
	setfenv(f, fenv)
	local ok, val = pcall(f)
	if ok then return val else return ok, val end
end

-- check wether the passed arguments are sensible for the function plotter
function validate_data(xmin, xmax, ymin, ymax, func)
	local msg = ""
	if xmin==nil then
		msg = msg .. 'Minimum X must be a number\n'
	end
	if xmax==nil then
		msg = msg .. 'Maximum X must be a number\n'
	end
	if ymin==nil then
		msg = msg .. 'Minimum Y must be a number\n'
	end
	if ymax==nil then
		msg = msg .. 'Maximum Y must be a number\n'
	end
	if xmin and xmax and xmin >= xmax then
		msg = msg .. 'Minimum X must be less than maximum X\n'
	end
	if ymin and ymax and ymin >= ymax then
		msg = msg .. 'Minimum Y must be less than maximum Y\n'
	end
	if func == nil then
		msg = msg .. 'You must specify a function\n'
	else
		local val, m = evaluate(func, xmin)
		if not val then
			msg = msg .. 'The function returned an error:\n  '..m
		end
	end

	if msg ~= "" then
		ltk.tk_messageBox{title='Error', message=msg, ['type']='ok'}
	end

	return msg == ""
end

-- draw coordinate system and also compute scale factors and origin
function drawcoords(xmin, xmax, ymin, ymax)
	local cw = ltk.winfo{'width', w_canvas}
	local ch = ltk.winfo{'height', w_canvas}
	local pw = cw - 30
	local ph = ch - 30

	local xfac = pw / (xmax-xmin)
	local yfac = ph / (ymax - ymin)
	local fac = (xfac < yfac) and xfac or yfac

	local w = fac * (xmax - xmin)
	local h = fac * (ymax - ymin)
	local x0 = (cw - w) / 2
	local y0 = (ch - h) / 2

	-- draw graph decorations and annotations
	canvas{'create', 'rectangle', x0, y0+h, x0+w, y0 }
	canvas{'create', 'text', x0-2, y0, text=ymax, anchor='ne'}
	canvas{'create', 'text', x0-2, y0+h, text=ymin, anchor='se'}
	canvas{'create', 'text', x0, y0+h+2, text=xmin, anchor='nw'}
	canvas{'create', 'text', x0+w, y0+h+2, text=xmax, anchor='ne'}

	if xmin<0 and xmax>0 then
		local x_0 = -xmin * fac + x0
		canvas{'create', 'line', x_0, y0, x_0, y0+h, fill='#ff0000'}
	end

	if ymin<0 and ymax>0 then
		local y_0 = -ymin * fac + y0
		canvas{'create', 'line', x0, y_0, x0+w, y_0, fill='#ff0000'}
	end

	-- return origin and scales.
	return x0, w, y0+h, -h
end

-- plot the function. Values are read from the widgets by means of their widget
-- command 'get'.
function plot()
	local xmin = tonumber(ltk.wcmd(w_xmin){'get'})
	local xmax = tonumber(ltk.wcmd(w_xmax){'get'})
	local ymin = tonumber(ltk.wcmd(w_ymin){'get'})
	local ymax = tonumber(ltk.wcmd(w_ymax){'get'})
	local func = ltk.wcmd(w_func){'get'}

	if not validate_data(xmin, xmax, ymin, ymax, func) then return end

	-- clear canvas
	canvas {'delete', 'all'}
	-- add name of function we plot
	canvas {'create', 'text', 1, 1, text="Function: "..func, anchor='nw'}

	-- and draw the function
	local x0, w, y0, h = drawcoords(xmin, xmax, ymin, ymax)
	local fx = (xmax - xmin) / w
	local fy = h / (ymax- ymin)
	local py = (evaluate(func, xmin) - ymin) * fy + y0
	local x,y
	for x = x0+1, x0+w do
		y = (evaluate(func, (x-x0)*fx+xmin) - ymin) * fy + y0
		canvas{'create', 'line', x-1, py, x, y, fill='#0000ff'}
		py = y
	end
end

-- helper function, as setting values for entry widgets is a bit involved.
function setval(widget, val)
	local v = ltk.wcmd(widget){'get'}
	local lv = #v or 0
	ltk.wcmd(widget){'delete', 0, lv}
	ltk.wcmd(widget){'insert', 0, tostring(val) }
end

-- load a function plot definition from a file
function open()
	local file = ltk.tk_getOpenFile{filetypes=myfiletype}
	-- an empty string is returned if the openfile dialog is aborted
	if file == "" then return end
	local f, err = loadfile(file)
	if f == nil then error(err) end
	local name, val
	local args = f()
	for name, val in pairs(args) do
		widget = _G["w_"..name]
		setval(widget, val)
	end

	-- set window title with file name
	ltk.wm{'title', '.', apptitle .. ': ' .. file}
end

-- save current function plot definition to a file.
function save()
	local file = ltk.tk_getSaveFile{filetypes=myfiletype}
	-- an empty string is returned if the savefile dialog is aborted
	if file == "" then return end
	local f = io.open(file, 'w')
	local name, widget, idx, val
	f:write("return {")
	for idx, name in pairs {'xmin', 'xmax', 'ymin', 'ymax', 'func'} do
		if idx > 1 then f:write(",\n") else f:write("\n") end
		widget = _G["w_"..name]
		val = ltk.wcmd(widget){'get'}
		f:write(string.format('["%s"]="%s"', name, tostring(val)));
	end
	f:write("\n}\n")
	f:close()

	-- set window title with file name
	ltk.wm{'title', '.', apptitle .. ': ' .. file}
end

-- save the current graph as postscript file. The canvas widget directly
-- supports this.
function savegraph()
	local gfile = ltk.tk_getSaveFile{filetypes=psfiletype}
	-- an empty string is returned if the openfile dialog is aborted
	if gfile == "" then return end
	canvas{'postscript', file=gfile}
end

-- create the application menu and submenu
function buildmenu()
	-- submenu "File"
	local w_file = ltk.menu {title='File'}
	local file = ltk.wcmd(w_file)
	file {'add', 'command', label='Open...', command=open }
	file {'add', 'command', label='Save...', command=save }
	file {'add', 'command', label='Save Graph', command=savegraph }
	file {'add', 'separator'}
	file {'add', 'command', label='Quit', command=ltk.exit}

	-- now add submenu to main menu
	local menu = ltk.wcmd(w_bar)
	menu {'add', 'cascade', menu=w_file, label='File' }

	return w_bar
end

-- build the application window. We use a grid layout, and sticky the widgets
-- in order to make them behave sensibly when the window resizes.
function buildwin()
	w_bar = buildmenu()
	ltk.wcmd('.'){'configure', menu=w_bar}
	ltk.wcmd(w_plot){'configure', command=plot}

	ltk.wcmd(w_xmin){'insert', 0, 0}
	ltk.wcmd(w_xmax){'insert', 0, 1}
	ltk.wcmd(w_ymin){'insert', 0, 0}
	ltk.wcmd(w_ymax){'insert', 0, 1}
	ltk.wcmd(w_func){'insert', 0, 'x'}

	-- we sticky the entry widgets at their left and right sides, so that they
	-- will only grow wider, not higher.
	ltk.grid{w_lxmin, column=0, row=0}
	ltk.grid{w_xmin, column=1, row=0, sticky='we'}
	ltk.grid{w_lxmax, column=0, row=1}
	ltk.grid{w_xmax, column=1, row=1, sticky='we'}
	ltk.grid{w_lymin, column=2, row=0}
	ltk.grid{w_ymin, column=3, row=0, sticky='we'}
	ltk.grid{w_lymax, column=2, row=1}
	ltk.grid{w_ymax, column=3, row=1, sticky='we'}
	ltk.grid{w_lfunc, column=4, row=0}
	ltk.grid{w_func, column=5, row=0, columnspan=2, sticky='we'}
	ltk.grid{w_plot, column=6, row=1, sticky='we'}

	-- the canvas widget should fill the entire space, so we sticky it on all
	-- 4 sides.
	ltk.grid{w_canvas, row=2, columnspan=7, sticky='nwse'}

	-- now tell the layout manager how to resize the widgets. Labels should not
	-- be resized, entry and canvas widgets should.
	ltk.grid{'columnconfigure', '.', 1, weight=1}
	ltk.grid{'columnconfigure', '.', 3, weight=1}
	ltk.grid{'columnconfigure', '.', 5, weight=1}
	ltk.grid{'columnconfigure', '.', 6, weight=1}
	ltk.grid{'rowconfigure', '.', 2, weight=1}
end

-- now create the application window
ltk.tk{'appname', apptitle}
buildwin()

ltk.bind{'all', '<Return>', plot}

-- and run the app. This never returns.
ltk.mainloop()
