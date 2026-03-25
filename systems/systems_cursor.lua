---@class CursorState
---@field spriteId string|nil
---@field screenX number
---@field screenY number
---@field worldX number
---@field worldY number

---@class SystemsCursor
local SystemsCursor = {}

---@type CursorState
local state         = {
    spriteId = nil,
    screenX = 0,
    screenY = 0,
    worldX = 0,
    worldY = 0,
}

---@param spriteId string|nil
function SystemsCursor.init(spriteId)
    state = {
        spriteId = spriteId,
        screenX = 0,
        screenY = 0,
        worldX = 0,
        worldY = 0,
    }
end

---@param mouseX number
---@param mouseY number
---@param cameraX number
---@param cameraY number
function SystemsCursor.updateFromMouse(mouseX, mouseY, cameraX, cameraY)
    state.screenX = mouseX / SCALE_FACTOR
    state.screenY = mouseY / SCALE_FACTOR
    state.worldX = state.screenX + cameraX
    state.worldY = state.screenY + cameraY
end

---@return CursorState
function SystemsCursor.getState()
    return state
end

return SystemsCursor
