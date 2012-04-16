--[[
 - ltk.lua
 -
 - bind tk gui toolkit to lua
 -
 - Gunnar Zötl <gz@tset.de>, 2010.
 - Released under MIT/X11 license. See file LICENSE for details.
--]]

local _G=_G

--module("ltk")
ltk = {}
local _M = ltk
_M._VERSION = 0.8
_M._REVISION = 8

-- references to global functions
local _
local t_insert = _G.table.insert
local t_remove = _G.table.remove
local s_gsub = _G.string.gsub
local s_format = _G.string.format
local setmetatable = _G.setmetatable
local pairs = _G.pairs
local ipairs = _G.ipairs
local type = _G.type
local select = _G.select
local tostring = _G.tostring
local unpack = _G.unpack
local error = _G.error
local pcall = _G.pcall
local ltcl = _G.require "ltcl"

local bind

-- initialize ltk state
--
local tcl_interp = ltcl.new()
ltk.tcl = tcl_interp
ltk._TKVERSION = tcl_interp:eval 'package require "Tk"'
local widgets = {}
local func_cache = {} -- use with care: anything you register here will stay
				-- here unless manually removed.

-- create variable passthru table
local var_mt = {}

var_mt.__index = function(_, idx)
	local ok, val = pcall(ltcl.getvar, tcl_interp, idx)
	return ok and val or nil
end

var_mt.__newindex = function(_, idx, val)
	return tcl_interp:setvar(idx, val)
end

ltk.var = setmetatable({}, var_mt)

-- register default toplevel widget
widgets['.'] = {
	id = '.',
	which = 'Tk',
	registered = {},
	destroyfns = {},
	fixlist = {}
}
-- <Destroy> handler for . is registered at the end of this file.

local all_widgets = {
	registered = {},
	destroyfns = {}
}

-- genid
--
-- utility function to generate unique id within tk state
--
-- Arguments:
--	-
--
local ltk_id_count = 0
local function genid()
	ltk_id_count = ltk_id_count + 1
	return s_format(".__ltkid%08x", ltk_id_count)	
end

-- maketkfunc
--
-- utility function to register lua functions with tk
-- checks wether the argument is
-- - a lua function. if so, registers it with the tcl interpreter
-- - a table, in that case the first element must be a function to be treated
--   like above, or a string, and the rest
--   are arguments, all of this is concatenated to a list
-- In these cases the function returns the generated id (or nil if no id was
-- generated) and the command to pass to a function or widget option, otherwise
-- returns nil
--
-- Arguments:
--	func	function to register with the tk state
--
local function maketkfunc(func)
	local id, cmd
	if type(func) == 'function' then
		id = genid()
		tcl_interp:register(id, func)
		func = id
	elseif type(func) == 'table' then
		if type(func[1]) == 'function' then
			id = genid()
			tcl_interp:register(id, func[1])
			func[1] = id
		end
	else
		id = nil
	end
	return id, func
end

-- fixfunctionargs
--
-- utility function to check all tk widget options that take commands for
-- functions and process them using maketkfunc() above. Returns a list of
-- generated function id's to register with the widget.
--
-- Arguments
--	fargs	list of options taking functions as args
--	opts	option list to process
--
local function fixfunctionargs(fargs, opts)
	local toregister = {}
	local test, cmd, id
	if opts == nil then return toregister end
	for _, test in pairs(fargs) do
		if opts[test] then
			id, cmd = maketkfunc(opts[test])
			t_insert(toregister, id)
			opts[test] = cmd
		end
	end
	return toregister
end

-- makefixfunc
--
-- utility function to create a function to fix option arguments that are
-- functions. Returns a function to be called with the ltk internal widget
-- structure as first and the table with arguments to process as second
-- argument.
--
-- Arguments:
--	...	widget commands to fix options for
--
local function makefixfunc(...)
	local fix
	local farg = select(1, ...)
	if (select('#', ...) == 1 and type(farg) == 'table') then
		fix = farg
	else
		fix = {...}
	end

	return function(widget, args)
		local reg = fixfunctionargs(fix, args)
		local k
		for _, k in pairs(reg) do
			t_insert(widget.registered, k)
		end
	end
