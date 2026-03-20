---@class MapDef
---@field imagePath     string
---@field spawnPoints   table<integer, {x: integer, y: integer}>
---@field walls         {x: integer, y: integer}[]

---@type table<string, MapDef>
local Maps = {
    arena = {
        imagePath   = "Assets/Maps/arena.png",
        spawnPoints = {
            [1] = { x = 100, y = 100 },
            [2] = { x = 300, y = 100 },
        },
        walls       = {
            -- populate once we have a proper map
        },
    },
}

return Maps
