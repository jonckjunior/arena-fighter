local World                  = require "world"
local C                      = require "components"
local FM                     = require "fixedmath"
local PLAYER_CONSTANTS       = require "player_constants"

---@class SystemsPresentPose
local SystemsPresentPose     = {}

---Saves positions before physics modifies them (used for interpolated rendering).
---@param w World
function SystemsPresentPose.snapshotPositions(w)
    for _, id in pairs(w.position) do
        id.px = id.x
        id.py = id.y
    end
end

---Writes facing direction from aim angle.
--- Producer: input.aimAngle
--- Consumer: facing.dir
---@param w World
function SystemsPresentPose.updateFacing(w)
    for _, id in ipairs(World.query(w, C.Name.input, C.Name.facing)) do
        w.facing[id].dir = FM.cos(w.input[id].aimAngle) >= 0 and 1 or -1
    end
end

---Enables walk animation when moving horizontally on the ground.
--- Producer: velocity.dx, grounded.value
--- Consumer: animation.isPlaying
---@param w World
function SystemsPresentPose.updateWalkAnimation(w)
    for _, id in ipairs(World.query(w, C.Name.input, C.Name.velocity, C.Name.animation, C.Name.grounded)) do
        local moving              = math.abs(w.velocity[id].dx) > PLAYER_CONSTANTS.ANIMATION_THRESHOLD_SPEED
        local onFloor             = w.grounded[id].value
        w.animation[id].isPlaying = moving and onFloor
    end
end

---Advances sprite animation timers and cycles frames.
---@param w World
---@param dt number
function SystemsPresentPose.animation(w, dt)
    for _, id in ipairs(World.query(w, C.Name.animation)) do
        local anim = w.animation[id]
        if anim.isPlaying then
            anim.timer = anim.timer + dt
            if anim.timer >= anim.duration then
                anim.timer   = anim.timer - anim.duration
                anim.current = (anim.current % #anim.frameIds) + 1
            end
        else
            anim.current = 1
            anim.timer   = 0
        end
    end
end

return SystemsPresentPose