end

-- getcachedfuncid
--
-- utility function to retrieve a cached function id, or if it is not cached,
-- generate a new id and cache and return that.
--
-- Arguments:
--	fn	function to get id for
--
local function getcachedfuncid(fn)
	local id
	if func_cache[fn] ~= nil then
		id = func_cache[fn]
	else
		id = genid()
		tcl_interp:register(id, fn)
		func_cache[fn] = id
	end
	return id
end

----- generic widget handling stuff -----

-- destroywidget
--
-- utility function to unregister any functions associated with a widget and
-- invalidate its state.
-- Note: once a widget has been destroyed, you can not use it again!
--
-- Arguments:
--	tk	tk state
--	wid	id of widget that is to be destroyed
--	hash, t, T, W	%#,%t,%T,%W from the Tcl event, see Tcl function "bind" doc
--
local function destroywidget(wid, hash, t, T, W)
	local widget = widgets[wid]
	-- this may happen when destroywidget is called on application shutdown or
	-- if the destroy event trickles up a child-parent widget chain.
	if (not widget) or (wid ~= W) then return end
	-- call registered <Destroy> handlers
	local destroyfns = widget.destroyfns or {}
	for i=1, #destroyfns do
		local fn = destroyfns[i]
		if type(fn) == 'string' then
			tcl_interp:call(fn)
		elseif type(fn) == 'table' then
			local i
			local f = fn[1]
			local args = {}
			for i = 2, #fn do
				local v = fn[i]
				v = s_gsub(v, '%%#', hash or '??')
				v = s_gsub(v, '%%t', t or '??')
				v = s_gsub(v, '%%T', T or '??')
				v = s_gsub(v, '%%W', W or '??')
				v = s_gsub(v, '%%%a', '??')
				args[i-1] = s_gsub(v, '%%%%', '%')
			end
			tcl_interp:callt(f, args)
		end
	end
	for i=1, #widget.registered do
		tcl_interp:unregister(widget.registered[i])
	end
	widgets[wid] = nil
end 

-- widget
--
-- generic widget creation function
-- creates a new widget of the type specified by the name parameter, and
-- registers a <Destroy> event handler for it to do housekeeping when the
-- widget is destroyed. The function returns the called widget id.
--
-- Arguments:
--	name	type of widget to be created
--	opts	table of arguments for object creation
--	optfixlist	table where the keys are the widget commands for which the
--		functions specified as values should fix functions for.
--	passedid you may create a hollow widget, that is, a table that behaves like
--		a widget but is not actually linked to tk, if you specify the pathname
--		yourself.
--
local function widget(name, opts, optfixlist, passedid, parentid)
	opts = opts or {}
	local pathname = passedid
	if parentid == '.' or not parentid then
		parentid = ''
	end

	if pathname == nil then
		pathname = parentid .. genid()
		t_insert(opts, 1, pathname)
		tcl_interp:callt(name, tcl_interp:makearglist(opts))
	else
		pathname = parentid .. pathname
	end

	local widget = {
		id = pathname,
		which = name,
		registered = {},
		destroyfns = {},
		fixlist = optfixlist or {}
	}
	widgets[pathname] = widget

	-- if we create a hollow widget, we don't register a destroy handler for it.
	if passedid == nil then
		bind{pathname, '<Destroy>',
			{ function(...) destroywidget(pathname, ...) end,
				'%#', '%t', '%T', '%W' }}
	end
	
	return pathname, widget
end

