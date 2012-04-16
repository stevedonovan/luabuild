#!/usr/bin/env lua

--[[
 - tktcolor.lua
 -
 - Gunnar Zötl <gz@tset.de>, 2010.
 - Released under MIT/X11 license. See file LICENSE for details.
--]]

-- straight port of Tk8.5 widget example to ltk, original header follows:
--
--# tcolor --
--# This script implements a simple color editor, where you can
--# create colors using either the RGB, HSB, or CYM color spaces
--# and apply the color to existing applications.
--#
--# RCS: @(#) $Id: tcolor,v 1.6 2007/12/13 15:27:07 dgp Exp $

-- as this is a straight port, it is not very lua-ish, but is shows how certain
-- things can be done.

require "ltk"
ltk.wm{'title', '.', "Color Editor"}

--[==[
# Global variables that control the program:
#
# colorSpace -			Color space currently being used for
#				editing.  Must be "rgb", "cmy", or "hsb".
# label1, label2, label3 -	Labels for the scales.
# red, green, blue -		Current color intensities in decimal
#				on a scale of 0-65535.
# color -			A string giving the current color value
#				in the proper form for x:
#				#RRRRGGGGBBBB
# updating -			Non-zero means that we're in the middle of
#				updating the scales to load a new color,so
#				information shouldn't be propagating back
#				from the scales to other elements of the
#				program:  this would make an infinite loop.
# command -			Holds the command that has been typed
#				into the "Command" entry.
# autoUpdate -			1 means execute the update command
#				automatically whenever the color changes.
# name -			Name for new color, typed into entry.
--]==]

ltk.var.colorSpace = 'hsb'
ltk.var.red = 65535
ltk.var.green = 0
ltk.var.blue = 0
ltk.var.color = '#ffff00000000'
ltk.var.updating = 0
ltk.var.autoUpdate = 1
ltk.var.name = ""

scales = {}
_sample_swatch = ''

-- The procedure below is invoked when the "Update" button is pressed,
-- and whenever the color changes if update mode is enabled.  It
-- propagates color information as determined by the command in the
-- Command entry.

function doUpdate ()
    --global color command
    newCmd = ltk.var.command
    newCmd = string.gsub(newCmd, '%%%%', ltk.var.color)
    ltk.tcl:eval(newCmd)
end

-- The procedure below is invoked when one of the scales is adjusted.
-- It propagates color information from the current scale readings
-- to everywhere else that it is used.

function tc_scaleChanged()
    --global red green blue colorSpace color updating autoUpdate
    local colorspace = ltk.var.colorSpace
    if ltk.var.updating ~= 0 then
		return
    end
    if colorspace == 'rgb' then
	    ltk.var.red = string.format("%.0f", ltk.wcmd(scales[1]){'get'}*65.535)
	    ltk.var.green = string.format("%.0f", ltk.wcmd(scales[2]){'get'}*65.535)
	    ltk.var.blue = string.format("%.0f", ltk.wcmd(scales[3]){'get'}*65.535)
	elseif colorspace == 'cmy' then
	    ltk.var.red = string.format("%.0f", 65535 - ltk.wcmd(scales[1]){'get'}*65.535)
	    ltk.var.green = string.format("%.0f", 65535 - ltk.wcmd(scales[2]){'get'}*65.535)
	    ltk.var.blue = string.format("%.0f", 65535 - ltk.wcmd(scales[3]){'get'}*65.535)
	elseif colorspace == 'hsb' then
	    local r, g, b = hsbToRgb(ltk.wcmd(scales[1]){'get'}/1000.0,
		    ltk.wcmd(scales[2]){'get'}/1000.0,
		    ltk.wcmd(scales[3]){'get'}/1000.0)
		ltk.var.red = r
		ltk.var.green = g
		ltk.var.blue = b
	end

    ltk.var.color = string.format("#%04x%04x%04x", ltk.var.red, ltk.var.green, ltk.var.blue)
    ltk.wcmd(_sample_swatch){'config', bg=ltk.var.color}
    if ltk.var.autoUpdate then doUpdate() end
    ltk.update{'idletasks'}
