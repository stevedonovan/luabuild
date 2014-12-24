@echo off
rem do we already have lake?
for %%X in (lake.exe) do (
   set LAKE=%%~$PATH:X
   if defined LAKE goto :lake
)
:outf
for %%X in (lua.exe,lua51.exe,luajit.exe) do (
  set LUA="%%~$PATH:X"
  if defined LUA goto :lua
)
echo no lua available...get lake.exe!!
exit /b
:lua
%LUA% -llfs -e "print 'OK!'"  2>&1 | find "OK!" > nul
if %errorlevel% neq 0  (
    echo luafilesystem not installed for %LUA%
    exit /b
)
set LAKE=%LUA% lake
goto :go
:lake
rem if it's a batch needs special treatment
echo %LAKE% | find ".bat"
set LAKE="%LAKE%"
if %errorlevel% equ 0 set LAKE=call %LAKE%
:go
rem and go!
if "%1" == "LUA53=1" (set LAKE=%LAKE% LUA53=1)
if defined LUA53 (set LAKE=%LAKE% LUA53=1)
%LAKE% %*
rem can now install the rest
if %errorlevel% equ 0 (
  echo installing...
  %LAKE% install.lua
)
