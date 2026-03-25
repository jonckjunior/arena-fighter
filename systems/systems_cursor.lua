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

---@param screenX number
---@param screenY number
---@param worldX number
---@param worldY number
function SystemsCursor.update(screenX, screenY, worldX, worldY)
    state.screenX = screenX
    state.screenY = screenY
    state.worldX = worldX
    state.worldY = worldY
end

---@return CursorState
function SystemsCursor.getState()
    return state
end

return SystemsCursor
