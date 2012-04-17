#!/usr/bin/env lua5.1

-- $Id: teststruct.lua,v 1.2 2008/04/18 20:06:01 roberto Exp $

-- load library
local lib = require"struct"
--assert(_G.struct == lib)


--
-- auxiliar function to print an hexadecimal `dump' of a given string
-- (not used by the test)
--
local function bp (s)
  s = string.gsub(s, "(.)", function(c)
        return string.format("\\%02x", string.byte(c))
      end)
  print(s)
end


local a,b,c,d,e,f,x

assert(#lib.pack("I", 67324752) == 4)

assert(lib.pack('b', 10) == string.char(10))
assert(lib.pack('bbb', 10, 20, 30) == string.char(10, 20, 30))

assert(lib.pack('<h', 10) == string.char(10, 0))
assert(lib.pack('>h', 10) == string.char(0, 10))
assert(lib.pack('<h', -10) == string.char(256-10, 256-1))

assert(lib.pack('<l', 10) == string.char(10, 0, 0, 0))
assert(lib.pack('>l', 10) == string.char(0, 0, 0, 10))
assert(lib.pack('<l', -10) == string.char(256-10, 256-1, 256-1, 256-1))

assert(lib.unpack('<h', string.char(10, 0)) == 10)
assert(lib.unpack('>h', string.char(0, 10)) == 10)
assert(lib.unpack('<h', string.char(256-10, 256-1)) == -10)

assert(lib.unpack('<l', string.char(10, 0, 0, 1)) == 10 + 2^(3*8))
assert(lib.unpack('>l', string.char(0, 1, 0, 10)) == 10 + 2^(2*8))
assert(lib.unpack('<l', string.char(256-10, 256-1, 256-1, 256-1)) == -10)

-- limits
lims = {{'B', 255}, {'b', 127}, {'b', -128},
        {'I1', 255}, {'i1', 127}, {'i1', -128},
        {'H', 2^16 - 1}, {'h', 2^15 - 1}, {'h', -2^15},
        {'I2', 2^16 - 1}, {'i2', 2^15 - 1}, {'i2', -2^15},
        {'L', 2^32 - 1}, {'l', 2^31 - 1}, {'l', -2^31},
        {'I4', 2^32 - 1}, {'i4', 2^31 - 1}, {'i4', -2^31},
       }

for _, a in pairs{'', '>', '<'} do
  for _, l in pairs(lims) do
    local fmt = a .. l[1]
    assert(lib.unpack(fmt, lib.pack(fmt, l[2])) == l[2])
  end
end


-- tests for fixed-sized ints
for _, i in pairs{1,2,4} do
  x = lib.pack('<i'..i, -3)
  assert(string.len(x) == i)
  assert(x == string.char(256-3) .. string.rep(string.char(256-1), i-1))
  assert(lib.unpack('<i'..i, x) == -3)
end


-- alignment
d = lib.pack("d", 5.1)
ali = {[1] = string.char(1)..d,
       [2] = string.char(1, 0)..d,
       [4] = string.char(1, 0, 0, 0)..d,
       [8] = string.char(1, 0, 0, 0, 0, 0, 0, 0)..d,
      }

for a,r in pairs(ali) do
  assert(lib.pack("!"..a.."bd", 1, 5.1) == r)
  local x,y = lib.unpack("!"..a.."bd", r)
  assert(x == 1 and y == 5.1)
end


print('+')


-- strings
assert(lib.pack("c", "alo alo") == "a")
assert(lib.pack("c4", "alo alo") == "alo ")
assert(lib.pack("c5", "alo alo") == "alo a")
assert(lib.pack("!4b>c7", 1, "alo alo") == "\1alo alo")
assert(lib.pack("!2<s", "alo alo") == "alo alo\0")
assert(lib.pack(" c0 ", "alo alo") == "alo alo")
for _, f in pairs{"B", "l", "i2", "f", "d"} do
  for _, s in pairs{"", "a", "alo", string.rep("x", 200)} do
    local x = lib.pack(f.."c0", #s, s)
    assert(lib.unpack(f.."c0", x) == s)
  end
end

-- indices
x = lib.pack("!>iiiii", 1, 2, 3, 4, 5)
local i = 1
local k = 1
while i < #x do
  local v, j = lib.unpack("!>i", x, i)
  assert(j == i + 4 and v == k)
  i = j; k = k + 1
end

-- alignments are relative to 'absolute' positions
x = lib.pack("!8 xd", 12)
assert(lib.unpack("!8d", x, 3) == 12)


assert(lib.pack("<lhbxxH", -2, 10, -10, 250) ==
  string.char(254, 255, 255, 255, 10, 0, 246, 0, 0, 250, 0))

a,b,c,d = lib.unpack("<lhbxxH",
  string.char(254, 255, 255, 255, 10, 0, 246, 0, 0, 250, 0))
assert(a == -2 and b == 10 and c == -10 and d == 250)

assert(lib.pack(">lBxxH", -20, 10, 250) ==
                string.char(255, 255, 255, 236, 10, 0, 0, 0, 250))

a, b, c, d = lib.unpack(">lBxxH",
                 string.char(255, 255, 255, 236, 10, 0, 0, 0, 250))
assert(a == -20 and b == 10 and c == 250 and d == 10)

a,b,c,d,e = lib.unpack(">fdfH",
                  '000'..lib.pack(">fdfH", 3.5, -24e-5, 200.5, 30000),
                  4)
assert(a == 3.5 and b == -24e-5 and c == 200.5 and d == 30000 and e == 22)

a,b,c,d,e = lib.unpack("<fdxxfH",
                  '000'..lib.pack("<fdxxfH", -13.5, 24e5, 200.5, 300),
                  4)
assert(a == -13.5 and b == 24e5 and c == 200.5 and d == 300 and e == 24)

x = lib.pack(">I2fi4I2", 10, 20, -30, 40001)
assert(string.len(x) == 2+4+4+2)
assert(lib.unpack(">f", x, 3) == 20)
a,b,c,d = lib.unpack(">i2fi4I2", x)
assert(a == 10 and b == 20 and c == -30 and d == 40001)

local s = "hello hello"
x = lib.pack(" b c0 ", string.len(s), s)
assert(lib.unpack("bc0", x) == s)
x = lib.pack("Lc0", string.len(s), s)
assert(lib.unpack("  L  c0   ", x) == s)
x = lib.pack("cc3b", s, s, 0)
assert(x == "hhel\0")
assert(lib.unpack("xxxxb", x) == 0)

assert(lib.pack("<!l", 3) == string.char(3, 0, 0, 0))
assert(lib.pack("<!xl", 3) == string.char(0, 0, 0, 0, 3, 0, 0, 0))
assert(lib.pack("<!xxl", 3) == string.char(0, 0, 0, 0, 3, 0, 0, 0))
assert(lib.pack("<!xxxl", 3) == string.char(0, 0, 0, 0, 3, 0, 0, 0))

assert(lib.unpack("<!l", string.char(3, 0, 0, 0)) == 3)
assert(lib.unpack("<!xl", string.char(0, 0, 0, 0, 3, 0, 0, 0)) == 3)
assert(lib.unpack("<!xxl", string.char(0, 0, 0, 0, 3, 0, 0, 0)) == 3)
assert(lib.unpack("<!xxxl", string.char(0, 0, 0, 0, 3, 0, 0, 0)) == 3)

assert(lib.pack("<!2 b l h", 2, 3, 5) == string.char(2, 0, 3, 0, 0, 0, 5, 0))
a,b,c = lib.unpack("<!2blh", string.char(2, 0, 3, 0, 0, 0, 5, 0))
assert(a == 2 and b == 3 and c == 5)

assert(lib.pack("<!8blh", 2, 3, 5) == string.char(2, 0, 0, 0, 3, 0, 0, 0, 5, 0))
a,b,c = lib.unpack("<!8blh", string.char(2, 0, 0, 0, 3, 0, 0, 0, 5, 0))
assert(a == 2 and b == 3 and c == 5)

assert(lib.pack(">sh", "aloi", 3) == "aloi\0\0\3")
assert(lib.pack(">!sh", "aloi", 3) == "aloi\0\0\0\3")
x = "aloi\0\0\0\0\3\2\0\0"
a, b, c = lib.unpack("<!si4", x)
assert(a == "aloi" and b == 2*256+3 and c == string.len(x)+1)

x = lib.pack("!4sss", "hi", "hello", "bye")
a,b,c = lib.unpack("sss", x)
assert(a == "hi" and b == "hello" and c == "bye")
a, i = lib.unpack("s", x, 1)
assert(a == "hi")
a, i = lib.unpack("s", x, i)
assert(a == "hello")
a, i = lib.unpack("s", x, i)
assert(a == "bye")



-- test for weird conditions
assert(lib.pack(">>>h <!!!<h", 10, 10) == string.char(0, 10, 10, 0))
assert(not pcall(lib.pack, "!3l", 10))
assert(not pcall(lib.pack, "3", 10))
assert(not pcall(lib.pack, "i3", 10))
assert(not pcall(lib.pack, "I3", 10))
assert(lib.pack("") == "")
assert(lib.pack("   ") == "")
assert(lib.pack(">>><<<!!") == "")
assert(not pcall(lib.unpack, "c0", "alo"))
assert(not pcall(lib.unpack, "s", "alo"))
assert(lib.unpack("s", "alo\0") == "alo")
assert(not pcall(lib.pack, "c4", "alo"))
assert(pcall(lib.pack, "c3", "alo"))
assert(not pcall(lib.unpack, "c4", "alo"))
assert(pcall(lib.unpack, "c3", "alo"))
assert(not pcall(lib.unpack, "bc0", "\4alo"))
assert(pcall(lib.unpack, "bc0", "\3alo"))

assert(not pcall(lib.unpack, "b", "alo", 4))
assert(lib.unpack("b", "alo\3", 4) == 3)

print'OK'
