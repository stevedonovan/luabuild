#!/usr/bin/env lua

--[[
 - ltcltest.lua
 -
 - an attempt at a test suite for ltcl interpreter integration. Probably not comprehensive, but
 - should cover a most of the functionality.
 -
 - Gunnar Zötl <gz@tset.de>, 2010
 - Released under MIT/X11 license. See file LICENSE for details.
--]]

require "ltcl"

tcl = ltcl.new()

ntests = 0
nfailed = 0

-- utilities

-- announce which test we are performing and what it tests
function announce(str)
	str = str or ""
	ntests = ntests + 1
	print("Test " .. tostring(ntests) .. ": " .. str)
end

-- print that the test did not ork out and optionally why
function fail(str)
	local msg = "  TEST FAILED"
	nfailed = nfailed + 1
	if str ~= nil then msg = msg .. ": " .. str end
	print(msg)
end

-- just prints wether the test went ok or not. An optional reason for failure may be passed,
-- which will then be printed.
function check(ok, msg)
	if ok==false then
		fail(msg)
	else
		print "  TEST OK"
	end
end

-- compare 2 tables. tables converted from tcl lists may not necessarily have proper types on all elements,
-- so we compare using a vaguely type agnostic compare function
function cmptables(v1, v2)
	local mycmp = function(x, y)
		if type(x) == 'table' and type(y) == 'table' then
			return cmptables(x, y)
		else
			return tostring(x) == tostring(y)
		end
	end
	if type(v1) ~= 'table' or type(v2) ~= 'table' then
		return false
	else
		-- Obacht: values in lists end up as strings (or rather, have no explicit types) in tcl
		local ok = true
		for i, v in ipairs(v1) do
			ok = ok and mycmp(v, v2[i])
		end
		for i, v in ipairs(v2) do
			ok = ok and mycmp(v1[i], v)
		end
		return ok
	end
end

-- careful: no recursion checks!
-- just for debugging purposes
function dumpval(val, pfx)
	pfx = pfx or ""
	local t = type(val)
	if t == 'string' then
		print('"' .. val .. '"')
	elseif t == 'table' then
		print('{')
		local lpfx = pfx .. '  '
		for k, v in pairs(val) do
			io.write(pfx .. '[' .. k .. '] = ')
			dumpval(v, lpfx .. "  ")
		end
		print(pfx .. '}')
	else
		print(tostring(val))
	end		
end

-- now for the tests.

----- get*/set* variables -----

-- tests variable access, data type conversion both from and to tcl and error propagation.

-- 1
announce("Setting variable vnum to number 1")
check(pcall(ltcl.setvar, tcl, 'vnum', 1))

-- 2
announce("reading vnum back, result should be a number 1")
ok, val = pcall(ltcl.getvar, tcl, 'vnum')
if ok then
	check(val == 1)
else
	fail(tostring(val))
end

-- 3
announce("Reading unset var vbool (should fail)")
ok, val = pcall(ltcl.getvar, tcl, 'vbool')
check(not ok)

-- 4
announce("Setting nowhere::var to 1 (should fail)")
ok = pcall(ltcl.setvar, tcl, 'nowhere::var', 1)
check(not ok)

-- 5
announce("Setting variable vbool to boolean true")
check(pcall(ltcl.setvar, tcl, 'vbool', true))

-- 6
announce("reading vbool back, result should be a number 1")
ok, val = pcall(ltcl.getvar, tcl, 'vbool')
if ok then
	check(val == 1)
else
	fail(tostring(val))
end

-- 7
announce("Setting variable vstr to string 'Hallo'")
check(pcall(ltcl.setvar, tcl, 'vstr', "Hallo"))

-- 8
announce("Reading vstr back, result should be a string 'Hallo'")
ok, val = pcall(ltcl.getvar, tcl, 'vstr')
if ok then
	check(val == 'Hallo')
else
	fail(tostring(val))
end

-- 9
announce("Setting variable vlst to list {1, 2, 3, 'a', 'b', 'c'}")
check(pcall(ltcl.setvar, tcl, 'vlst', {1, 2, 3, 'a', 'b', 'c'}))

-- 10
announce("Reading vlst back, result should be a table {1, 2, 3, 'a', 'b', 'c'}")
ok, val = pcall(ltcl.getvar, tcl, 'vlst')
if ok then
	check(cmptables(val, {1, 2, 3, 'a', 'b', 'c'}))
else
	fail(tostring(val))
end

