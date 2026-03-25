local SInput              = require "systems/systems_input"
local Sim                 = require "systems/systems_sim"
local SPresent            = require "systems/systems_present"
local SEffects            = require "systems/systems_effects"
local SPresentCamera      = require "systems/systems_present_camera"
local SPresentUi          = require "systems/systems_present_ui"
local SCursor             = require "systems/systems_cursor"

---@class Systems
local Systems             = {}

Systems.gatherLocalInput  = SInput.gatherLocalInput
Systems.isRoundOver       = Sim.isRoundOver
Systems.getRoundWinner    = Sim.getRoundWinner
Systems.snapshotPositions = SPresent.snapshotPositions
Systems.getCursorState    = SCursor.getState

function Systems.initPresentation()
    SPresentCamera.init()
    SCursor.init("cursor_cross")
end

---@param rawInput RawInput
function Systems.updatePresentationInput(rawInput)
    local cameraX, cameraY = SPresentCamera.getPosition()
    SCursor.updateFromMouse(rawInput.mouseX or 0, rawInput.mouseY or 0, cameraX, cameraY)
end

---@param w World
---@param localPlayerIndex integer
---@param dt number
function Systems.updatePresentationCamera(w, localPlayerIndex, dt)
    local cursor = SCursor.getState()
    SPresentCamera.update(w, localPlayerIndex, cursor.worldX, cursor.worldY, dt)
end

---@param w World
---@param alpha number
function Systems.drawWorldFrame(w, alpha)
    local cameraX, cameraY = SPresentCamera.getPosition()
    local shakeX, shakeY = SPresentCamera.getShakeOffset()

    love.graphics.push()
    love.graphics.translate(-cameraX + shakeX, -cameraY + shakeY)

    if w.mapAssetId then
        love.graphics.draw(require("assets").getImage(w.mapAssetId), 0, 0)
    end
    SPresent.drawWorld(w, alpha)
    SPresent.drawHpBars(w, alpha)
    SPresent.drawReloadBars(w, alpha)

    love.graphics.pop()
    SPresentUi.drawCursor(SCursor.getState())
end

---@param gameState string
---@param waitTimer number
---@param roundWinner integer|nil
---@param drawValue integer
---@param useNetwork boolean
---@param localWantsRestart boolean
---@param scores table
---@param networkIndex integer|nil
---@param networkFrame integer|nil
---@param stalledFrames integer|nil
function Systems.drawScreenUi(gameState, waitTimer, roundWinner, drawValue, useNetwork, localWantsRestart, scores,
                              networkIndex, networkFrame, stalledFrames)
    if useNetwork and networkIndex and networkFrame and stalledFrames then
        SPresentUi.drawNetworkDebug(networkIndex, networkFrame, stalledFrames)
    end

    SPresentUi.drawOverlays(gameState, waitTimer, roundWinner, drawValue, useNetwork, localWantsRestart)
    SPresentUi.drawScores(scores)
end

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
    Sim.runSimulation(w, frameInputs, dt)
end

---@param w World
---@param localPlayerIndex integer
---@param dt number
function Systems.runPresentationTick(w, localPlayerIndex, dt)
    SPresent.presentVisualState(w, dt)
    SEffects.presentEffects(w, localPlayerIndex, dt)
end

return Systems
