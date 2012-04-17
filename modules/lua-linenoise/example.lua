local L = require 'linenoise'
-- L.clearscreen()
print '----- Testing lua-linenoise! ------'
local prompt, history = '? ', 'history.txt'
L.historyload(history) -- load existing history
L.setcompletion(function(c,s)
   if s == 'h' then
    L.addcompletion(c,'help')
    L.addcompletion(c,'halt')
  end
end)
local line = L.linenoise(prompt)
while line do
    if #line > 0 then
        print(line:upper())
        L.historyadd(line)
        L.historysave(history) -- save every new line
    end
    line = L.linenoise(prompt)
end

