local SInput             = require "systems/systems_input"
local SPhysics           = require "systems/systems_physics"
local SCombat            = require "systems/systems_combat"
local SRender            = require "systems/systems_render"
local SEffects           = require "systems/systems_effects"

---@class Systems
local Systems            = {}

-- ── Re-export functions that game.lua calls directly ─────────────────────────

Systems.gatherLocalInput = SInput.gatherLocalInput
Systems.draw             = SRender.draw
Systems.drawHpBars       = SRender.drawHpBars
Systems.shakeEvent       = SEffects.shakeEvent
Systems.isRoundOver      = SCombat.isRoundOver
Systems.getRoundWinner   = SCombat.getRoundWinner

-- ── Fixed-tick simulation loop ────────────────────────────────────────────────
--
-- Ordering rationale:
--   applyInputs          — write raw input + history before anything reads it
--   snapshotPositions    — record pre-physics positions for interpolated rendering
--   applyGravity         — accumulate vertical force before movement resolves it
--   applyHorizontalMovement — set dx from input
--   applyJump            — reads framesSinceGrounded (prev frame) + history → sets dy
--   applyWallJump        — reads framesSinceWall (prev frame) + history → sets dx, dy
--                          runs after applyJump so the shared cooldown blocks both
--                          from firing in the same frame
--   applyVariableJumpCutoff — clamps dy on early key release
--   playerMove           — sweeps position, resolves contacts, writes grounded + wallDir
--   updateGroundedTimer  — reads fresh grounded.value/wallDir → updates timers
--   applyVelocity        — moves non-player entities (bullets)
--   combat               — guns, bullets, damage, death, lifetime
--   updateFacing         — cosmetic, reads aimAngle
--   updateWalkAnimation  — cosmetic, reads velocity + grounded
--   animation            — advances sprite frames
--   presentEffects       — audio
--   lifetime             — cleans up expired entities

---@param w World
---@param frameInputs table
---@param localPlayerIndex integer
---@param dt number
function Systems.runSystems(w, frameInputs, localPlayerIndex, dt)
    SInput.applyInputs(w, frameInputs)
    SPhysics.snapshotPositions(w)
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
    SCombat.firing(w)
    SCombat.bulletPlayerCollision(w)
    SCombat.bulletTerrainCollision(w)
    SCombat.death(w)
    SRender.updateFacing(w)
    SRender.updateWalkAnimation(w)
    SRender.animation(w, dt)
    SEffects.presentEffects(w, localPlayerIndex)
    SCombat.lifetime(w, dt)
end

return Systems
