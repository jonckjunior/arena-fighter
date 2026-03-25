local World        = require "world"
local C            = require "components"
local Utils        = require "utils"

---@class SystemsInput
local SystemsInput = {}
local atan2        = math.atan2 or function(y, x) return math.atan(y / x) end

local function getPlayerGun(w, playerId)
    local guns = World.query(w, C.Name.equippedBy, C.Name.position, C.Name.animation)
    return Utils.find(guns, function(id)
        return w.equippedBy[id].ownerId == playerId
    end)
end

---Captures raw local device input for one player before any world-aware mapping.
---@param playerIndex integer
---@param USE_NETWORK boolean
---@param keysPressed RawInput
---@return table
function SystemsInput.captureLocalInput(playerIndex, USE_NETWORK, keysPressed)
    if playerIndex == 1 or USE_NETWORK then
        return {
            up       = keysPressed["w"],
            dn       = keysPressed["s"],
            lt       = keysPressed["a"],
            rt       = keysPressed["d"],
            fire     = keysPressed["leftMouse"],
            reload   = keysPressed["r"],
            aimAngle = 0,
        }
    end

    return {
        up       = keysPressed["u"],
        dn       = keysPressed["j"],
        lt       = keysPressed["h"],
        rt       = keysPressed["k"],
        fire     = keysPressed["space"],
        reload   = keysPressed["r"],
        aimAngle = 0,
    }
end

---Resolves a player's aim angle against an explicit world-space target.
---@param playerIndex integer
---@param w World
---@param targetX number
---@param targetY number
---@param fallbackAngle number|nil
---@return number
function SystemsInput.resolveAimAngle(playerIndex, w, targetX, targetY, fallbackAngle)
    local players = World.query(w, C.Name.playerIndex, C.Name.position, C.Name.input)
    local pid     = Utils.find(players, function(id)
        return w.playerIndex[id].index == playerIndex
    end)
    if not pid then return fallbackAngle or 0 end

    local gunId = getPlayerGun(w, pid)
    if not gunId then return fallbackAngle or 0 end

    local px, py = w.position[gunId].x, w.position[gunId].y
    local dx, dy = targetX - px, targetY - py
    if dx * dx + dy * dy > 5 * 5 then
        return atan2(dy, dx)
    end
    return w.input[pid].aimAngle or fallbackAngle or 0
end

---Maps raw local input into gameplay-ready input using world state.
--- The aim target is provided explicitly rather than being read from a cursor.
---@param playerIndex integer
---@param w World
---@param mx number
---@param my number
---@param rawInput table
---@return table
function SystemsInput.mapLocalInput(playerIndex, w, mx, my, rawInput)
    return {
        up = rawInput.up,
        dn = rawInput.dn,
        lt = rawInput.lt,
        rt = rawInput.rt,
        fire = rawInput.fire,
        reload = rawInput.reload,
        aimAngle = SystemsInput.resolveAimAngle(playerIndex, w, mx, my, rawInput.aimAngle),
    }
end

---Returns gameplay-ready input for one local player by composing:
--- 1. raw device capture
--- 2. world-aware input mapping
---@param playerIndex integer
---@param w World
---@param mx number
---@param my number
---@param USE_NETWORK boolean
---@param keysPressed RawInput
---@return table
function SystemsInput.gatherLocalInput(playerIndex, w, mx, my, USE_NETWORK, keysPressed)
    local rawInput = SystemsInput.captureLocalInput(playerIndex, USE_NETWORK, keysPressed)
    return SystemsInput.mapLocalInput(playerIndex, w, mx, my, rawInput)
end

---Copies frame inputs into each player's input component and prepends a
--- raw snapshot to their inputHistory ring buffer.
--- History index 1 is always the most recent frame.
---@param w World
---@param frameInputs table
function SystemsInput.applyInputs(w, frameInputs)
    for _, id in ipairs(World.query(w, C.Name.playerIndex)) do
        local pidx = w.playerIndex[id]
        local inp  = frameInputs[pidx.index]
        if not (inp and w.input[id]) then goto continue end

        -- Update live input state
        w.input[id].up       = inp.up
        w.input[id].dn       = inp.dn
        w.input[id].lt       = inp.lt
        w.input[id].rt       = inp.rt
        w.input[id].fire     = inp.fire
        w.input[id].reload   = inp.reload
        w.input[id].aimAngle = inp.aimAngle

        -- Prepend snapshot to history, trim to historySize.
        -- Index 1 is always the most recent frame.
        local history        = w.input[id].inputHistory
        table.insert(history, 1, {
            up       = inp.up,
            dn       = inp.dn,
            lt       = inp.lt,
            rt       = inp.rt,
            fire     = inp.fire,
            reload   = inp.reload,
            aimAngle = inp.aimAngle,
        })
        if #history > w.input[id].historySize then
            table.remove(history)
        end

        ::continue::
    end
end

return SystemsInput
