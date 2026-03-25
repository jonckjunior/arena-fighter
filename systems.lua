local SInput             = require "systems/systems_input"
local SPhysics           = require "systems/systems_physics"
local SCombat            = require "systems/systems_combat"
local SPresent           = require "systems/systems_present"
local SEffects           = require "systems/systems_effects"
local SPresentCamera     = require "systems/systems_present_camera"
local SPresentUi         = require "systems/systems_present_ui"

---@class Systems
local Systems            = {}

-- ── Re-export functions that game.lua calls directly ─────────────────────────

Systems.gatherLocalInput = SInput.gatherLocalInput
Systems.drawWorld        = SPresent.drawWorld
Systems.drawHpBars       = SPresent.drawHpBars
Systems.drawReloadBars   = SPresent.drawReloadBars
Systems.shakeEvent       = SEffects.shakeEvent
Systems.initCamera       = SPresentCamera.init
Systems.updateCamera     = SPresentCamera.update
Systems.consumeShake     = SPresentCamera.consumeShake
Systems.tickCameraShake  = SPresentCamera.tickShake
Systems.getCameraPosition = SPresentCamera.getPosition
Systems.getCameraShakeOffset = SPresentCamera.getShakeOffset
Systems.drawCursor       = SPresentUi.drawCursor
Systems.drawNetworkDebug = SPresentUi.drawNetworkDebug
Systems.drawScores       = SPresentUi.drawScores
Systems.drawOverlays     = SPresentUi.drawOverlays
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
--   presentVisualState   — cosmetic, updates facing/walk state/animation
--   presentEffects       — audio
--   lifetime             — cleans up expired entities

---@param w World
---@param frameInputs table
---@param localPlayerIndex integer
---@param dt number
function Systems.runSystems(w, frameInputs, localPlayerIndex, dt)
    SInput.applyInputs(w, frameInputs)
    SPresent.snapshotPositions(w)
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
    SPresent.presentVisualState(w, dt)
    SEffects.presentEffects(w, localPlayerIndex)
    SCombat.lifetime(w, dt)
end

return Systems
