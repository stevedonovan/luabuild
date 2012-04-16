-- renumber test comments in ltcltest.lua

testno = false
for s in io.lines() do
	m = string.match(s, '^-- (%d+)$')
	if m then
		if not testno then
			testno = m * 1
		else
			testno = testno + 1
		end
		print("-- "..tostring(testno))
	else
		print(s)
	end
end
