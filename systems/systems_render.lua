local SPresentPose     = require "systems/systems_present_pose"
local SPresentDraw     = require "systems/systems_present_draw"

---@class SystemsRender
local SystemsRender    = {}

function SystemsRender.snapshotPositions(w)
    SPresentPose.snapshotPositions(w)
end

function SystemsRender.updateFacing(w)
    SPresentPose.updateFacing(w)
end

function SystemsRender.updateWalkAnimation(w)
    SPresentPose.updateWalkAnimation(w)
end

function SystemsRender.animation(w, dt)
    SPresentPose.animation(w, dt)
end

function SystemsRender.draw(w, alpha)
    SPresentDraw.drawWorld(w, alpha)
end

function SystemsRender.drawHpBars(w, alpha)
    SPresentDraw.drawHpBars(w, alpha)
end

function SystemsRender.drawReloadBars(w, alpha)
    SPresentDraw.drawReloadBars(w, alpha)
end

return SystemsRender
