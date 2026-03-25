local SRender             = require "systems/systems_render"

---@class SystemsPresent
local SystemsPresent      = {}

---Records pre-simulation positions for interpolated world drawing.
---@param w World
function SystemsPresent.snapshotPositions(w)
    SRender.snapshotPositions(w)
end

---Updates visual-facing presentation state before drawing.
---@param w World
---@param dt number
function SystemsPresent.presentVisualState(w, dt)
    SRender.updateFacing(w)
    SRender.updateWalkAnimation(w)
    SRender.animation(w, dt)
end

---Draws the world-layer animated entities.
---@param w World
---@param alpha number
function SystemsPresent.drawWorld(w, alpha)
    SRender.draw(w, alpha)
end

---@param w World
---@param alpha number
function SystemsPresent.drawHpBars(w, alpha)
    SRender.drawHpBars(w, alpha)
end

---@param w World
---@param alpha number
function SystemsPresent.drawReloadBars(w, alpha)
    SRender.drawReloadBars(w, alpha)
end

return SystemsPresent
