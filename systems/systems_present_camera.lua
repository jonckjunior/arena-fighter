local World                = require "world"
local C                    = require "components"
local Utils                = require "utils"

---@class PresentCameraState
---@field x number
---@field y number
---@field lookSpeed number
---@field lookAhead number
---@field shakeIntensity number
---@field shakeTimer number
---@field shakeDuration number
---@field shakeOffsetX number
---@field shakeOffsetY number

---@class SystemsPresentCamera
local SystemsPresentCamera = {}

---@type PresentCameraState
local state                = {
    x = 0,
    y = 0,
    lookSpeed = 8,
    lookAhead = 0.2,
    shakeIntensity = 0,
    shakeTimer = 0,
    shakeDuration = 0.2,
    shakeOffsetX = 0,
    shakeOffsetY = 0,
}

---@param intensity number
---@param duration number
function SystemsPresentCamera.consumeShake(intensity, duration)
    if intensity > 0 then
        if intensity > state.shakeIntensity then
            state.shakeIntensity = intensity
        end
        if duration > state.shakeTimer then
            state.shakeTimer = duration
            state.shakeDuration = duration
        end
    end
end

---@param dt number
function SystemsPresentCamera.tickShake(dt)
    state.shakeTimer = math.max(0, state.shakeTimer - dt)
    if state.shakeTimer > 0 then
        local shakeScale = state.shakeIntensity * (state.shakeTimer / state.shakeDuration)
        state.shakeOffsetX = love.math.random(-shakeScale, shakeScale)
        state.shakeOffsetY = love.math.random(-shakeScale, shakeScale)
    else
        state.shakeOffsetX = 0
        state.shakeOffsetY = 0
        state.shakeIntensity = 0
    end
end

---@param w World
---@param targetIndex integer
---@param cursorX number
---@param cursorY number
---@param dt number
function SystemsPresentCamera.update(w, targetIndex, cursorX, cursorY, dt)
    local pid = Utils.find(
        World.query(w, C.Name.playerIndex, C.Name.position),
        function(id) return w.playerIndex[id].index == targetIndex end
    )
    if not pid then return end

    local px = w.position[pid].x
    local py = w.position[pid].y

    local targetX = px + (cursorX - px) * state.lookAhead - 240
    local targetY = py + (cursorY - py) * state.lookAhead - 135

    local t = 1 - math.exp(-state.lookSpeed * dt)
    state.x = state.x + (targetX - state.x) * t
    state.y = state.y + (targetY - state.y) * t

    state.x = math.max(0, math.min(state.x, w.mapWidth - VIEWPORT_W))
    state.y = math.max(0, math.min(state.y, w.mapHeight - VIEWPORT_H))
end

---@return number x
---@return number y
function SystemsPresentCamera.getPosition()
    return state.x, state.y
end

---@return number x
---@return number y
function SystemsPresentCamera.getShakeOffset()
    return state.shakeOffsetX, state.shakeOffsetY
end

return SystemsPresentCamera
