-- lockstep.lua — phase 1: connection only.
-- Connects to the relay and blocks until a player index is assigned.
-- No input sending, no frame buffering, no ready checks yet.

local enet     = require "enet"
local Lockstep = {}

---@class LockstepState
---@field host    any     enet host
---@field server  any     enet peer (the relay)
---@field myIndex integer which player we are (1-based)

--- Connects to the relay and waits until we receive our player index.
--- Blocks in a tight loop — only call this from love.load().
---@param relayHost string
---@param port      integer
---@return LockstepState
function Lockstep.connect(relayHost, port)
    local host    = enet.host_create()
    local server  = host:connect(relayHost .. ":" .. port)

    local myIndex = nil
    print("[lockstep] Connecting to " .. relayHost .. ":" .. port .. " ...")

    while not myIndex do
        local event = host:service(100) -- block up to 100 ms per iteration
        if event then
            if event.type == "connect" then
                print("[lockstep] TCP handshake done, waiting for index assignment...")
            elseif event.type == "receive" then
                -- Relay sends exactly 2 bytes: [0xFF][playerIndex]
                local msgType = string.byte(event.data, 1)
                if msgType == 0xFF then
                    myIndex = string.byte(event.data, 2)
                    print("[lockstep] Assigned player index: " .. myIndex)
                end
            elseif event.type == "disconnect" then
                error("[lockstep] Disconnected from relay before receiving player index")
            end
        end
    end

    return {
        host    = host,
        server  = server,
        myIndex = myIndex,
    }
end

return Lockstep
