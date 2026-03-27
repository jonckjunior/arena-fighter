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
---@field gravity     string
---@field grounded    string
---@field jumpTimers  string

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
    gravity     = "gravity",
    grounded    = "grounded",
}

function C.grounded()
    return {
        value               = false,
        wallDir             = 0,   -- -1 = wall on left, 1 = wall on right, 0 = none
        framesSinceGrounded = 0,   -- increments each airborne frame, resets on landing
        framesSinceJump     = 999, -- increments every frame, reset to 0 when a jump fires
        framesSinceWall     = 999, -- increments each frame not touching a wall, resets on wall contact
        lastWallDir         = 0,   -- wallDir value from the last frame a wall was touched (-1 or 1)
    }
end

---@param historySize integer  number of frames to keep (use PLAYER_CONSTANTS.INPUT_HISTORY_FRAMES)
function C.input(historySize)
    return {
        up           = false,
        dn           = false,
        lt           = false,
        rt           = false,
        fire         = false,
        aimAngle     = 0,
        -- Ring buffer of raw input snapshots, index 1 = most recent frame.
        -- Each entry is a plain table: { up, dn, lt, rt, fire, aimAngle }
        inputHistory = {},
        historySize  = historySize or 30,
    }
end

function C.playerIndex(index)
    return { index = index }
end

function C.position(x, y)
    return { x = x, y = y, px = x, py = y }
end

function C.gravity(g)
    return { g = g }
end

function C.velocity(dx, dy)
    return { dx = dx or 0, dy = dy or 0 }
end

function C.speed(value)
    return { value = value }
end

function C.animation(frameIds, duration)
    return { frameIds = frameIds, current = 1, timer = 0, duration = duration, isPlaying = false }
end

function C.facing(dir)
    return { dir = dir or 1 }
end

---Creates a circle collider
---@param radius number
---@return {shape: string, radius: integer, ox: integer, oy: integer}
function C.circleCollider(radius, ox, oy)
    return { shape = "circle", radius = radius, ox = ox or 0, oy = oy or 0 }
end

---Creates a rectangle collider. Position is treated as the center.
---@param w integer
---@param h integer
---@param ox integer
---@param oy integer
---@return {shape: string, w: integer, h: integer, ox: integer, oy: integer}
function C.rectCollider(w, h, ox, oy)
    return { shape = "rect", w = w, h = h, ox = ox or 0, oy = oy or 0 }
end

function C.gun(maxCooldown, damage, bulletSpeed, bulletCount, spread, maxAmmo, reloadTime, muzzleOffsetX, muzzleOffsetY)
    return {
        cooldown      = 0,
        maxCooldown   = maxCooldown,
        damage        = damage,
        bulletSpeed   = bulletSpeed,
        bulletCount   = bulletCount,
        spread        = spread,
        maxAmmo       = maxAmmo,
        currentAmmo   = maxAmmo,
        reloadTime    = reloadTime,
        reloadTimer   = 0,
        isReloading   = false,
        muzzleOffsetX = muzzleOffsetX,
        muzzleOffsetY = muzzleOffsetY,
    }
end

function C.bullet(ownerId, damage, graceFrames)
    return { ownerId = ownerId, damage = damage, graceFrames = graceFrames or 1 }
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

function C.solid()
    return {}
end

return C
