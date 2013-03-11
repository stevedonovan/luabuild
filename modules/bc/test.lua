-- test bc library

local bc=require"bc"

------------------------------------------------------------------------------
print(bc.version)

------------------------------------------------------------------------------
print""
print"Pi algorithm of order 4"

bc.digits(65)
PI="3.1415926535897932384626433832795028841971693993751058209749445923078164062862090"
pi=bc.number(PI)

-- http://pauillac.inria.fr/algo/bsolve/constant/pi/pi.html
function A2()
 local x=bc.sqrt(2)
 local p=2+x
 local y=bc.sqrt(x)
 print(-1,p)
 x=(y+1/y)/2
 p=p*(x+1)/(y+1)
 print(0,p)
 for i=1,20 do
  local P=p
  local t=bc.sqrt(x)
  y=(y*t+1/t)/(y+1)
  x=(t+1/t)/2
  p=p*(x+1)/(y+1)
  print(i,p)
  if p==P then break end
 end
 return p
end

function bc.abs(x) if bc.isneg(x) then return -x else return x end end

p=A2()
print("exact",pi)
print("-",bc.abs(pi-p))

------------------------------------------------------------------------------
print""
print"Square root of 2"

function mysqrt(x)
 local y,z=x,x
 repeat z,y=y,(y+x/y)/2 until z==y
 return y
end

print("f math",math.sqrt(2))
print("f mine",mysqrt(2))
a=bc.sqrt(2) print("B sqrt",a)
b=mysqrt(bc.number(2)) print("B mine",b)
R=bc.number"1.414213562373095048801688724209698078569671875376948073176679737990732478462107038850387534327641573"
print("exact",R)
print(a==b,a<b,a>b,bc.compare(a,b))

------------------------------------------------------------------------------
print""
print"Fibonacci numbers as digits in fraction"

x=99989999
bc.digits(68)
a=bc.div(1,x)
s=bc.tostring(a)
print("1/"..x.." =")
print("",s)
s=string.gsub(s,"0(%d%d%d)"," %1")
print("",s)

------------------------------------------------------------------------------
print""
print"Factorials"

function factorial(n,f)
 for i=2,n do f=f*i end
 return f
end

one=bc.number(1)
for i=1,30 do
  local f=factorial(i,1)
  local b=factorial(i,one)
 --print(i,factorial(i,1),factorial(i,one))
   f=string.format("%.0f",f)
 --print(i,bc.number(f)==b,string.format("%.0f",f),b)
 print(i,bc.number(f)==b,f,b)
end

------------------------------------------------------------------------------
print""
print"Comparisons"

bc.digits(4)
a=bc.div(4,2)
b=bc.number(1)
print("a","b","a==b","a<b","a>b","bc.compare(a,b)")
print(a,b,a==b,a<b,a>b,bc.compare(a,b))
b=b+1
print(a,b,a==b,a<b,a>b,bc.compare(a,b))
b=b+1
print(a,b,a==b,a<b,a>b,bc.compare(a,b))

------------------------------------------------------------------------------
print""
print"Modulo"

A=20.2
B=7.48
a=bc.number(A)
b=bc.number(B)
print("mod",bc.mod(a,b))
print("MOD",bc.mod(A,B))
print("def",a-bc.trunc(a/b)*b)
print("oper",a%b)
print("real",A%B)

------------------------------------------------------------------------------
print""
print"Trunc"
print(n,bc.trunc(pi,n))
for n=0,10 do
	local t=bc.trunc(pi,n)
	print(n,t,bc.tostring(t)==string.sub(PI,1,n+2))
end

------------------------------------------------------------------------------
print""
print("RSA")
bc.digits(0)

function string2bc(s)
       local x=bc.number(0)
       for i=1,#s do
               x=256*x+s:byte(i)
       end
       return x
end

function bc2string(x)
	if x:iszero() then
		return ""
	else
		local r
		x,r=bc.divmod(x,256)
		return bc2string(x)..string.char(r:tonumber())
       end
end

function hex2bc(s)
	local x=bc.number(0)
	for i=1,#s do
		x=16*x+tonumber(s:sub(i,i),16)
	end
	return x
end

public="10001"
private="816f0d36f0874f9f2a78acf5643acda3b59b9bcda66775b7720f57d8e9015536160e728230ac529a6a3c935774ee0a2d8061ea3b11c63eed69c9f791c1f8f5145cecc722a220d2bc7516b6d05cbaf38d2ab473a3f07b82ec3fd4d04248d914626d2840b1bd337db3a5195e05828c9abf8de8da4702a7faa0e54955c3a01bf121"
modulus="bfedeb9c79e1c6e425472a827baa66c1e89572bbfe91e84da94285ffd4c7972e1b9be3da762444516bb37573196e4bef082e5a664790a764dd546e0d167bde1856e9ce6b9dc9801e4713e3c8cb2f12459788a02d2e51ef37121a0f7b086784f0e35e76980403041c3e5e98dfa43ab9e6e85558c5dc00501b2f2a2959a11db21f"

d=hex2bc(public)
	print("public key")
	print(d)
e=hex2bc(private)
	print("private key")
	print(e)
n=hex2bc(modulus)
	print("modulus")
	print(n)

message="The quick brown fox jumps over the lazy dog"
	print("message as text")
	print(message)

m=string2bc(message)
	print("encoded message")
	print(m)
	assert(m<n)
	assert(message==bc2string(m))

	print("encrypted message")
x=bc.powmod(m,e,n)
	print(x)

	print("decrypted message")
y=bc.powmod(x,d,n)
	print(y)
	assert(y==m)
y=bc2string(y)
	print("decrypted message as text")
	print(y)
	assert(y==message)

--print"" print("trimmed",bc.trim())
------------------------------------------------------------------------------

print""
print(bc.version)

-- eof
