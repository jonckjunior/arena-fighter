local World          = require "world"
local C              = require "components"
local Utils          = require "utils"
local SPresentCamera = require "systems/systems_present_camera"

---@class SystemsEffects
local SystemsEffects = {}

---@param w World
---@param localPlayerIndex integer
local function presentAudio(w, localPlayerIndex)
    local players = World.query(w, C.Name.playerIndex, C.Name.position)
    local pid     = Utils.find(players, function(id)
        return w.playerIndex[id].index == localPlayerIndex
    end)

    if pid then
        love.audio.setPosition(w.position[pid].x, w.position[pid].y, 0)
    end

    local toDelete = {}
    for _, id in ipairs(World.query(w, C.Name.soundEvent)) do
        local ev  = w.soundEvent[id]
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
        toDelete[#toDelete + 1] = id
    end
    for _, id in ipairs(toDelete) do
        World.destroy(w, id)
    end
end

---@param w World
---@param localPlayerIndex integer
---@param dt number
local function presentShake(w, localPlayerIndex, dt)
    local intensity   = 0
    local duration    = 0
    local shakeEvents = World.query(w, C.Name.shakeEvent)

    for _, id in ipairs(shakeEvents) do
        local ev = w.shakeEvent[id]
        if ev.playerIndex == localPlayerIndex and ev.intensity > intensity then
            intensity = ev.intensity
            duration  = ev.duration
        end
    end

    SPresentCamera.consumeShake(intensity, duration)
    SPresentCamera.tickShake(dt)

    for _, id in ipairs(shakeEvents) do
        World.destroy(w, id)
    end
end

---Consumes all pending presentation events for the local player.
---@param w World
---@param localPlayerIndex integer
---@param dt number
function SystemsEffects.presentEffects(w, localPlayerIndex, dt)
    presentAudio(w, localPlayerIndex)
    presentShake(w, localPlayerIndex, dt)
end

return SystemsEffects