-- makewidget
--
-- create and register a tk widget creation function. Takes care of all prepa-
-- rations for later invocations like fixing function args and such
--
-- Arguments:
--	wtype	tk widget type to create function for, will also be the name of the
--			widget creation function within ltk, unless mname is specified.
--	conf	config options to fix function arguments for
--	cmds	widgets commands that may have functions in their argument list,
--			and the table of arguments to them that may be functions.
--	mname	if specified, the new widget creation function will be registered
--			under this name
--
local function makewidget(wtype, conf, cmds, mname)
	local realcmds
	if cmds ~= nil and type(cmds) ~= 'table' then
		error("cmds argument must be a table.")
	elseif cmds then
		local cmd, fix
		realcmds = {}
		for cmd, fix in pairs(cmds) do
			realcmds[cmd] = makefixfunc(fix)
		end
	end
	
	-- if config fix options were given, also fix them for the configure widget
	-- command
	if conf ~= nil and type(conf) ~= 'table' then
		error("conf argument must be a table.")
	else
		if not realcmds then realcmds = {} end
		realcmds['configure'] = makefixfunc(conf)
	end
	
	if not mname then
		mname = wtype
	end
	
	-- may be called as func{opts} or func(parent){opts}
	_M[mname] = function(opts)
		local pfx
		local fn = function(opts)
			local toregister = {}
			if conf then toregister = fixfunctionargs(conf, opts) end
			local wid, widget = widget(wtype, opts, realcmds, nil, pfx)
			widget.which = mname
			local cmd
			for _, cmd in pairs(toregister) do t_insert(widget.registered, cmd) end
			return wid
		end
		if _M.widgettype(opts) then
			pfx = opts
			return fn
		else
			return fn(opts)
		end
	end
end

----- pre-defined widget types -----

-- see tk docs for usage.
-- named parameters do not need the '-' before the name, ltcl.makearglist takes
-- care of that

---- tk 8.4 widgets ----

-- button widget
--
makewidget('button', {'command'})

-- canvas widget
makewidget('canvas', {'xscrollcommand', 'yscrollcommand'}, {
	['bind'] = {4}
})

-- checkbutton widget
makewidget('checkbutton', {'command'})

-- entry widget
makewidget('entry',
	{'xscrollcommand', 'invalidcommand', 'invcmd', 'validatecommand', 'vcmd'})

-- frame widget
makewidget('frame')

-- label widget
makewidget('label')

-- labelframe widget
makewidget('labelframe')

-- listbox widget
makewidget('listbox', {'xscrollcommand', 'yscrollcommand'})

-- menu widget
makewidget('menu', {'postcommand', 'tearoffcommand'}, {
	['add'] = 'command'
})

-- menubutton widget
makewidget('menubutton')

-- message widget
makewidget('message')

-- panedwindow widget
makewidget('panedwindow')

-- radiobutton widget
makewidget('radiobutton', {'command'})

-- scale widget
makewidget('scale', {'command'})

-- scrollbar widget
makewidget('scrollbar', {'command'})

-- spinbox widget
makewidget('spinbox', {'command', 'xscrollcommand', 'invalidcommand', 'invcmd',
		'validatecommand', 'vcmd'})

-- text widget
makewidget('text', {'xscrollcommand', 'yscrollcommand'}, {
	['create'] = {'create'},
	['window'] = {'create'},
	['tag'] = {5}
})

-- toplevel
makewidget('toplevel')

---- aditional tk 8.5 ttk widgets ----

-- ttk::button widget
makewidget('ttk::button', {'command'}, {
	['instate'] = {3}
}, 'ttk_button')

-- ttk::checkbutton widget
makewidget('ttk::checkbutton', {'command'}, {
	['instate'] = {3}
}, 'ttk_checkbutton')

-- ttk::combobox widget
makewidget('ttk::combobox', {'postcommand'}, {
	['instate'] = {3}
}, 'ttk_combobox')

-- ttk:entry widget
makewidget('ttk::entry', {'xscrollcommand', 'invalidcommand', 'validatecommand'}, {
	['instate'] = {3}
}, 'ttk_entry')

