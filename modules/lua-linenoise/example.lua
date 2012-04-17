local L = require 'linenoise'
local line = L.linenoise '? '
while line do
   print(line:upper())
   L.historyadd(line)
   line = L.linenoise '? '
end
