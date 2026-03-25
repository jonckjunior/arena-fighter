local Assets         = require "assets"
local SPresent       = require "systems/systems_present"
local SEffects       = require "systems/systems_effects"
local SPresentCamera = require "systems/systems_present_camera"
local SPresentUi     = require "systems/systems_present_ui"
local SCursor        = require "systems/systems_cursor"

---@class SystemsPresentRuntime
local Runtime        = {}

function Runtime.init()
    Assets.load()
    SPresentCamera.init()
    SCursor.init("cursor_cross")
end

---@param rawInput RawInput
function Runtime.updatePresentationInput(rawInput)
    local cameraX, cameraY = SPresentCamera.getPosition()
    SCursor.updateFromMouse(rawInput.mouseX or 0, rawInput.mouseY or 0, cameraX, cameraY)
end

---@param w World
---@param localPlayerIndex integer
---@param dt number
function Runtime.updatePresentationCamera(w, localPlayerIndex, dt)
    local cursor = SCursor.getState()
    SPresentCamera.update(w, localPlayerIndex, cursor.worldX, cursor.worldY, dt)
end

---@param w World
---@param localPlayerIndex integer
---@param dt number
function Runtime.runPresentationTick(w, localPlayerIndex, dt)
    SPresent.presentVisualState(w, dt)
    SEffects.presentEffects(w, localPlayerIndex, dt)
end

---@param w World
---@param alpha number
function Runtime.drawWorldFrame(w, alpha)
    local cameraX, cameraY = SPresentCamera.getPosition()
    local shakeX, shakeY = SPresentCamera.getShakeOffset()

    love.graphics.push()
    love.graphics.translate(-cameraX + shakeX, -cameraY + shakeY)

    if w.mapAssetId then
        love.graphics.draw(Assets.getImage(w.mapAssetId), 0, 0)
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
function Runtime.drawScreenUi(gameState, waitTimer, roundWinner, drawValue, useNetwork, localWantsRestart, scores,
                              networkIndex, networkFrame, stalledFrames)
    if useNetwork and networkIndex and networkFrame ~= nil and stalledFrames ~= nil then
        SPresentUi.drawNetworkDebug(networkIndex, networkFrame, stalledFrames)
    end

    SPresentUi.drawOverlays(gameState, waitTimer, roundWinner, drawValue, useNetwork, localWantsRestart)
    SPresentUi.drawScores(scores)
end

return Runtime
