local Assets         = require "assets"
local SInput         = require "systems/systems_input"
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

---@param game GameInstance
---@param rawInput RawInput
---@return table
function Runtime.buildFrameInputs(game, rawInput)
    local world = game:getWorld()
    if not world then return {} end

    local cursor = SCursor.getState()
    if game:usesNetwork() then
        local playerIndex = game:getLocalPlayerIndex()
        local raw = SInput.captureLocalInput(playerIndex, true, rawInput)
        return {
            [playerIndex] = SInput.mapLocalInput(playerIndex, world, cursor.worldX, cursor.worldY, raw),
        }
    end

    local frameInputs = {}
    for playerIndex = 1, game:getPlayerCount() do
        local raw = SInput.captureLocalInput(playerIndex, false, rawInput)
        frameInputs[playerIndex] = SInput.mapLocalInput(playerIndex, world, cursor.worldX, cursor.worldY, raw)
    end
    return frameInputs
end

---@param game GameInstance
---@return GameHooks
function Runtime.createGameHooks(game)
    return {
        beforeSimulationTick = function(w)
            SPresent.snapshotPositions(w)
        end,
        afterSimulationTick = function(w, dt)
            SPresent.presentVisualState(w, dt)
            SEffects.presentEffects(w, game:getLocalPlayerIndex(), dt)
        end,
    }
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