-- ttk::frame widget
makewidget('ttk::frame', nil, {
	['instate'] = {3}
}, 'ttk_frame')

-- ttk::label widget
makewidget('ttk::label', nil, {
	['instate'] = {3}
}, 'ttk_label')

-- ttk::labelframe widget
makewidget('ttk::labelframe', nil, {
	['instate'] = {3}
}, 'ttk_labelframe')

-- ttk::menubutton widget
makewidget('ttk::menubutton', nil, {
	['instate'] = {3}
}, 'ttk_menubutton')

-- ttk::notebook widget
makewidget('ttk::notebook', nil, {
	['instate'] = {3}
}, 'ttk_notebook')

-- ttk::panedwindow widget
makewidget('ttk::panedwindow', nil, {
	['instate'] = {3}
}, 'ttk_panedwindow')

-- ttk::progressbar widget
makewidget('ttk::progressbar', nil, {
	['instate'] = {3}
}, 'ttk_progressbar')

-- ttk::radiobutton widget
makewidget('ttk::radiobutton', {'command'}, {
	['instate'] = {3}
}, 'ttk_radiobutton')

-- ttk::scale widget
makewidget('ttk::scale', {'command'}, {
	['instate'] = {3}
}, 'ttk_scale')

-- ttk::scrollbar widget
makewidget('ttk::scrollbar', {'command'}, {
	['instate'] = {3}
}, 'ttk_scrollbar')

-- ttk::separator widget
makewidget('ttk::separator', nil, {
	['instate'] = {3}
}, 'ttk_separator')

-- ttk::sizegrip widget
makewidget('ttk::sizegrip', {'command'}, {
	['instate'] = {3}
}, 'ttk_sizegrip')

-- ttk::treeview widget
makewidget('ttk::treeview', {'xscrollcommand', 'yscrollcommand'}, {
	['instate'] = {3}
}, 'ttk_treeview')

----- tk and utility functions -----

-- addpackage utility function
--
function ltk.addpackage(pkg)
	return tcl_interp:call('package', 'require', pkg)
end

-- addtkwidget utility function
--
function ltk.addtkwidget(wtype, conf, cmds, uname)
	local mname
	if uname ~= nil then
		mname = 'x_' .. uname
	else
		local fwtype = s_gsub(wtype, ':', '_')
		mname = 'x_' .. fwtype
	end
	makewidget(wtype, conf, cmds, mname)
end

-- tcl after function
-- in order to not re-register functions all the time, we cache registerd
-- functions and try to reuse the registration if possible.
--
function ltk.after(args)
	local arg
	for arg=2, #args do
		local fn = args[arg]
		if type(fn) == 'function' then
			args[arg] = getcachedfuncid(fn)
		elseif type(fn) == 'table' then
			fn[1] = getcachedfuncid(fn[1])
			args[arg] = fn
		end
	end

	return tcl_interp:callt('after', args)
end

-- tk bell function
--
function ltk.bell()
	return tcl_interp:call('bell')
end

-- tk bind function 
--
function bind(args)
	local wid = args[1]
	local events = args[2]
	local i, id, base, cmd, rawcmd
	local add = false
	local widget
	if wid == 'all' then
		widget = all_widgets
	else
		widget = widgets[wid]
	end
	if not widget then error('bad window path name "'..tostring(wid)..'"') end

	base = 3
	if args[base] == '+' then
		base = base + 1
		add = true
	end
	rawcmd = args[base]
	id, cmd = maketkfunc(rawcmd)
	args[base] = cmd

	-- register the function id with the widget
	if id ~= nil then
		t_insert(widget.registered, id)
	end

	-- special treatment for Destroy events: as we register such events ourself
	-- additional Destroy events will be handled internally by the ltk Destroy
	-- event handler.
	if events == '<Destroy>' and rawcmd ~= nil and
			tcl_interp:call('bind', wid, '<Destroy>') ~= '' then
		if add then
			t_insert(widget.destroyfns, cmd)
		else
			widget.destroyfns = { cmd }
		end
	else
		return tcl_interp:callt('bind', args)
	end
