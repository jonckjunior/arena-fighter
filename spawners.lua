local World      = require "world"
local C          = require "components"

---@class Spawners
local Spawners   = {}

Spawners.GunDefs = {
    pistol = {
        maxCooldown = 15,
        damage      = 20,
        bulletSpeed = 600,
        bulletCount = 1,
        spread      = 0,
        sprite      = "Assets/Sprites/Weapons/Tiles/tile_0000.png",
    },
    ak47 = {
        maxCooldown = 15,
        damage      = 20,
        bulletSpeed = 600,
        bulletCount = 1,
        spread      = 0,
        sprite      = "Assets/Sprites/Weapons/Tiles/tile_0005.png",
    },
}

function Spawners.player(w, x, y, index)
    local id          = World.newEntity(w)
    w.position[id]    = C.position(x, y)
    w.velocity[id]    = C.velocity()
    w.speed[id]       = C.speed(60)
    w.input[id]       = C.input()
    w.animation[id]   = C.animation({
        love.graphics.newImage("Assets/Sprites/Players/Tiles/tile_0000.png"),
        love.graphics.newImage("Assets/Sprites/Players/Tiles/tile_0001.png"),
        love.graphics.newImage("Assets/Sprites/Players/Tiles/tile_0002.png"),
    }, 0.15)
    w.facing[id]      = C.facing(1)
    w.collider[id]    = C.collider(9)
    w.drawLayer[id]   = C.drawLayer(1)
    w.playerIndex[id] = C.playerIndex(index)
    w.hp[id]          = C.hp(100)
    return id
end

---Spawns a gun for the owner
---@param w World
---@param ownerId integer
---@param defName string
---@return integer
function Spawners.gun(w, ownerId, defName)
    local def        = Spawners.GunDefs[defName]
    local id         = World.newEntity(w)
    w.position[id]   = C.position(0, 0)
    w.equippedBy[id] = C.equippedBy(ownerId)
    w.gun[id]        = C.gun(def.maxCooldown, def.damage, def.bulletSpeed, def.bulletCount, def.spread)
    w.animation[id]  = C.animation({ love.graphics.newImage(def.sprite) }, 0.1)
    w.drawLayer[id]  = C.drawLayer(2)
    return id
end

---Spawns a bullet for the owner
---@param w World
---@param ownerId integer
---@param x number
---@param y number
---@param vx number
---@param vy number
---@param damage number
---@return integer
function Spawners.bullet(w, ownerId, x, y, vx, vy, damage)
    local id                  = World.newEntity(w)
    w.position[id]            = C.position(x, y)
    w.velocity[id]            = C.velocity(vx, vy)
    w.collider[id]            = C.collider(3)
    w.bullet[id]              = C.bullet(ownerId, damage)
    w.lifetime[id]            = C.lifetime(2.0)
    w.animation[id]           = C.animation({
        love.graphics.newImage("Assets/Sprites/Weapons/Tiles/tile_0023.png")
    }, 0.1)
    w.animation[id].isPlaying = true
    w.drawLayer[id]           = C.drawLayer(2)
    return id
end

function Spawners.barrel(w, x, y)
    local id        = World.newEntity(w)
    w.position[id]  = C.position(x, y)
    w.collider[id]  = C.collider(9)
    w.solid[id]     = true
    w.animation[id] = C.animation({
        love.graphics.newImage("Assets/Sprites/Tiles/Tiles/tile_0222.png")
    }, 0.1)
    w.drawLayer[id] = C.drawLayer(1)
    return id
end

return Spawners
