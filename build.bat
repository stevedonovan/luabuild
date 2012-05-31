@echo off
rem do we already have lake?
for %%X in (lake.exe,lake.bat) do (
   set LAKE=%%~$PATH:X
   if defined LAKE goto :lake
)
:outf
for %%X in (lua.exe,lua51.exe) do (
  set LUA=%%~$PATH:X
  if defined LUA goto :outl
)
:outl	
if defined LUA ( 
     set LAKE="%LUA%" lake
) else (
     echo no lua available...get lake.exe!!
     exit /b
)
goto :go
:lake
rem if it's a batch needs special treatment
echo %LAKE% | find ".bat"
set LAKE="%LAKE%"
if %errorlevel% equ 0 set LAKE=call %LAKE%
:go
rem and go!
%LAKE%
rem can now install the rest
if %errorlevel% equ 0 (
  echo installing...
  %LAKE% install.lua
)