end

-- The procedure below is invoked to update the scales from the
-- current red, green, and blue intensities.  It's invoked after
-- a change in the color space and after a named color value has
-- been loaded.

function tc_setScales()
    --global red green blue colorSpace updating
    local colorspace = ltk.var.colorSpace
    local red, green, blue = tonumber(ltk.var.red), tonumber(ltk.var.green), tonumber(ltk.var.blue)
    ltk.var.updating=true
    if colorspace=='rgb' then
	    ltk.wcmd(scales[1]){'set', string.format('%.0f', red/65.535)}
	    ltk.wcmd(scales[2]){'set', string.format('%.0f', green/65.535)}
	    ltk.wcmd(scales[3]){'set', string.format('%.0f', blue/65.535)}
	elseif colorspace=='cmy' then
	    ltk.wcmd(scales[1]){'set', string.format('%.0f', (65535-red)/65.535)}
	    ltk.wcmd(scales[2]){'set', string.format('%.0f', (65535-green)/65.535)}
	    ltk.wcmd(scales[3]){'set', string.format('%.0f', (65535-blue)/65.535)}
	elseif colorspace=='hsb' then
	    local h, s, v = rgbToHsv(red, green, blue)
	    ltk.wcmd(scales[1]){'set', string.format('%.0f', h * 1000.0)}
	    ltk.wcmd(scales[2]){'set', string.format('%.0f', s * 1000.0)}
	    ltk.wcmd(scales[3]){'set', string.format('%.0f', v * 1000.0)}
	end
    ltk.var.updating=false
end

-- The procedure below is invoked when a new color space is selected.
-- It changes the labels on the scales and re-loads the scales with
-- the appropriate values for the current color in the new color space

function changeColorSpace(space)
    --global label1 label2 label3
    if space == 'rgb' then
	    ltk.var.label1 = "Adjust Red:"
	    ltk.var.label2 = "Adjust Green:"
	    ltk.var.label3 = "Adjust Blue:"
	    tc_setScales()
	elseif space == 'cmy' then
	    ltk.var.label1 = "Adjust Cyan:"
	    ltk.var.label2 = "Adjust Magenta:"
	    ltk.var.label3 = "Adjust Yellow:"
	    tc_setScales()
	elseif space == 'hsb' then
	    ltk.var.label1 = "Adjust Hue:"
	    ltk.var.label2 = "Adjust Saturation:"
	    ltk.var.label3 = "Adjust Brightness:"
	    tc_setScales()
	end
end

-- The procedure below is invoked when a named color has been
-- selected from the listbox or typed into the entry.  It loads
-- the color into the editor.

function tc_loadNamedColor(wname)
	local name
	if ltk.widgettype(wname) == 'entry' then
		name = ltk.wcmd(wname){'get'}
	else
		name = ltk.wcmd(wname){'get', ltk.wcmd(wname){'curselection'}}
	end
	local r, g, b
    --global red green blue color autoUpdate

    if string.sub(name, 1, 1) ~= "#" then
		local lst =ltk.winfo{'rgb', _sample_swatch, name}
		r, g, b = string.match(lst, "^(%d+) (%d+) (%d+)$")
		ltk.var.red = r
		ltk.var.green = g
		ltk.var.blue = b
    else
		local len = #name
		if len == 4 then
			format = "#(%1x)(%1x)(%1x)"
			shift = 12
		elseif len == 7 then
			format = "#(%2x)(%2x)(%2x)"
			shift = 8
		elseif len == 10 then
			format = "#(%3x)(%3x)(%3x)"
			shift = 4
		elseif len == 13 then
			format = "#(%4x)(%4x)(%4x)"
			shift = 0
		else
			error("syntax error in color name \""..name.."\"")
		end
		r, g, b = string.match(name, format)
		if not r or not g or not b then
			error("syntax error in color name \""..name.."\"")
		end
		ltk.var.red = r * 2^shift
		ltk.var.green = g * 2^shift
		ltk.var.blue = b * 2^shift
	end
    tc_setScales()
    ltk.var.color = string.format("#%04x%04x%04x", r, g, b)
    ltk.wcmd(_sample_swatch){'config', bg=color}
    if ltk.var.autoUpdate then doUpdate() end
