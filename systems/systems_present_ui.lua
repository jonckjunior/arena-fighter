local Assets            = require "assets"
local Utils             = require "utils"

---@class SystemsPresentUi
local SystemsPresentUi  = {}

---@param cursor CursorState
function SystemsPresentUi.drawCursor(cursor)
    if not (cursor and cursor.spriteId) then return end

    local sprite = Assets.getImage(cursor.spriteId)
    love.graphics.draw(sprite, cursor.screenX, cursor.screenY, 0, 1, 1,
        Utils.round(sprite:getWidth() / 2),
        Utils.round(sprite:getHeight() / 2))
end

---@param networkIndex integer
---@param frame integer
---@param stalledFrames integer
function SystemsPresentUi.drawNetworkDebug(networkIndex, frame, stalledFrames)
    local stall = stalledFrames > 0 and "  STALLED x" .. stalledFrames or ""
    love.graphics.print("P" .. networkIndex .. "  f=" .. frame .. stall, 4, 4)
end

---@param scores table
function SystemsPresentUi.drawScores(scores)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("P1: " .. scores[1], 10, 10)
    love.graphics.print("P2: " .. scores[2], love.graphics.getWidth() - 60, 10)
end

---@param gameState string
---@param waitTimer number
---@param roundWinner integer|nil
---@param drawValue integer
---@param useNetwork boolean
---@param localWantsRestart boolean
function SystemsPresentUi.drawOverlays(gameState, waitTimer, roundWinner, drawValue, useNetwork, localWantsRestart)
    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    if gameState == "waiting" then
        local secs = math.ceil(waitTimer)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(secs > 0 and tostring(secs) or "Fight!", 0, sh / 2 - 8, sw, "center")
        love.graphics.setColor(1, 1, 1)
    elseif gameState == "roundOver" then
        local text
        if roundWinner ~= drawValue then
            text = "Player " .. roundWinner .. " wins!"
        else
            text = "Draw!"
        end
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 0, 0, sw, sh)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(text, 0, sh / 2 - 16, sw, "center")
    elseif gameState == "matchOver" then
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 0, 0, sw, sh)
        love.graphics.setColor(1, 1, 1)
        if useNetwork and localWantsRestart then
            love.graphics.printf("Waiting for other players...", 0, sh / 2 + 8, sw, "center")
        else
            love.graphics.printf("Press R to play again", 0, sh / 2 + 8, sw, "center")
        end
    end
end

return SystemsPresentUi
