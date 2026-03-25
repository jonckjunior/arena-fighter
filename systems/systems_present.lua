local SPresentPose        = require "systems/systems_present_pose"
local SPresentDraw        = require "systems/systems_present_draw"

---@class SystemsPresent
local SystemsPresent      = {}

---Records pre-simulation positions for interpolated world drawing.
---@param w World
function SystemsPresent.snapshotPositions(w)
    SPresentPose.snapshotPositions(w)
end

---Updates visual-facing presentation state before drawing.
---@param w World
---@param dt number
function SystemsPresent.presentVisualState(w, dt)
    SPresentPose.updateFacing(w)
    SPresentPose.updateWalkAnimation(w)
    SPresentPose.animation(w, dt)
end

---Draws the world-layer animated entities.
---@param w World
---@param alpha number
function SystemsPresent.drawWorld(w, alpha)
    SPresentDraw.drawWorld(w, alpha)
end

---@param w World
---@param alpha number
function SystemsPresent.drawHpBars(w, alpha)
    SPresentDraw.drawHpBars(w, alpha)
end

---@param w World
---@param alpha number
function SystemsPresent.drawReloadBars(w, alpha)
    SPresentDraw.drawReloadBars(w, alpha)
end

return SystemsPresent
