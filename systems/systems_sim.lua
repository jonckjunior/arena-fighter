local SPhysics            = require "systems/systems_physics"
local SCombat             = require "systems/systems_combat"

---@class SystemsSim
local SystemsSim          = {}

SystemsSim.isRoundOver    = SCombat.isRoundOver
SystemsSim.getRoundWinner = SCombat.getRoundWinner

---@param w World
---@param frameInputs table
---@param dt number
function SystemsSim.runSimulation(w, frameInputs, dt)
    SPhysics.snapshotPositions(w)
    SPhysics.commitFrameInputs(w, frameInputs)
    SPhysics.applyGravity(w, dt)
    SPhysics.applyHorizontalMovement(w)
    SPhysics.applyJump(w)
    SPhysics.applyWallJump(w)
    SPhysics.applyVariableJumpCutoff(w)
    SPhysics.playerMove(w, dt)
    SPhysics.updateGroundedTimer(w)
    SPhysics.applyVelocity(w, dt)
    SCombat.gunCooldown(w)
    SCombat.gunFollow(w)
    SCombat.reload(w, dt)
    SCombat.firing(w)
    SCombat.bulletPlayerCollision(w)
    SCombat.bulletTerrainCollision(w)
    SCombat.death(w)
    SCombat.lifetime(w, dt)
end

return SystemsSim