end

ltk.bind = bind

-- tk bindtags function
--
function ltk.bindtags(args)
	return tcl_interp:callt('bindtags', wid, tcl_interp:makearglist(args))
end

-- tk clipboard function
--
function ltk.clipboard(args)
	local opts = tcl_interp:makearglist(args)
	if opts[1] == 'append' then
		-- append '- -' then put data at the end of the argument list
		t_insert(opts, '--')
		t_insert(opts, opts[2])
		t_remove(opts, 2)
	end
	return tcl_interp:callt('clipboard', opts)
end

-- tk console function
-- Obacht: this may not be available on all systems (indeed, it is only
-- available on systems without a proper console...)
--
function ltk.console(args)
	return tcl_interp:callt('console', tcl_interp:makearglist(args))
end

-- tk destroy function
-- ltk specific cleanup is handled by the widgets <Destroy> event handlers
--
function ltk.destroy(args)
	return tcl_interp:callt('destroy', tcl_interp:makearglist(args))
end

-- tk event function
--
function ltk.event(args)
	return tcl_interp:callt('event', tcl_interp:makearglist(args))
end

-- tcl/tk exit function
-- exit the tcl/Tk interpreter, and thus the application.
--
function ltk.exit(code)
	code = code or 0
	tcl_interp:call('bind', '.', '<Destroy>', '')
	destroywidget('.', '??', '??', '??', '.')
	res = tcl_interp:call('exit', code)
end

-- tk focus function
--
function ltk.focus(args)
	return tcl_interp:callt('focus', tcl_interp:makearglist(args))
end

-- tk font function
--
function ltk.font(args)
	local opts = tcl_interp:makearglist(args)
	local cmd = opts[1]
	local nopts = #opts
	if cmd == 'actual' or cmd == 'measure' or cmd == 'metrics' then
		if opts[nopts - 1] == '-displayof' then
			t_insert(opts, 3, '-displayof')
			t_insert(opts, 4, opts[nopts+1])
			t_remove(opts, nopts + 2)
			t_remove(opts, nopts + 1)
		end
		if cmd=='actual' and #(opts[nopts]) == 1 then
			t_insert(opts, nopts, '--')
		end
	end
	return tcl_interp:callt('font', opts)
end

-- ltcl fromutf8 function
--
function ltk.fromutf8(str, enc)
	return tcl_interp:fromutf8(str, enc)
end

-- tk grab function
--
function ltk.grab(args)
	return tcl_interp:callt('grab', tcl_interp:makearglist(args))
end

-- tk grid function
--
-- converts lua widgets to tcl widget names then calls tcl grid
--
function ltk.grid(args)
	return tcl_interp:callt('grid', tcl_interp:makearglist(args))
end

-- tk image function
--
function ltk.image(args)
	local cmd = args[1]
	local opts = tcl_interp:makearglist(args)
	if cmd == 'create' then
		local id = genid()
		local wid, widget = widget(imgtype, nil, nil, id)
		t_insert(opts, 3, id)
		local img = tcl_interp:callt('image', opts)
		return wid
	elseif cmd == 'delete' then
		local img, no
		for no=2,#opts do
			img = opts[no]
			widgets[img] = nil
		end
	end
	-- else
	return tcl_interp:call('image', opts)
end

-- tk lower function
--
function ltk.lower(args)
	return tcl_interp:callt('lower', tcl_interp:makearglist(args))
end

-- mainloop utility function
-- add a destroy event handler to the default toplevel window then enter event
-- handler.
--
function ltk.mainloop()
	tcl_interp:call('vwait', 'forever')
end

-- tk option function
--
function ltk.option(args)
	return tcl_interp:callt('option', tcl_interp:makearglist(args))
end

-- tk pack function
--
function ltk.pack(args)
	return tcl_interp:callt('pack', tcl_interp:makearglist(args))
