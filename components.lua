---@class C
local C = {}

--- Component name constants. Use these instead of raw strings with World.query/find
--- so typos are caught immediately (nil key) rather than silently returning nothing.
---@class ComponentName
---@field position    string
---@field velocity    string
---@field animation   string
---@field input       string
---@field speed       string
---@field facing      string
---@field solid       string
---@field collider    string
---@field gun         string
---@field bullet      string
---@field lifetime    string
---@field equippedBy  string
---@field drawLayer   string
---@field playerIndex string
---@field hp          string
---@field soundEvent  string
---@field shakeEvent string
C.Name = {
    position    = "position",
    velocity    = "velocity",
    animation   = "animation",
    input       = "input",
    speed       = "speed",
    facing      = "facing",
    solid       = "solid",
    collider    = "collider",
    gun         = "gun",
    bullet      = "bullet",
    lifetime    = "lifetime",
    equippedBy  = "equippedBy",
    drawLayer   = "drawLayer",
    playerIndex = "playerIndex",
    hp          = "hp",
    soundEvent  = "soundEvent",
    shakeEvent  = "shakeEvent",
}

function C.playerIndex(index)
    return { index = index }
end

function C.position(x, y)
    return { x = x, y = y, px = x, py = y }
end

function C.velocity(dx, dy)
    return { dx = dx or 0, dy = dy or 0 }
end

function C.speed(value)
    return { value = value }
end

function C.input()
    return { up = false, dn = false, lt = false, rt = false, fire = false, aimAngle = 0 }
end

function C.animation(frames, duration)
    return { frames = frames, current = 1, timer = 0, duration = duration, isPlaying = false }
end

function C.facing(dir)
    return { dir = dir or 1 }
end

function C.collider(radius)
    return { radius = radius }
end

function C.gun(maxCooldown, damage, bulletSpeed, bulletCount, spread)
    return {
        cooldown    = 0,
        maxCooldown = maxCooldown,
        damage      = damage,
        bulletSpeed = bulletSpeed,
        bulletCount = bulletCount or 1,
        spread      = spread or 0,
    }
end

function C.bullet(ownerId, damage)
    return { ownerId = ownerId, damage = damage }
end

function C.lifetime(ttl)
    return { ttl = ttl }
end

function C.equippedBy(ownerId)
    return { ownerId = ownerId }
end

function C.drawLayer(layer)
    return { layer = layer or 0 }
end

function C.hp(max)
    return { current = max, max = max }
end

function C.soundEvent(soundPath, x, y, playerIndex)
    return { soundPath = soundPath, x = x, y = y, playerIndex = playerIndex }
end

function C.shakeEvent(intensity, duration, playerIndex)
    return { intensity = intensity, duration = duration, playerIndex = playerIndex }
end

return C
