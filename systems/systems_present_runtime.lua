local Assets         = require "assets"
local SEffects       = require "systems/systems_effects"
local SPresentCamera = require "systems/systems_present_camera"
local SPresentDraw   = require "systems/systems_present_draw"
local SPresentPose   = require "systems/systems_present_pose"
local SPresentUi     = require "systems/systems_present_ui"
local SCursor        = require "systems/systems_cursor"

---@class SystemsPresentRuntime
local Runtime        = {}

function Runtime.init()
    Assets.load()
end

---@param rawInput RawInput
---@return number
---@return number
function Runtime.getMouseWorldPosition(rawInput)
    local cameraX, cameraY = SPresentCamera.getPosition()
    return (rawInput.mouseX or 0) + cameraX, (rawInput.mouseY or 0) + cameraY
end

---@param game GameInstance
---@param rawInput RawInput
---@param dt number
function Runtime.present(game, rawInput, dt)
    local w = game:getWorld()
    if not w then return end

    local localPlayerIndex = game:getLocalPlayerIndex()
    local targetX, targetY = Runtime.getMouseWorldPosition(rawInput)

    SCursor.update(rawInput.mouseX or 0, rawInput.mouseY or 0, targetX, targetY)
    SPresentCamera.update(w, localPlayerIndex, targetX, targetY, dt)
    SPresentPose.updateFacing(w)
    SPresentPose.updateWalkAnimation(w)
    SPresentPose.updateGunPresentation(w)
    SPresentPose.animation(w, dt)
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
    SPresentDraw.drawWorld(w, alpha)
    SPresentDraw.drawHpBars(w, alpha)
    SPresentDraw.drawReloadBars(w, alpha)

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

---@param game GameInstance
---@param canvas love.Canvas
function Runtime.drawGame(game, canvas)
    local world = game:getWorld()
    if not world then return end

    local state = game:getState()
    local network = game:getNetworkState()

    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.2, 0.2, 0.2)
    Runtime.drawWorldFrame(world, game:getDrawAlpha())
    love.graphics.setCanvas()
    love.graphics.draw(canvas, 0, 0, 0, SCALE_FACTOR, SCALE_FACTOR)

    Runtime.drawScreenUi(
        state.gameState,
        state.waitTimer,
        state.roundWinner,
        state.DRAW,
        game:usesNetwork(),
        state.localWantsRestart,
        state.scores,
        network.networkIndex,
        game:usesNetwork() and network.ls and network.ls.frame or nil,
        game:usesNetwork() and network.ls and network.ls.stalledFrames or nil
    )
end

return Runtime