-- 11
announce("Setting variable vnlst to list {1, {2, {3, 4}, 5}, 6}")
check(pcall(ltcl.setvar, tcl, 'vnlst', {1, {2, {3, 4}, 5}, 6}))

-- 12
announce("Reading vnlst back, result should be a table {1, {2, {3, 4}, 5}, 6}")
ok, val = pcall(ltcl.getvar, tcl, 'vnlst')
if ok then
	check(cmptables(val, {1, {2, {3, 4}, 5}, 6}))
else
	fail(tostring(val))
end

-- 13
announce("Setting variable vapp1 to string 'abc' then appending 'def'")
ok = pcall(ltcl.setvar, tcl, 'vapp1', 'abc')
check(pcall(ltcl.setvar, tcl, 'vapp1', 'def', ltcl.APPEND_VALUE))

-- 14
announce("Reading vapp1 back, result should be a string 'abcdef'")
ok, val = pcall(ltcl.getvar, tcl, 'vapp1')
if ok then
	check(val == 'abcdef')
else
	fail(tostring(val))
end

-- 15
announce("Setting variable vapp2 to list {1,2,3} then appending 4")
ok = pcall(ltcl.setvar, tcl, 'vapp2', {1,2,3})
check(pcall(ltcl.setvar, tcl, 'vapp2', 4, ltcl.APPEND_VALUE+ltcl.LIST_ELEMENT))

-- 16
announce("Reading vapp2 back, result should be a table {1,2,3,4}")
ok, val = pcall(ltcl.getvar, tcl, 'vapp2')
if ok then
	check(cmptables(val, {1,2,3,4}))
else
	fail(tostring(val))
end

-- 17
announce("Appending list {5,6} to vapp2")
check(pcall(ltcl.setvar, tcl, 'vapp2', {5,6}, ltcl.APPEND_VALUE+ltcl.LIST_ELEMENT))

-- 18
announce("Reading vapp2 back, result should be a table {1,2,3,4,{5,6}}")
ok, val = pcall(ltcl.getvar, tcl, 'vapp2')
if ok then
	check(cmptables(val, {1,2,3,4,{5,6}}))
else
	fail(tostring(val))
end

-- 19
announce("Setting variable vnil to nil")
check(pcall(ltcl.setvar, tcl, 'vnil', nil))

-- 20
announce("Reading vnil back, result should be an empty string ''")
ok, val = pcall(ltcl.getvar, tcl, 'vnil')
if ok then
	check(val == '')
else
	fail(tostring(val))
end

-- array tests

-- 21
announce("Attempting to refer to index 1 or array variable varr1, should fail")
ok, msg = pcall(ltcl.getarray, tcl, 'varr1', 1)
check(not ok)

-- 22
announce("creating an array {'a' 1 'b' 2 'c' 3} from tcl, then read indices 'a', 'b', 'c' from it. Should return 1, 2, 3 in turn.")
ok, msg = pcall(ltcl.call, tcl, 'array', 'set', 'varr1', {'a', 1, 'b', 2, 'c', 3})
if ok then
	lok, val = pcall(ltcl.getarray, tcl, 'varr1', 'a')
	ok = ok and lok and val == 1
	lok, val = pcall(ltcl.getarray, tcl, 'varr1', 'b')
	ok = ok and lok and val == 2
	lok, val = pcall(ltcl.getarray, tcl, 'varr1', 'c')
	ok = ok and lok and val == 3
	check(ok)
else
	fail(tostring(msg))
end

-- 23
announce("adding 'd'=4 to varr1, then read index 'd' back, should return a number 4")
ok, msg = pcall(ltcl.setarray, tcl, 'varr1', 'd', 4)
if ok then
	ok, val = pcall(ltcl.getarray, tcl, 'varr1', 'd')
	if ok then
		check(val == 4)
	else
		fail(tostring(msg))
	end
else
	fail(tostring(msg))
end

-- 24
announce("retrieving undefined index 'e' from varr1, should fail")
ok = pcall(ltcl.getarray, tcl, 'varr1', 'e')
check(not ok)

-- 25
announce("creating recursive table a={a}, then setting Tcl var to it. Should fail.")
rectbl={}
rectbl[1]=rectbl
ok = pcall(ltcl.setvar, tcl, 'rectbl', rectbl)
check(not ok)

