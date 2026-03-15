local enet     = require "enet"
local Lockstep = {}

---@class LockstepState
---@field host         any            enet host
---@field server       any            enet peer (the relay)
---@field myIndex      integer        which player we are (1-based)
---@field frame        integer        current frame number (incremented by main.lua each tick)
---@field inputBuffer   table           frame number → player index → input table
---@field inputDelay    integer        how many frames of input to buffer before starting simulation
---@field lastSentFrame integer        the latest frame number we've sent input for (used to guard against sending multiple times per frame when catching up)
---@field numPlayers    integer        total number of players in this game (used to check readiness)

--- Connects to the relay and waits until we receive our player index.
--- Blocks in a tight loop — only call this from love.load().
---@param relayHost string
---@param port      integer
---@param numPlayers integer
---@param inputDelay integer   how many frames of input to buffer before starting simulation
---@return LockstepState
function Lockstep.connect(relayHost, port, numPlayers, inputDelay)
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

    -- Wait for the relay's "go" signal (0xFE) — sent once all players are connected.
    -- This ensures every client starts from frame 0 at the same moment.
    print("[lockstep] Waiting for all players...")
    local ready = false
    while not ready do
        local event = host:service(100)
        if event and event.type == "receive" then
            if string.byte(event.data, 1) == 0xFE then
                ready = true
                print("[lockstep] Go! Starting from frame 0.")
            end
        end
    end

    return {
        host        = host,
        server      = server,
        myIndex     = myIndex,
        numPlayers  = numPlayers,
        inputDelay  = inputDelay,
        frame       = 0,
        inputBuffer = {},
    }
end

-- Packet layout (6 bytes, LuaJIT-compatible — no string.pack):
--   [1] playerIndex  uint8
--   [2] frame high   uint8  high byte of uint16
--   [3] frame low    uint8  low byte of uint16
--   [4] buttons      uint8  bit0=up bit1=dn bit2=lt bit3=rt bit4=fire
--   [5] angle high   uint8  high byte of uint16
--   [6] angle low    uint8  low byte of uint16
--
-- aimAngle [-pi, pi] is mapped to [0, 65535] and split across bytes 5-6.
---Ready the input to be sent across the network
---@param playerIndex integer
---@param frame integer
---@param inp table   raw input for our player (up/dn/lt/rt/fire/aimAngle)
---@return string
local function packInput(playerIndex, frame, inp)
    local buttons = 0
    if inp.up then buttons = buttons + 1 end
    if inp.dn then buttons = buttons + 2 end
    if inp.lt then buttons = buttons + 4 end
    if inp.rt then buttons = buttons + 8 end
    if inp.fire then buttons = buttons + 16 end

    local f = frame % 65536
    local a = math.floor(((inp.aimAngle + math.pi) / (2 * math.pi)) * 65535 + 0.5) % 65536

    return string.char(
        playerIndex,
        math.floor(f / 256), f % 256,
        buttons,
        math.floor(a / 256), a % 256
    )
end

--- Send this frame's local input to the relay.
--- The relay will broadcast it to all other clients.
---@param ls  LockstepState
---@param inp table   raw input for our player (up/dn/lt/rt/fire/aimAngle)
function Lockstep.send(ls, inp)
    local targetFrame = ls.frame + ls.inputDelay

    -- Guard: the tick loop can run multiple times per love.update when catching up.
    -- Only send once per target frame.
    if ls.lastSentFrame and ls.lastSentFrame >= targetFrame then return end
    ls.lastSentFrame                        = targetFrame

    ls.inputBuffer[targetFrame]             = ls.inputBuffer[targetFrame] or {}
    ls.inputBuffer[targetFrame][ls.myIndex] = inp

    ls.server:send(packInput(ls.myIndex, targetFrame, inp))
    ls.host:flush()
end

---Unpacks the data received from the relay into playerIndex, frame, and input table.
---@param data string
---@return integer
---@return integer
---@return table
local function unpackInput(data)
    local playerIndex = string.byte(data, 1)
    local frameHi     = string.byte(data, 2)
    local frameLo     = string.byte(data, 3)
    local buttons     = string.byte(data, 4)
    local angleHi     = string.byte(data, 5)
    local angleLo     = string.byte(data, 6)

    local frame       = frameHi * 256 + frameLo
    local angle       = angleHi * 256 + angleLo

    return playerIndex, frame, {
        up       = buttons % 2 >= 1,
        dn       = math.floor(buttons / 2) % 2 >= 1,
        lt       = math.floor(buttons / 4) % 2 >= 1,
        rt       = math.floor(buttons / 8) % 2 >= 1,
        fire     = math.floor(buttons / 16) % 2 >= 1,
        aimAngle = (angle / 65535) * (2 * math.pi) - math.pi,
    }
end

--- Drain all pending packets from the relay and store the latest input per player.
--- Call this once per love.update, before the fixed-tick loop.
---@param ls LockstepState
function Lockstep.receive(ls)
    local event = ls.host:service(0)
    while event do
        if event.type == "receive" then
            local playerIndex, frame, inp      = unpackInput(event.data)
            ls.inputBuffer[frame]              = ls.inputBuffer[frame] or {}
            ls.inputBuffer[frame][playerIndex] = inp
        elseif event.type == "disconnect" then
            print("[lockstep] Disconnected from relay")
        end
        event = ls.host:service(0)
    end
end

--- Returns true when all numPlayers inputs for ls.frame have arrived.
--- Pure: reads state, changes nothing.
---@param ls         LockstepState
---@return boolean
function Lockstep.ready(ls)
    local bucket = ls.inputBuffer[ls.frame]
    if not bucket then return false end
    for i = 1, ls.numPlayers do
        if not bucket[i] then return false end
    end
    return true
end

--- Consume inputs for ls.frame and advance the frame counter.
--- Only call after ready() returns true.
---@param ls LockstepState
---@return table  frameInputs[playerIndex] = inp
function Lockstep.consume(ls)
    local inputs = ls.inputBuffer[ls.frame]
    ls.inputBuffer[ls.frame] = nil -- free memory
    ls.frame = ls.frame + 1
    return inputs
end

--- Call once right after connect() returns.
--- Fills neutral inputs for ALL players for frames 0..(inputDelay-1) locally.
--- No packets sent — every client runs the same code so they all agree.
---@param ls LockstepState
function Lockstep.bootstrap(ls)
    local neutral = { up = false, dn = false, lt = false, rt = false, fire = false, aimAngle = 0 }
    for f = 0, ls.inputDelay - 1 do
        ls.inputBuffer[f] = {}
        for p = 1, ls.numPlayers do
            ls.inputBuffer[f][p] = neutral
        end
    end
    -- Tell the send guard frames 0..inputDelay-1 are already handled.
    ls.lastSentFrame = ls.inputDelay - 1
end

return Lockstep
