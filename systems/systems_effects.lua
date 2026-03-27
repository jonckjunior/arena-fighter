local World          = require "world"
local C              = require "components"
local Utils          = require "utils"
local SPresentCamera = require "systems/systems_present_camera"

---@class SystemsEffects
local SystemsEffects = {}

---@param w World
---@param sounds {soundPath: string, x: number, y: number, playerIndex: integer|nil}[]
---@param localPlayerIndex integer
local function presentAudio(w, sounds, localPlayerIndex)
    local players = World.query(w, C.Name.playerIndex, C.Name.position)
    local pid     = Utils.find(players, function(id)
        return w.playerIndex[id].index == localPlayerIndex
    end)

    if pid then
        love.audio.setPosition(w.position[pid].x, w.position[pid].y, 0)
    end

    for _, ev in ipairs(sounds) do
        local src = love.audio.newSource(ev.soundPath, "static")
        if ev.playerIndex == localPlayerIndex then
            src:setRelative(true)
            src:setPosition(0, 0, 0)
        else
            src:setRelative(false)
            src:setPosition(ev.x, ev.y, 0)
        end
        love.audio.setDistanceModel("linearclamped")
        src:setAttenuationDistances(100, 500)
        src:play()
    end
end

---@param shakes {intensity: number, duration: number, playerIndex: integer|nil}[]
---@param localPlayerIndex integer
---@param dt number
local function presentShake(shakes, localPlayerIndex, dt)
    local intensity   = 0
    local duration    = 0

    for _, ev in ipairs(shakes) do
        if ev.playerIndex == localPlayerIndex and ev.intensity > intensity then
            intensity = ev.intensity
            duration  = ev.duration
        end
    end

    SPresentCamera.consumeShake(intensity, duration)
    SPresentCamera.tickShake(dt)
end

---Consumes all pending presentation effects for the local player.
---@param w World
---@param localPlayerIndex integer
---@param dt number
function SystemsEffects.presentEffects(w, localPlayerIndex, dt)
    local effects = w.presentationEffects or { sounds = {}, shakes = {} }
    presentAudio(w, effects.sounds or {}, localPlayerIndex)
    presentShake(effects.shakes or {}, localPlayerIndex, dt)
    w.presentationEffects = { sounds = {}, shakes = {} }
end

return SystemsEffects
