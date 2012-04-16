#!/usr/bin/env lua

--[[
 - ltkbrowse.lua
 -
 - Gunnar Zötl <gz@tset.de>, 2010.
 - Released under MIT/X11 license. See file LICENSE for details.
--]]

-- straight port of Tk8.5 widget example to ltk, original header follows:
--
--# browse --
--# This script generates a directory browser, which lists the working
--# directory and allows you to open files or subdirectories by
--# double-clicking.
--#
--# RCS: @(#) $Id: browse,v 1.5 2003/09/30 14:54:29 dkf Exp $

require "ltk"
local lfs = require "lfs"
local lua = arg[-1]

-- Create a scrollbar on the right side of the main window and a listbox
-- on the left side.

scroll = ltk.scrollbar {}
list = ltk.listbox {yscroll=scroll.." set", relief="sunken", width=20, height=20,
	setgrid=true}
lcmd = ltk.wcmd(list)
ltk.wcmd(scroll){'configure', command=list.." yview"}
ltk.pack{scroll, side='right', fill='y'}
ltk.pack{list, side='left', fill='both', expand='yes'}
ltk.wm{'minsize', '.', 1, 1}

-- The procedure below is invoked to open a browser on a given file;  if the
-- file is a directory then another instance of this program is invoked; if
-- the file is a regular file then the Mx editor is invoked to display
-- the file.

if string.find(arg[0], '/') == 1 then
	browseScript=lfs.currentdir()..'/'..arg[0]
else
	browseScript=arg[0]
end
function browse(dir, file)
    file=dir..'/'..file
    local ftype = lfs.attributes(file).mode
    if ftype=="directory" then
		os.execute(lua.." "..browseScript.." "..file.." &")
	elseif ftype=="file" then
		if os.getenv("EDITOR") then
			os.execute(os.getenv("EDITOR").." "..file.." &")
		else
			os.execute("xedit "..file.." &")
		end
	else
			print("'"..file.."' isn't a directory or regular file")
	end
end

-- Fill the listbox with a list of all the files in the directory.

if #arg>0 then
	dir=arg[1]
else
	dir="."
end
files = {}
for f in lfs.dir(dir) do
	table.insert(files, f)
end
table.sort(files)
for _,i in ipairs(files) do
    if lfs.attributes(dir..'/'..i).mode == 'directory' then
		i = i .. '/'
    end
    lcmd{'insert', 'end', i}
end

-- Set up bindings for the browser.
-- strangely enough, binding to 'all' throws an error, eventhough when doing it
-- through ltk.tcl:eval(), it works... No problem, as binding to '.' does the
-- same thing when there is only one window.
ltk.bind{'all', '<Control-c>', ltk.exit}
ltk.bind{list, '<Double-Button-1>', function()
		local n = lcmd{'curselection'}
		browse(dir, lcmd{'get', n})
	end}

ltk.mainloop()
