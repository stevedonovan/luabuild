local sql = require 'luasql.odbc'
local env = sql.odbc()
local con = env:connect 'AURA'
local cur = con:execute 'SELECT EventID FROM [Event Summaries]'
local row = cur:fetch({},'a')
while row do
    print(row.EventID)
    row = cur:fetch(row,'a')
end
cur:close()
con:close()
env:close()