end

-- tk place function
--
function ltk.place(args)
	return tcl_interp:callt('place', tcl_interp:makearglist(args))
end

-- tk raise function
--
function ltk.raise(args)
	return tcl_interp:callt('lower', tcl_interp:makearglist(args))
end

-- tk selection function
--
function ltk.selection(args)
	tcl_interp:callt('selection', tcl_interp:makearglist(args))
end

-- tk send function
--
function ltk.send(args)
	tcl_interp:callt('send', tcl_interp:makearglist(args))
end

-- tk tk function
--
function ltk.tk(args)
	local opts = tcl_interp:makearglist(args)
	local nopts = #opts
	if opts[nopts - 1] == '-displayof' and nopts > 3 then
		t_insert(opts, 2, '-displayof')
		t_insert(opts, 3, opts[nopts+1])
		t_remove(opts, nopts + 2)
		t_remove(opts, nopts + 1)
	end
	return tcl_interp:callt('tk', opts)
end

-- tk tk_bisque function
--
function ltk.tk_bisque(args)
	return tcl_interp:callt('bisque', tcl_interp:makearglist(args))
end

-- tk tk_chooseColor function
--
function ltk.tk_chooseColor(args)
	return tcl_interp:callt('tk_chooseColor', tcl_interp:makearglist(args))
end

-- tk tk_chooseDirectory function
--
function ltk.tk_chooseDirectory(args)
	return tcl_interp:callt('tk_chooseDirectory', tcl_interp:makearglist(args))
end

-- tk tk_dialog function
-- Note: generates its own id, and disposes of it after use
--
function ltk.tk_dialog(args)
	local id = genid()
	table.insert(1, id)
	local res = tcl_interp:callt('tk_dialog', args)
	tcl_interp:call('destroy', id)
	return res
end

-- tk tk_focusFollowsMouse function
--
function ltk.tk_focusFollowsMouse(args)
	return tcl_interp:callt('tk_focusFollowsMouse', tcl_interp:makearglist(args))
end

-- tk tk_focusNext function
--
function ltk.tk_focusNext(args)
	return tcl_interp:callt('tk_focusNext', tcl_interp:makearglist(args))
end

-- tk tk_focusPrev funcion
--
function ltk.tk_focusPrev(args)
	return tcl_interp:callt('tk_focusPrev', tcl_interp:makearglist(args))
end

-- tk tk_getOpenFile function
--
function ltk.tk_getOpenFile(args)
	return tcl_interp:callt('tk_getOpenFile', tcl_interp:makearglist(args))
end

-- tk tk_getSaveFile function
--
function ltk.tk_getSaveFile(args)
	return tcl_interp:callt('tk_getSaveFile', tcl_interp:makearglist(args))
end

-- tk tk_menuSetFocus function
--
function ltk.tk_menuSetFocus(args)
	return tcl_interp:callt('tk_menuSetFocus', tcl_interp:makearglist(args))
end

-- tk tk_messageBox function
--
function ltk.tk_messageBox(args)
	return tcl_interp:call('tk_messageBox', tcl_interp:makearglist(args))
end

-- tk tk_optionMenu function
-- we create a pseudowidget wrapping the menu returned by tk_optionMenu so that
-- a widget command for it can be created to manipulate the widget. The widget
-- created for the optionmenu button is also returned, so that it can be used
-- with layout managers.
--
-- In a deviation from the Tk tk_optionMenu function, the first arg here may
-- also be a function.
--
function ltk.tk_optionMenu(args)
	local var_or_func = args[1]
	local id = genid()
	local wid, button = widget('optionMenu', nil, nil, id)
	local opts = tcl_interp:makearglist(args)
	local tmpvar
	if type(var_or_func) == "function" then
		tmpvar = genid()
		opts[1] = tmpvar
	end
	t_insert(opts , 1, id)
	local rmid = tcl_interp:callt('tk_optionMenu', opts)
	local mid = widget('menu', nil, nil, rmid)
	if tmpvar then
		local cbfunc = function(name1, name2, flags)
			return var_or_func(id, _M.var[name1])
		end
		button.__callback = cbfunc
		tcl_interp:tracevar(tmpvar, nil, tcl_interp.TRACE_WRITES, cbfunc)
	end
	return wid, mid