end

-- The procedure below converts an RGB value to HSB.  It takes red, green,
-- and blue components (0-65535) as arguments, and returns a list containing
-- HSB components (floating-point, 0-1) as result.  The code here is a copy
-- of the code on page 615 of "Fundamentals of Interactive Computer Graphics"
-- by Foley and Van Dam.

function rgbToHsv(red, green, blue)
	local max, min, range, hue, sat
    if red > green then
		max, min = red, green
    else
		max, min = green, red
    end
    if blue > max then
		max = blue
    elseif blue < min then
		min = blue
    end
    range = max - min
    if max == 0 then
		sat = 0
    else
		sat = (max - min) / max
    end
    if sat == 0 then
		hue = 0
    else
		local rc = (max - red) / range
		local gc = (max - green) / range
		local bc = (max - blue) / range
		if red == max then
			hue = (bc - gc) / 6.0
		elseif green == max then
			hue = (2 + rc - bc) / 6.0
		else
			hue = (4 + gc - rc) / 6.0
		end
		if hue < 0.0 then
			hue = hue + 1.0
		end
	end
    return hue, sat, max/65535
end

-- The procedure below converts an HSB value to RGB.  It takes hue, saturation,
-- and value components (floating-point, 0-1.0) as arguments, and returns a
-- list containing RGB components (integers, 0-65535) as result.  The code
-- here is a copy of the code on page 616 of "Fundamentals of Interactive
-- Computer Graphics" by Foley and Van Dam.

function hsbToRgb(hue, sat, value)
    local v = string.format("%.0f", 65535.0*value)
    if sat == 0 then
		return v, v, v
    else
		hue = hue * 6.0
		if hue >= 6.0 then
			hue = 0.0
		end
		i = math.floor(hue)
		local f = hue - i
		local p = string.format('%.0f', 65535.0 * value * (1 - sat))
		local q = string.format('%.0f', 65535.0 * value * (1 - (sat * f)))
		local t = string.format('%.0f', 65535.0 * value * (1 - (sat * (1 - f))))
		if i == 0 then
			return v, t, p
		elseif i == 1 then
			return q, v, p
		elseif i == 2 then
			return p, v, t
		elseif i == 3 then
			return p, q, v
		elseif i == 4 then
			return t, p, v
		elseif i == 5 then
			return v, p, q
		else
			error("i value "..tostring(i).." is out of range")
		end
	end
end

-- Create the menu bar at the top of the window.

_menu = ltk.menu {}
ltk.wcmd('.'){'configure', menu=_menu}
_file = ltk.menu(_menu){}
ltk.wcmd(_menu){'add', 'cascade', menu=_file, label='File', underline=0}
_file_cmd = ltk.wcmd(_file)
_file_cmd{'add', 'radio', label="RGB color space", variable='colorSpace',
	value='rgb', underline=0, command={changeColorSpace, 'rgb'}}
_file_cmd{'add', 'radio', label="CMY color space", variable='colorSpace',
	value='cmy', underline=0, command={changeColorSpace, 'cmy'}}
_file_cmd{'add', 'radio', label="HSB color space", variable='colorSpace',
	value='hsb', underline=0, command={changeColorSpace, 'hsb'}}
_file_cmd{'add', 'separator'}
_file_cmd{'add', 'radio', label="Automatic updates", variable='autoUpdate',
	value=1, underline=0}
_file_cmd{'add', 'radio', label="Manual updates", variable='autoUpdate',
	value=0, underline=0}
_file_cmd{'add', 'separator'}
_file_cmd{'add', 'command', label="Exit program", underline=0, command=ltk.exit}

-- Create the command entry window at the bottom of the window, along
-- with the update button.

