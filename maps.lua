---@class MapDef
---@field assetId       string
---@field imagePath     string
---@field spawnPoints   table<integer, {x: integer, y: integer}>
---@field walls         {x: integer, y: integer}[]
---@field width integer
---@field height integer

---@type table<string, MapDef>
local Maps = {
    arena = {
        assetId     = "map_arena",
        imagePath   = "Assets/Maps/arena.png",
        width       = 480,
        height      = 270,
        spawnPoints = {
            [1] = { x = 104, y = 160 }, -- above left platform
            [2] = { x = 376, y = 160 }, -- above right platform
        },

        walls       = {
            -- populate once we have a proper map
        },
    },
}

return Maps