end

-- tk tk_popup function
--
function ltk.tk_popup(args)
	return tcl_interp:callt('tk_popup', tcl_interp:makearglist(args))
end

-- tk tk_setPalette function
--
function ltk.tk_setPalette(args)
	tcl_interp:callt('tk_setPalette', tcl_interp:makearglist(args))
end

-- tk tk_textCopy function
--
function ltk.tk_textCopy(args)
	return tcl_interp:callt('tk_textCopy', tcl_interp:makearglist(args))
end

-- tk tk_textCut function
--
function ltk.tk_textCut(args)
	return tcl_interp:callt('tk_textCut', tcl_interp:makearglist(args))
end

-- tk tk_textPaste function
--
function ltk.tk_textPaste(args)
	return tcl_interp:callt('tk_textPaste', tcl_interp:makearglist(args))
end

-- tk tkwait function
--
function ltk.tkwait(args)
	return tcl_interp:callt('tkwait', tcl_interp:makearglist(args))
end

-- ltcl toutf8 function
--
function ltk.toutf8(str, enc)
	return tcl_interp:toutf8(str, enc)
end

-- tcl update function
--
function ltk.update(args)
	return tcl_interp:callt('update', tcl_interp:makearglist(args))
end

-- vals utility function
-- packs its arguments into a ltcl:tuple
--
function ltk.vals(...)
	return tcl_interp:vals(...)
end

-- wcmd utility function
-- used to call widget commands
--
function ltk.wcmd(wid)
	local widget = widgets[wid]
	if not widget then error('bad window path name "'..tostring(wid)..'"') end
	if not widget.command then
		widget.command = function(args)
			local fix = widget.fixlist[args[1]]
			if fix then fix(widget, args) end
			return tcl_interp:callt(wid, tcl_interp:makearglist(args))
		end
	end
	return widget.command
end

-- widgettype utility function
-- return type of tk widget or nil, if the argument is not a ltk widget
--
function ltk.widgettype(wid)
	local widget = widgets[wid]
	if widget then
		return widget.which
	end
	return nil
end

-- tk winfo function
--
function ltk.winfo(args)
	local opts = tcl_interp:makearglist(args)
	local nopts = #opts
	if opts[nopts - 1] == '-displayof' and nopts > 3 then
		t_insert(opts, 2, '-displayof')
		t_insert(opts, 3, opts[nopts+1])
		t_remove(opts, nopts + 2)
		t_remove(opts, nopts + 1)
	end
	return tcl_interp:callt('winfo', opts)
end

-- tk wm function
--
function ltk.wm(args)
	return tcl_interp:callt('wm', tcl_interp:makearglist(args))
end

----- ttk functions -----

-- ttk::style function
--
function ltk.ttk_style(args)
	if cmd == 'theme' then
		if args['settings'] then
			args['settings'] = getcachedfuncid(args['settings'])
		end
		opts = tcl_interp:makearglist(args)
		local scmd = opts[2]
		if scmd == 'settings' then
			opts[4] = getcachedfuncid(opts[4])
		end
	else
		opts = tcl_interp:makearglist(args)
	end
	return tcl_interp:callt('ttk::style', opts)
end

-- ttk_vsapi function
--
function ltk.ttk_vsapi(args)
	return tcl_interp:callt('ttk_vsapi', tcl_interp:makearglist(args))
end

-- prepare main '.' window so that closing it will do the right thing.
bind{'.', '<Destroy>', {
	function(wid)
		if wid=='.' then
			_M.exit()
		end
	end, '%W'}}

return ltk
