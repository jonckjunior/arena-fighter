local World              = require "world"
local C                  = require "components"
local Utils              = require "utils"

---@alias FrameInput { up: boolean, dn: boolean, lt: boolean, rt: boolean, fire: boolean, reload: boolean, aimAngle: number }
---@alias FrameInputs table<integer, FrameInput>

---@class SystemsHandleInput
local SystemsHandleInput = {}
local atan2              = math.atan2 or function(y, x) return math.atan(y / x) end

local function getPlayerGun(w, playerId)
    local guns = World.query(w, C.Name.equippedBy, C.Name.position, C.Name.animation)
    return Utils.find(guns, function(id)
        return w.equippedBy[id].ownerId == playerId
    end)
end

---Resolves a player's aim angle against an explicit world-space target.
---@param playerIndex integer
---@param w World
---@param targetX number
---@param targetY number
---@param fallbackAngle number|nil
---@return number
function SystemsHandleInput.resolveAimAngle(playerIndex, w, targetX, targetY, fallbackAngle)
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

---Returns gameplay-ready input for one local player.
---@param playerIndex integer
---@param w World
---@param mx number
---@param my number
---@param USE_NETWORK boolean
---@param keysPressed RawInput
---@return FrameInput
function SystemsHandleInput.gatherLocalInput(playerIndex, w, mx, my, USE_NETWORK, keysPressed)
    local input
    if playerIndex == 1 or USE_NETWORK then
        input = {
            up = keysPressed["w"],
            dn = keysPressed["s"],
            lt = keysPressed["a"],
            rt = keysPressed["d"],
            fire = keysPressed["leftMouse"],
            reload = keysPressed["r"],
        }
    else
        input = {
            up = keysPressed["u"],
            dn = keysPressed["j"],
            lt = keysPressed["h"],
            rt = keysPressed["k"],
            fire = keysPressed["space"],
            reload = keysPressed["r"],
        }
    end

    input.aimAngle = SystemsHandleInput.resolveAimAngle(playerIndex, w, mx, my, 0)
    return input
end

---@param game GameInstance
---@param rawInput RawInput
---@param targetX number
---@param targetY number
---@return FrameInputs
function SystemsHandleInput.getGameplayInput(game, rawInput, targetX, targetY)
    local world = game:getWorld()
    if not world then return {} end

    local frameInputs = {}
    if game:usesNetwork() then
        local playerIndex = game:getLocalPlayerIndex()
        frameInputs[playerIndex] = SystemsHandleInput.gatherLocalInput(playerIndex, world, targetX, targetY, true,
            rawInput)
    else
        for playerIndex = 1, game:getPlayerCount() do
            frameInputs[playerIndex] = SystemsHandleInput.gatherLocalInput(playerIndex, world, targetX, targetY, false,
                rawInput)
        end
    end
    return frameInputs
end

return SystemsHandleInput