-- 26
announce("creating recursive table a={{a[2]},{a[1]}}, then setting Tcl var to it. Should fail.")
rectbl={}
rectbl[1]={}
rectbl[2] = {rectbl[1]}
rectbl[1][1] = rectbl[2]
ok = pcall(ltcl.setvar, tcl, 'rectbl', rectbl)
check(not ok)


-- no tests for flags ltcl.GLOBAL_ONLY and ltcl.NAMESPACE_ONLY

----- evaluating stuff -----

-- tests basic tcl expression evaluation, result conversion and error propagation

-- 27
announce("Calling makearglist with {1,2,3}, should return {1,2,3}")
ok, val = pcall(ltcl.makearglist, tcl, {1,2,3})
if ok then
	check(cmptables(val, {1,2,3}))
else
	fail(tostring(val))
end

-- 28
announce("TCalling 'list' with a 200 parameter array, should return a table with said 200 values")
parms = {}
for i=1,200 do parms[i] = i end
ok, val = pcall(ltcl.makearglist, tcl, parms)
if ok then
	check(#val==200 and cmptables(val, parms))
else
	fail(tostring(val))
end

-- 29
announce("TCalling 'list' with a 100 entry parameter hash, should return a 200 entry list with matching entries")
hparms = {}
for i=1,100 do hparms["key"..tostring(i)] = "val"..tostring(i) end
ok, val = pcall(ltcl.makearglist, tcl, hparms)
if ok then
	ok = #val == 200
	for i=1,200,2 do
		k0 = val[i]
		v = val[i+1]
		k = string.sub(k0, 2)
		ok = ok and hparms[k] == v
		hparms[k] = nil -- ensure that this key/value pair can not be found again
	end
	check(ok)
else
	fail(tostring(val))
end

-- 30
announce("Calling makearglist with {1,2,3,c=4}, should return {1,2,3, '-c',4}")
ok, val = pcall(ltcl.makearglist, tcl, {1,2,3,c=4})
if ok then
	check(cmptables(val, {1,2,3,'-c',4}))
else
	fail(tostring(val))
end

-- 31
announce("Evaluating 'return $vnum', result should be a number 1")
ok, val = pcall(ltcl.eval, tcl, 'return $vnum')
if ok then
	check(val == 1)
else
	fail(tostring(val))
end

-- 32
announce("Evaluating 'return $vbool', result should be a number 1")
ok, val = pcall(ltcl.eval, tcl, 'return $vbool')
if ok then
	check(val == 1)
else
	fail(tostring(val))
end

-- 33
announce("Evaluating 'return $vstr', result should be a string 'Hallo'")
ok, val = pcall(ltcl.eval, tcl, 'return $vstr')
if ok then
	check(val == 'Hallo')
else
	fail(tostring(val))
end

-- 34
announce("Evaluating 'return $vlst', result should be a table {1, 2, 3, 'a', 'b', 'c'}")
ok, val = pcall(ltcl.eval, tcl, 'return $vlst')
if ok then
	check(cmptables(val, {1, 2, 3, 'a', 'b', 'c'}))
else
	fail(tostring(val))
end

-- 35
announce("Evaluating 'return $vnlst', result should be a table {1, {2, {3, 4}, 5}, 6}")
ok, val = pcall(ltcl.eval, tcl, 'return $vnlst')
if ok then
	check(cmptables(val, {1, {2, {3, 4}, 5}, 6}))
else
	fail(tostring(val))
end

-- 36
announce("Evaluating 'return $vnil, result should be an empty string ''")
ok, val = pcall(ltcl.eval, tcl, 'return $vnil')
if ok then
	check(val == '')
else
	fail(tostring(val))
end

-- 37
announce("Evaluating 'bla fasel', should fail")
ok = pcall(ltcl.eval, tcl, 'bla fasel')
check(not ok)

-- 38
announce("Evaluating 'expr 1+2', result should be a number 3")
ok, val = pcall(ltcl.eval, tcl, 'expr 1+2')
if ok then
	check(val == 3)
else
	fail(tostring(val))
end

-- 39
announce("Evaluating 'return \"Hallo\"', result should be a string 'Hallo'")
ok, val = pcall(ltcl.eval, tcl, 'return "Hallo"')
if ok then
	check(val == "Hallo")
else
	fail(tostring(val))
end

-- 40
announce("Evaluating 'list 1 2 3', result should be a table {1,2,3}")
ok, val = pcall(ltcl.eval, tcl, 'list 1 2 3')
if ok then
	check(cmptables(val, {1,2,3}))
else
	fail(tostring(val))
end

-- 41
announce("Evaluating 'list 1 [list 2 3] 4', result should be a table {1,{2,3},4}")
ok, val = pcall(ltcl.eval, tcl, 'list 1 [list 2 3] 4')
if ok then
	check(cmptables(val, {1,{2,3},4}))
else
	fail(tostring(val))
end

-- calling into tcl

-- tests parameter conversion and error propagation, everything else should be reasonably well tested by now

-- 42
announce("Calling 'expr' with parameters 1, '+', 2, result should be a number 3")
ok, val = pcall(ltcl.call, tcl, 'expr', 1, '+', 2)
if ok then
	check(val == 3)
else
	fail(tostring(val))
end

-- 43
announce("Calling 'list' with parameters 1,2,3, result should be a table {1,2,3}")
ok, val = pcall(ltcl.call, tcl, 'list', 1, 2, 3)
if ok then
	check(cmptables(val, {1,2,3}))
else
	fail(tostring(val))
end

-- 44
announce("Calling 'concat' with parameter 'Hallo', result should be a string 'Hallo'")
ok, val = pcall(ltcl.call, tcl, 'concat', 'Hallo')
if ok then
	check(val == 'Hallo')
else
	fail(tostring(val))
end

-- 45
announce("Calling 'bla' without parameter, should fail")
ok = pcall(ltcl.call, tcl, 'bla')
check(not ok)

-- 46
announce("Calling 'bla' with parameter 'fasel', should fail")
ok = pcall(ltcl.call, tcl, 'bla', 'fasel')
check(not ok)

-- 47
announce("Calling 'puts' with parameters 1,2, should fail")
ok = pcall(ltcl.call, tcl, 'puts', 1, 2)
check(not ok)

-- 48
announce("TCalling 'list' with parameter array {1,2,3}, should return a table {1,2,3}")
ok, val = pcall(ltcl.callt, tcl, 'list', {1,2,3})
if ok then
	check(cmptables(val, {1,2,3}))
else
	fail(tostring(val))
end

-- 49
announce("Making argument list from {1,2,c=3} then TCalling list with this list, should return a table {1,2,'-c',3}")
ok, args = pcall(ltcl.makearglist, tcl, {1,2,c=3})
ok, val = pcall(ltcl.callt, tcl, 'list', args)
if ok then
	check(cmptables(val, {1,2,'-c',3}))
else
	fail(tostring(val))
end

-- 50
announce("Making argument list from {1,c=2,3} then TCalling list with this list, should return a table {1,3,'-c',2}")
ok, args = pcall(ltcl.makearglist, tcl, {1,c=2,3})
ok, val = pcall(ltcl.callt, tcl, 'list', args)
if ok then
	check(cmptables(val, {1,3,'-c',2}))
else
	fail(tostring(val))
end

-- lua functions from tcl 1

-- tests registering lua functions with the interpreter, calling them, parameter, return values and error propagation

-- 51
announce("Registering a simple function with tcl, taking no arguments and returning nothing")
function lt1() end
check(pcall(ltcl.register, tcl, 'lt1', lt1))

-- 52
announce("Checking wether function has been registered")
check(type(getmetatable(tcl)['__functions']['lt1']) == 'function')

-- 53
announce("Calling said function through ltcl.eval, should return an empty string")
ok, val = pcall(ltcl.eval, tcl, 'lt1')
if ok then
	check(val == "")
else
	fail(tostring(val))
end

-- 54
announce("Calling said function through ltcl.call, should return an empty string")
ok, val = pcall(ltcl.call, tcl, 'lt1')
if ok then
	check(val == "")
else
	fail(tostring(val))
end

-- 55
announce("Registering a function with tcl returning its first argument")
function lt2(x) return x end
check(pcall(ltcl.register, tcl, 'lt2', lt2))

-- 56
announce("Calling said function through eval with argument 1, should return 1")
ok, val = pcall(ltcl.eval, tcl, 'lt2 1')
if ok then
	check(val == 1 or val == '1')
else
	fail(tostring(val))
end

-- 57
announce("Calling said function through eval with argument [expr 1], should return number 1")
ok, val = pcall(ltcl.eval, tcl, 'lt2 [expr 1]')
if ok then
	check(val == 1)
else
	fail(tostring(val))
end

-- 58
announce("Calling said function through eval with argument 'Hallo', should return string 'Hallo'")
ok, val = pcall(ltcl.eval, tcl, 'lt2 Hallo')
if ok then
	check(val == 'Hallo')
else
	fail(tostring(val))
end

-- 59
announce("Registering a function with tcl returning a list of its arguments")
function lt3(...) return {...} end
check(pcall(ltcl.register, tcl, 'lt3', lt3))

-- 60
announce("Calling said function through ltcl.eval with arguments 1,2,3, should return table {1,2,3}")
ok, val = pcall(ltcl.eval, tcl, 'lt3 1 2 3')
if ok then
	check(cmptables(val, {1,2,3}))
else
	fail(tostring(val))
end

-- 61
announce("Calling said function through ltcl.call with arguments 4,5,6, should return table {4,5,6}")
ok, val = pcall(ltcl.call, tcl, 'lt3', 4, 5, 6)
if ok then
	check(cmptables(val, {4,5,6}))
else
	fail(tostring(val))
end

-- 62
announce("Registering a function then calling it then unregistering it")
function lt4() return "X" end
ok = pcall(ltcl.register, tcl, 'lt4', lt4)
ok1, val = pcall(ltcl.call, tcl, 'lt4')
ok = ok and ok1 and val == "X"
check(ok and pcall(ltcl.unregister, tcl, 'lt4'))

-- 63
announce("Checking wether unregistered function has indeed been removed")
check(getmetatable(tcl)['__functions']['lt4'] == nil)

-- 64
announce("Trying to call unregistered function, should fail")
ok = pcall(ltcl.eval, tcl, 'lt4')
ok = ok or pcall(ltcl.call, tcl, 'lt4')
check(not ok)

-- lua functions from tcl 2

-- tests direct calling of lua functions from tcl.

-- 65
announce("Calling a lua function that compares its argument to number 1 with argument 1, should return 1")
function dt1(arg) return arg == 1 or arg == '1' end
ok, val = pcall(ltcl.eval, tcl, 'lua dt1 1')
if ok then
	check(val == 1)
else
	fail(tostring(val))
end

-- 66
announce("Calling a lua function that compares its argument to string 'Hallo' with argument 'Hallo', should return 1")
function dt2(arg) return arg == 'Hallo' end
ok, val = pcall(ltcl.eval, tcl, 'lua dt2 Hallo')
if ok then
	check(val == 1)
else
	fail(tostring(val))
end

-- 67
announce("Calling said function with a string 'Huhu', should return 0")
ok, val = pcall(ltcl.eval, tcl, 'lua dt2 Huhu')
if ok then
	check(val == 0)
else
	fail(tostring(val))
end

-- 68
announce("Calling a lua function that compares its argument to table {1,2,3} with argument [list 1 2 3], should return 1")
function dt3(arg) return cmptables(arg, {1,2,3}) end
ok, val = pcall(ltcl.eval, tcl, 'lua dt3 [list 1 2 3]')
if ok then
	check(val == 1)
else
	fail(tostring(val))
end

-- 69
announce("Calling a nonexistent lua function, should fail")
ok = pcall(ltcl.eval, tcl, 'lua dt4')
check(not ok)

-- 70
announce("Calling a lua function that returns all of its arguments with parameters 1 2 3, should return number 1")
function dt4(...) return ... end
ok, val = pcall(ltcl.eval, tcl, 'lua dt4 1 2 3')
if ok then
	check(val == 1 or val == '1')
else
	fail(tostring(val))
end

----- utf8 conversion stuff -----

-- very basic tests, just see wether it does anything at all just using ASCII
-- chars (which should convert to themselves), and see wether it fails when it should.

-- 71
announce("Converting string 'abc' to utf8, result should be a string 'abc'")
ok, val = pcall(ltcl.toutf8, tcl, 'abc')
if ok then
	check(val == 'abc')
else
	fail(tostring(val))
end

-- 72
announce("Converting that string 'abc' from utf8, result should be a string 'abc'")
ok, val = pcall(ltcl.fromutf8, tcl, val)
if ok then
	check(val == 'abc')
else
	fail(tostring(val))
end

-- 73
announce("Calling toutf8 with bogus encoding, should fail")
ok = pcall(ltcl.toutf8, tcl, 'x', 'bogusencoding')
check(not ok)

-- 74
announce("Calling fromutf8 with bogus encoding, should fail")
ok = pcall(ltcl.fromutf8, tcl, 'x', 'bogusencoding')
check(not ok)

----- vals tests -----

-- 75
announce("Calling list using callt with args {x=tcl:vals(1)}, should return a table {1}")
ok, val = pcall(ltcl.callt, tcl, 'list', {tcl:vals(1)})
if ok then
	check(cmptables(val, {1}))
else
	fail(tostring(val))
end

-- 76
announce("Calling list using callt with args {tcl:vals(1,2,3)}, should return a table {'-x',1,2,3}")
ok, val = pcall(ltcl.callt, tcl, 'list', {tcl:vals(1,2,3)})
if ok then
	check(cmptables(val, {1,2,3}))
else
	fail(tostring(val))
end

-- 77
announce("Making argument list from {x=tcl:vals(1,2,3),y=tcl:vals(4,5)} then Tcalling list with this list, should return a table {'-x',1,2,3,'-y',4,5} or {'-y',4,5,'-x',1,2,3}")
ok, args = pcall(ltcl.makearglist, tcl, {x=tcl:vals(1,2,3),y=tcl:vals(4,5)})
ok, val = pcall(ltcl.callt, tcl, 'list', args)
if ok then
	check(cmptables(val, {'-x',1,2,3,'-y',4,5}) or cmptables(val, {'-y',4,5,'-x',1,2,3}))
else
	fail(tostring(val))
end

----- checkflags tests -----

-- 78
announce("Setting flags to 1+2+8+32+64+256, checking against 1,2,4,6,32,33, should return 1,2,nil,nil,32,33")
flags = 1+2+8+32+64+256
ok, a,b,c,d,e,f = pcall(ltcl.checkflags, tcl, flags, 1,2,4,6,32,33)
if ok then
	check((a==1) and (b==2) and (c==nil) and (d==nil) and (e==32) and (f==33))
else
	fail(tostring(a))
end

-- 79
announce("Checking flags against 'bla', should fail")
ok = pcall(ltcl.checkflags, tcl, flags, 'bla')
check(not ok)

-- 80
announce("Checking 'bla' against 1,2,4, should fail")
ok = pcall(ltcl.checkflags, tcl, 'bla', 1,2,4)
check(not ok)

----- tracevar tests -----

-- 81
announce("Setting write trace on tcl var tracea, then setting tracea to 42. Should call trace func with a, nil, and at least ltcl.TRACE_WRITES")
trace_ok =false
function tracevara(n1, n2, flags)
	local ok, val = pcall(ltcl.checkflags, tcl, flags, ltcl.TRACE_WRITES)
	if ok and val and n1 == 'tracea' and n2==nil then
		ok, val = pcall(ltcl.getvar, tcl, 'tracea')
		trace_ok = (val == 42)
	end
	if not ok then
		return tostring(val)
	end
end
ok, msg = pcall(ltcl.tracevar, tcl, 'tracea', nil, ltcl.TRACE_WRITES, tracevara)
if ok then
	ok, msg = pcall(ltcl.setvar, tcl, 'tracea', 42)
end
if ok then
	check(trace_ok)
else
	fail(tostring(msg))
end

-- 82
announce("Now unsetting said variable, trace should still be there and behave as before")
ok, msg = pcall(ltcl.unsetvar, tcl, 'tracea')
collectgarbage()
if ok then
	ok, msg = pcall(ltcl.tracevar, tcl, 'tracea', nil, ltcl.TRACE_WRITES, tracevara)
end
if ok then
	ok, msg = pcall(ltcl.setvar, tcl, 'tracea', 42)
end
if ok then
	check(trace_ok)
else
	fail(tostring(msg))
end

-- 83
announce("Setting write trace on tcl var tracea (which is 42), that changes tracea to 17 before reading. Should call trace func with a, nil, and at least ltcl.TRACE_READS, and getvar should return 17")
trace_ok = false
function tracevara2(n1, n2, flags)
	local ok, val = pcall(ltcl.checkflags, tcl, flags, ltcl.TRACE_READS)
	if ok and val and n1 == 'tracea' and n2==nil then
		ok, val = pcall(ltcl.setvar, tcl, 'tracea', 17)
		trace_ok = ok
	end
	if not ok then
		return tostring(val)
	end
end
ok, msg = pcall(ltcl.tracevar, tcl, 'tracea', nil, ltcl.TRACE_READS, tracevara2)
if ok then
	ok, msg = pcall(ltcl.getvar, tcl, 'tracea')
end
if ok then
	check(trace_ok and msg==17)
else
	fail(tostring(msg))
end

-- all done
print("Tests " .. tostring(ntests) .. " failed " .. tostring(nfailed))
