#!/usr/bin/env lua

--[[
 - tkhello.lua
 -
 - Gunnar Zötl <gz@tset.de>, 2010.
 - Released under MIT/X11 license. See file LICENSE for details.
--]]

-- straight port of Tk8.5 widget example to ltk, original header follows:
--
--# hello --
--# Simple Tk script to create a button that prints "Hello, world".
--# Click on the button to terminate the program.
--#
--# RCS: @(#) $Id: hello,v 1.4 2003/09/30 14:54:30 dkf Exp $

require "ltk"

-- The first line below creates the button, and the second line
-- asks the packer to shrink-wrap the application's main window
-- around the button.

hello = ltk.button{text="Hello, world", command=function()
		print "Hello, world!"
		ltk.exit()
	end}
ltk.pack{hello}

ltk.mainloop()
