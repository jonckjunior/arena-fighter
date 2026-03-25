local SInput             = require "systems/systems_input"
local SPhysics           = require "systems/systems_physics"
local SCombat            = require "systems/systems_combat"
local SPresent           = require "systems/systems_present"
local SEffects           = require "systems/systems_effects"
local SPresentCamera     = require "systems/systems_present_camera"
local SPresentUi         = require "systems/systems_present_ui"
local SCursor            = require "systems/systems_cursor"

---@class Systems
local Systems            = {}

-- ── Re-export functions that game.lua calls directly ─────────────────────────

Systems.gatherLocalInput = SInput.gatherLocalInput
Systems.drawWorld        = SPresent.drawWorld
Systems.drawHpBars       = SPresent.drawHpBars
Systems.drawReloadBars   = SPresent.drawReloadBars
Systems.initCamera       = SPresentCamera.init
Systems.updateCamera     = SPresentCamera.update
Systems.getCameraPosition = SPresentCamera.getPosition
Systems.getCameraShakeOffset = SPresentCamera.getShakeOffset
Systems.drawCursor       = SPresentUi.drawCursor
Systems.drawNetworkDebug = SPresentUi.drawNetworkDebug
Systems.drawScores       = SPresentUi.drawScores
Systems.drawOverlays     = SPresentUi.drawOverlays
Systems.isRoundOver      = SCombat.isRoundOver
Systems.getRoundWinner   = SCombat.getRoundWinner
Systems.snapshotPositions = SPresent.snapshotPositions
Systems.initCursor       = SCursor.init
Systems.updateCursorFromMouse = SCursor.updateFromMouse
Systems.getCursorState   = SCursor.getState

-- ── Fixed-tick pipelines ──────────────────────────────────────────────────────
--
-- Ordering rationale:
--   applyInputs          — write raw input + history before anything reads it
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
--   presentEffects       — audio + camera shake events

---@param w World
---@param frameInputs table
---@param dt number
function Systems.runSimulation(w, frameInputs, dt)
    SInput.applyInputs(w, frameInputs)
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

---@param w World
---@param localPlayerIndex integer
---@param dt number
function Systems.runPresentationTick(w, localPlayerIndex, dt)
    SPresent.presentVisualState(w, dt)
    SEffects.presentEffects(w, localPlayerIndex, dt)
end

return Systems
