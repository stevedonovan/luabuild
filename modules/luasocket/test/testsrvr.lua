socket = require("socket")
host = host or "127.0.0.1"
port = port or "8443"
server = assert(socket.bind(host, port))
loadstring = loadstring or load -- Lua 5.2 compat
ack = "\n";
while 1 do
    print("server: waiting for client connection...");
    control = assert(server:accept());
    while 1 do
        command, emsg = control:receive();
        if emsg == "closed" then
            control:close()
            break
        end
        if command == 'quit' then
            control:close()
            print 'shutting down server'
            return
        end
        assert(command, emsg)
        assert(control:send(ack));
        print(command);
        (loadstring(command))();
    end
end