_command = ltk.labelframe{text="Command:", padx={'1m', 0}}
_command_e = ltk.entry(_command){textvariable='command'}
_command_update = ltk.button(_command){text='Update', command=doUpdate}
ltk.pack{_command_update, side='right', pady='.1c', padx={'.25c', 0}}
ltk.pack{_command_e, expand='yes', fill='x', ipadx='0.25c'}

-- Create the listbox that holds all of the color names in rgb.txt,
-- if an rgb.txt file can be found.

ltk.grid{_command, sticky='nsew', row=2, columnspan=3, padx='1m', pady={0, '1m'}}

ltk.grid{'columnconfigure', '.', {1, 2}, weight=1}
ltk.grid{'rowconfigure', '.', 0, weight=1}

for _, i in ipairs {
    '/usr/local/lib/X11/rgb.txt', '/usr/lib/X11/rgb.txt',
    '/X11/R5/lib/X11/rgb.txt', '/X11/R4/lib/rgb/rgb.txt',
    '/usr/openwin/lib/X11/rgb.txt', '/etc/X11/rgb.txt'
} do
	f = io.open(i, 'r')
	if f then
		_names = ltk.labelframe{text="Select:", padx='.1c', pady='1c'}
		ltk.grid{_names, row=0, column=0, sticky='nsew', padx='.15c', pady='.15c', rowspan=2}
		ltk.grid{'columnconfigure', '.', 0, weight=1}
		_names_lb = ltk.listbox(_names){width=20, height=12, exportselection=false}
		_names_s = ltk.scrollbar(_names){orient='vertical', command=_names_lb.." yview"}
		ltk.wcmd(_names_lb){'configure', yscrollcommand=_names_s.." set"}
		ltk.bind{_names_lb, '<Double-1>', {tc_loadNamedColor, _names_lb}}
		ltk.pack{_names_lb, _names_s, side='left', fill='y', expand=1}
		for line in f:lines() do
			col = string.match(line, '^%s*%d+%s+%d+%s+%d+%s+([^%s]+)%s*$')
			if col then
				ltk.wcmd(_names_lb){'insert', 'end', col}
			end
		end
		f:close()
    end
end

-- Create the three scales for editing the color, and the entry for
-- typing in a color value.

_adjust = ltk.frame{}
labels = {}
labelframes = {}
for i=1,3 do
    labels[i] = ltk.label(_adjust){textvariable="label"..tostring(i), pady=0}
    labelframes[i] = ltk.labelframe(_adjust){labelwidget=labels[i], padx='1m', pady='1m'}
    scales[i] = ltk.scale{from=0, to=1000, length='6c', orient='horizontal',
	    command=tc_scaleChanged}
    ltk.pack{scales[i], ['in']=labelframes[i]}
    ltk.pack{labelframes[i]}
end
ltk.grid{_adjust, row=0, column=1, sticky='nsew', padx='.15c', pady='.15c'}

_name = ltk.labelframe{text="Name:", padx='1m', pady='1m'}
_name_e = ltk.entry(_name){textvariable='name', width=10}
ltk.pack{_name_e, side='right', expand=1, fill='x'}
ltk.bind{_name_e, '<Return>', {tc_loadNamedColor, _name_e}}
ltk.grid{_name, column=1, row=1, sticky='nsew', padx='.15c', pady='.15c'}

-- Create the color display swatch on the right side of the window.

_sample = ltk.labelframe{text="Color:", padx='1m', pady='1m'}
_sample_swatch = ltk.frame(_sample){width='2c', height='5c', background=ltk.var.color}
_sample_value = ltk.label(_sample){textvariable='color', width=13, font={'Courier', 12}}
ltk.pack{_sample_swatch, side='top', expand='yes', fill='both'}
ltk.pack{_sample_value, side='bottom', pady='.25c'}
ltk.grid{_sample, row=0, column=2, sticky='nsew', padx='.15c', pady='.15c', rowspan=2}

changeColorSpace('hsb')

ltk.mainloop()
