local World            = require "world"
local C                = require "components"
local PLAYER_CONSTANTS = require "player_constants"
local Assets           = require "assets"

---@class Spawners
local Spawners         = {}

Spawners.GunDefs       = {
    pistol = {
        maxCooldown = 30,
        damage      = 35,
        bulletSpeed = 400,
        bulletCount = 1,
        spread      = 0,
        spriteId    = "gun_pistol",
        maxAmmo     = 3,
        reloadTime  = 1.5, -- seconds
    },
    ak47 = {
        maxCooldown = 15,
        damage      = 20,
        bulletSpeed = 400,
        bulletCount = 1,
        spread      = 0,
        spriteId    = "gun_ak47",
        maxAmmo     = 30,
        reloadTime  = 2.0,
    },
}

---Creates and returns a player at position x and y with network index index
---@param w World
---@param x integer
---@param y integer
---@param index integer
---@return integer
function Spawners.player(w, x, y, index)
    local id          = World.newEntity(w)
    w.position[id]    = C.position(x, y)
    w.velocity[id]    = C.velocity()
    w.speed[id]       = C.speed(PLAYER_CONSTANTS.SPEED)
    w.input[id]       = C.input(PLAYER_CONSTANTS.INPUT_HISTORY_FRAMES)
    w.animation[id]   = C.animation({ "player_idle_1", "player_idle_2", "player_idle_3" }, 0.15)
    w.facing[id]      = C.facing(1)
    w.collider[id]    = C.rectCollider(10, 14, 0, 4)
    w.drawLayer[id]   = C.drawLayer(1)
    w.playerIndex[id] = C.playerIndex(index)
    w.hp[id]          = C.hp(PLAYER_CONSTANTS.HP)
    w.gravity[id]     = C.gravity(PLAYER_CONSTANTS.GRAVITY)
    w.grounded[id]    = C.grounded()
    return id
end

---Spawns a gun for the owner
---@param w World
---@param ownerId integer
---@param defName string
---@return integer
function Spawners.gun(w, ownerId, defName)
    local def = Spawners.GunDefs[defName]
    local id  = World.newEntity(w)
    assert(w.position[ownerId])
    w.position[id]   = C.position(w.position[ownerId].x, w.position[ownerId].y)
    w.equippedBy[id] = C.equippedBy(ownerId)
    w.gun[id]        = C.gun(def.maxCooldown, def.damage, def.bulletSpeed, def.bulletCount, def.spread) -- In Spawners.gun(), pass the new fields:
    w.gun[id]        = C.gun(
        def.maxCooldown, def.damage, def.bulletSpeed,
        def.bulletCount, def.spread,
        def.maxAmmo, def.reloadTime
    )
    w.animation[id]  = C.animation({ def.spriteId }, 0.1)
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
    w.collider[id]            = C.circleCollider(3, 0, 0)
    w.bullet[id]              = C.bullet(ownerId, damage)
    w.lifetime[id]            = C.lifetime(2.0)
    w.animation[id]           = C.animation({ "bullet_basic" }, 0.1)
    w.animation[id].isPlaying = true
    w.drawLayer[id]           = C.drawLayer(2)
    w.gravity[id]             = C.gravity(PLAYER_CONSTANTS.STANDARD_GRAVITY_BULLET)

    local playerIndex         = w.playerIndex[ownerId] and w.playerIndex[ownerId].index
    Spawners.soundEvent(w, "Assets/Sounds/gunshot.ogg", x, y, playerIndex)
    Spawners.shakeEvent(w, 1, 0.1, playerIndex)
    return id
end

function Spawners.soundEvent(w, soundPath, x, y, playerIndex)
    local id         = World.newEntity(w)
    w.soundEvent[id] = C.soundEvent(soundPath, x, y, playerIndex)
    return id
end

function Spawners.shakeEvent(w, intensity, duration, playerIndex)
    local id         = World.newEntity(w)
    w.shakeEvent[id] = C.shakeEvent(intensity, duration, playerIndex)
    return id
end

function Spawners.wall(w, x, y)
    local id        = World.newEntity(w)
    w.position[id]  = C.position(x, y)
    w.collider[id]  = C.rectCollider(16, 11, 0, 1)
    w.solid[id]     = C.solid()
    w.animation[id] = C.animation({ "wall_basic" }, 0.1)
    w.drawLayer[id] = C.drawLayer(1)
    return id
end

---@param mapDef MapDef
---@return World
function Spawners.fromMapDef(mapDef)
    local w                 = World.new()
    local mapImage          = Assets.getImage(mapDef.assetId)
    w.mapAssetId            = mapDef.assetId
    w.mapWidth, w.mapHeight = mapImage:getDimensions()

    for i, sp in ipairs(mapDef.spawnPoints) do
        local pid = Spawners.player(w, sp.x, sp.y, i)
        Spawners.gun(w, pid, "pistol")
    end

    local function row(x1, x2, y)
        for x = x1, x2, 16 do
            Spawners.wall(w, x, y)
        end
    end

    row(8, 472, 254)
    row(64, 144, 222 - 16)
    row(336, 416, 222 - 16)
    row(200, 280, 190)
    Spawners.wall(w, 176, 238)
    Spawners.wall(w, 304, 238)

    for i = 1, 100 do
        Spawners.wall(w, 16, i * 16)
    end

    for i = 1, 100 do
        Spawners.wall(w, 400, i * 16)
    end

    for i = 1, 100 do
        Spawners.wall(w, i * 16, 0)
    end

    return w
end

return Spawners
