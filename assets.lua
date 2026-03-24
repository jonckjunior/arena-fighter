---@class Assets
local Assets = {}

local IMAGE_PATHS = {
    player_idle_1 = "Assets/Sprites/Players/Tiles/tile_0000.png",
    player_idle_2 = "Assets/Sprites/Players/Tiles/tile_0001.png",
    player_idle_3 = "Assets/Sprites/Players/Tiles/tile_0002.png",
    gun_pistol    = "Assets/Sprites/Weapons/Tiles/tile_0000.png",
    gun_ak47      = "Assets/Sprites/Weapons/Tiles/tile_0005.png",
    bullet_basic  = "Assets/Sprites/Weapons/Tiles/tile_0023.png",
    wall_basic    = "Assets/Sprites/Tiles/Tiles/tile_0222.png",
    cursor_cross  = "Assets/Sprites/Weapons/Tiles/tile_0024.png",
    map_arena     = "Assets/Maps/arena.png",
}

local images = {}

function Assets.load()
    for id, path in pairs(IMAGE_PATHS) do
        if not images[id] then
            images[id] = love.graphics.newImage(path)
        end
    end
end

---@param id string
---@return love.Image
function Assets.getImage(id)
    local image = images[id]
    assert(image, "Unknown image asset id: " .. tostring(id))
    return image
end

return Assets
