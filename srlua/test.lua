-- test srlua

print("hello from inside "..arg[0])
print(...)
print"bye!"

print("hello again from inside "..arg[0])
for i=0,#arg do
	print(i,arg[i])
end
print"bye!"
