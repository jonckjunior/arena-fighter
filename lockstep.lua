-- lockstep.lua — phase 2: connection + input sending.
-- Connects to the relay, receives a player index, and can send local input each tick.
-- No receiving remote input, no frame buffering, no gating yet.

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
        local event = host:service(100)
        if event then
            if event.type == "connect" then
                print("[lockstep] Connected, waiting for index assignment...")
            elseif event.type == "receive" then
                local msgType = string.byte(event.data, 1)
                if msgType == 0xFF then
                    myIndex = string.byte(event.data, 2)
                    print("[lockstep] Assigned player index: " .. myIndex)
                end
            elseif event.type == "disconnect" then
                error("[lockstep] Disconnected before receiving player index")
            end
        end
    end

    return {
        host    = host,
        server  = server,
        myIndex = myIndex,
    }
end

-- Packet layout (4 bytes, LuaJIT-compatible — no string.pack):
--   [1] playerIndex  uint8
--   [2] buttons      uint8  bit0=up bit1=dn bit2=lt bit3=rt bit4=fire
--   [3] angle high   uint8  high byte of uint16
--   [4] angle low    uint8  low byte of uint16
--
-- aimAngle [-pi, pi] is mapped to [0, 65535] and split across bytes 3-4.

local function packInput(playerIndex, inp)
    local buttons = 0
    if inp.up then buttons = buttons + 1 end
    if inp.dn then buttons = buttons + 2 end
    if inp.lt then buttons = buttons + 4 end
    if inp.rt then buttons = buttons + 8 end
    if inp.fire then buttons = buttons + 16 end

    local angle = math.floor(((inp.aimAngle + math.pi) / (2 * math.pi)) * 65535 + 0.5) % 65536
    local hi    = math.floor(angle / 256)
    local lo    = angle % 256

    return string.char(playerIndex, buttons, hi, lo)
end

--- Send this frame's local input to the relay.
--- The relay will broadcast it to all other clients.
---@param ls  LockstepState
---@param inp table   raw input for our player (up/dn/lt/rt/fire/aimAngle)
function Lockstep.send(ls, inp)
    ls.server:send(packInput(ls.myIndex, inp))
    ls.host:flush()
end

return Lockstep
