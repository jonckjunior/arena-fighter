local SInput             = require "systems_input"
local SPhysics           = require "systems_physics"
local SCombat            = require "systems_combat"
local SRender            = require "systems_render"
local SEffects           = require "systems_effects"

---@class Systems
local Systems            = {}

-- ── Re-export sub-system functions that game.lua calls directly ───────────────

Systems.gatherLocalInput = SInput.gatherLocalInput
Systems.draw             = SRender.draw
Systems.drawHpBars       = SRender.drawHpBars
Systems.shakeEvent       = SEffects.shakeEvent
Systems.isRoundOver      = SCombat.isRoundOver
Systems.getRoundWinner   = SCombat.getRoundWinner

-- ── Fixed-tick simulation loop ────────────────────────────────────────────────

---Runs all simulation systems for one fixed timestep.
---@param w World
---@param frameInputs table
---@param localPlayerIndex integer
---@param dt number
function Systems.runSystems(w, frameInputs, localPlayerIndex, dt)
    SInput.applyInputs(w, frameInputs)
    SPhysics.snapshotPositions(w)
    SPhysics.applyGravity(w, dt)
    SPhysics.inputToVelocity(w, dt)
    SPhysics.playerMove(w, dt)
    SPhysics.applyVelocity(w, dt)
    SCombat.gunCooldown(w)
    SCombat.gunFollow(w)
    SCombat.firing(w)
    SCombat.bulletPlayerCollision(w)
    SCombat.bulletTerrainCollision(w)
    SCombat.death(w)
    SPhysics.updateJumpTimers(w, dt)
    SRender.animation(w, dt)
    SEffects.presentEffects(w, localPlayerIndex)
    SCombat.lifetime(w, dt)
end

return Systems
