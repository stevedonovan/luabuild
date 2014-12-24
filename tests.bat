@echo off
rem see if we can wrap Lake successfully as an exe
call srlua -m "lfs winapi" -o flake lake
flake -h
set L53=
if defined LUA53 (set L53="LUA53=1")
lake %L53% -f test.lake
