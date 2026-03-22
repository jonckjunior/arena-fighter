local World            = require "world"
local C                = require "components"
local PLAYER_CONSTANTS = require "player_constants"

---@class Spawners
local Spawners         = {}

Spawners.GunDefs       = {
    pistol = {
        maxCooldown = 15,
        damage      = 20,
        bulletSpeed = 400,
        bulletCount = 1,
        spread      = 0,
        sprite      = "Assets/Sprites/Weapons/Tiles/tile_0000.png",
    },
    ak47 = {
        maxCooldown = 15,
        damage      = 20,
        bulletSpeed = 400,
        bulletCount = 1,
        spread      = 0,
        sprite      = "Assets/Sprites/Weapons/Tiles/tile_0005.png",
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
    w.speed[id]       = C.speed(120)
    w.input[id]       = C.input()
    w.animation[id]   = C.animation({
        love.graphics.newImage("Assets/Sprites/Players/Tiles/tile_0000.png"),
        love.graphics.newImage("Assets/Sprites/Players/Tiles/tile_0001.png"),
        love.graphics.newImage("Assets/Sprites/Players/Tiles/tile_0002.png"),
    }, 0.15)
    w.facing[id]      = C.facing(1)
    w.collider[id]    = C.rectCollider(10, 14)
    w.drawLayer[id]   = C.drawLayer(1)
    w.playerIndex[id] = C.playerIndex(index)
    w.hp[id]          = C.hp(PLAYER_CONSTANTS.HP)
    w.gravity[id]     = C.gravity(PLAYER_CONSTANTS.GRAVITY)
    w.grounded[id]    = C.grounded()
    w.jumpTimers[id]  = C.jumpTimers(PLAYER_CONSTANTS.COYOTE_TIME, PLAYER_CONSTANTS.JUMP_BUFFER_TIME)
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
    w.collider[id]            = C.circleCollider(3)
    w.bullet[id]              = C.bullet(ownerId, damage)
    w.lifetime[id]            = C.lifetime(2.0)
    w.animation[id]           = C.animation({
        love.graphics.newImage("Assets/Sprites/Weapons/Tiles/tile_0023.png")
    }, 0.1)
    w.animation[id].isPlaying = true
    w.drawLayer[id]           = C.drawLayer(2)
    w.gravity[id]             = C.gravity(w.STANDARD_GRAVITY)

    local playerIndex         = w.playerIndex[ownerId] and w.playerIndex[ownerId].index
    Spawners.soundEvent(w, "Assets/Sounds/gunshot.ogg", x, y, playerIndex)
    Spawners.shakeEvent(w, 1, 0.1, playerIndex)
    return id
end

function Spawners.soundEvent(w, soundPath, x, y, playerIndex)
    local id = World.newEntity(w)
    w.soundEvent[id] = C.soundEvent(soundPath, x, y, playerIndex)
    return id
end

function Spawners.shakeEvent(w, intensity, duration, playerIndex)
    local id = World.newEntity(w)
    w.shakeEvent[id] = C.shakeEvent(intensity, duration, playerIndex)
    return id
end

function Spawners.wall(w, x, y)
    local id        = World.newEntity(w)
    w.position[id]  = C.position(x, y)
    w.collider[id]  = C.rectCollider(16, 16)
    w.solid[id]     = true
    w.animation[id] = C.animation({
        love.graphics.newImage("Assets/Sprites/Tiles/Tiles/tile_0222.png")
    }, 0.1)
    w.drawLayer[id] = C.drawLayer(1)
    return id
end

---@param mapDef MapDef
---@return World
function Spawners.fromMapDef(mapDef)
    local w                 = World.new()
    w.map                   = love.graphics.newImage(mapDef.imagePath)
    w.mapWidth, w.mapHeight = w.map:getDimensions()

    for i, sp in ipairs(mapDef.spawnPoints) do
        local pid = Spawners.player(w, sp.x, sp.y, i)
        Spawners.gun(w, pid, "pistol")
    end

    -- Spawn a horizontal strip of wall tiles from x1 to x2 (step 16) at height y
    local function row(x1, x2, y)
        for x = x1, x2, 16 do
            Spawners.wall(w, x, y)
        end
    end

    -- ── Arena layout (480 × 270 viewport) ──────────────────────────────────
    --
    --           [   center platform   ]          y = 190
    --   [ left platform ]       [ right platform ]   y = 222  (+32)
    --                   [cov]   [cov]                y = 238  (on floor)
    -- [================== floor ===================] y = 254  (+32)
    --
    -- Every vertical step is 32px. Jump apex with JUMP_SPEED=150, gravity=240
    -- is ~47px, so every platform is safely reachable in one jump.

    -- Floor — full viewport width
    row(8, 472, 254)

    -- Left side platform (6 tiles, x 64–144)
    row(64, 144, 222)

    -- Right side platform (6 tiles, x 336–416)
    row(336, 416, 222)

    -- Centre raised platform (6 tiles, x 200–280)
    row(200, 280, 190)

    -- Two single-tile cover blocks sitting on the floor.
    -- They block sight lines across the middle of the arena and give
    -- players something to duck behind without fully blocking movement.
    Spawners.wall(w, 176, 238) -- left-centre cover
    Spawners.wall(w, 304, 238) -- right-centre cover

    return w
end

return Spawners
