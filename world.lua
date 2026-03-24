local C     = require "components"

---@class World
---@field nextId number
---@field entities table<integer, boolean>
---@field position table<integer, {x: number, y: number, px: number, py: number}>
---@field velocity table<integer, {dx: number, dy: number}>
---@field animation table<integer, {frames: table, current: number, timer: number, duration: number, isPlaying: boolean, angle: number | nil, flipY: integer | nil}>
---@field input table<integer, {up: boolean, dn: boolean, lt: boolean, rt: boolean, fire: boolean, reload: boolean, aimAngle: number, inputHistory: table[], historySize: integer}>
---@field speed table<integer, {value: number}>
---@field facing table<integer, {dir: number}>
---@field solid table<integer, {}>
---@field collider table<integer, {shape: "circle"|"rect", radius: number|nil, w: number|nil, h: number|nil, ox: integer, oy: integer}>
---@field gun table<integer, {cooldown: number, maxCooldown: number, damage: number, bulletSpeed: number, spread: number, bulletCount: integer, isReloading: boolean, reloadTime: number, reloadTimer: number, maxAmmo: integer, currentAmmo: integer}>
---@field bullet table<integer, {ownerId: integer, damage: number, graceFrames: integer}>
---@field lifetime table<integer, {ttl: number}>
---@field equippedBy table<integer, {ownerId: integer}>
---@field drawLayer table<integer, {layer: integer}>
---@field playerIndex table<integer, {index: integer}>
---@field hp table<integer, {current: number, max: number}>
---@field soundEvent table<integer, {soundPath: string, x: number, y: number, playerIndex: integer}>
---@field shakeEvent table<integer, {intensity: number, duration: number, playerIndex: integer}>
---@field gravity table<integer, {g: number}>
---@field grounded table<integer, {value: boolean, wallDir: integer, framesSinceGrounded: integer, framesSinceJump: integer, framesSinceWall: integer, lastWallDir: integer}>
---@field rng love.RandomGenerator
---@field map love.Image
---@field mapWidth  number
---@field mapHeight number
local World = {}

---Creates a new world with all its components
---@return World
function World.new()
    local w = {
        nextId   = 1,
        entities = {},
        rng      = love.math.newRandomGenerator(12345),
    }
    for _, name in pairs(C.Name) do
        w[name] = {}
    end
    return w
end

---Creates a new entity
---@param w World
---@return integer
function World.newEntity(w)
    local id = w.nextId
    w.nextId = w.nextId + 1
    w.entities[id] = true
    return id
end

function World.destroy(w, id)
    w.entities[id] = nil
    for _, t in pairs(w) do
        if type(t) == "table" then t[id] = nil end
    end
end

--- Returns all entity ids that have every listed component.
--- Put the rarest component first for best performance.
---@param w    World
---@param ...  string  component names (use C.Name constants)
---@return     integer[]
function World.query(w, ...)
    local components = { ... }
    local result     = {}
    local first      = w[components[1]]
    if not first then return result end

    for id in pairs(first) do
        local match = true
        for i = 2, #components do
            if not w[components[i]][id] then
                match = false
                break
            end
        end
        if match then result[#result + 1] = id end
    end
    table.sort(result)
    return result
end

-- SAVE STATE ------------------------
---@param comp table
---@return table
local function copyFlat(comp)
    local copy = {}
    for k, v in pairs(comp) do
        copy[k] = v
    end
    return copy
end

---@param comp table
---@return table
local function copyAnimation(comp)
    return {
        frames    = comp.frames,
        current   = comp.current,
        timer     = comp.timer,
        duration  = comp.duration,
        isPlaying = comp.isPlaying,
        angle     = comp.angle,
        flipY     = comp.flipY,
    }
end

---@param comp table
---@return table
local function copyInput(comp)
    local history = {}
    for i, entry in ipairs(comp.inputHistory) do
        history[i] = {
            up       = entry.up,
            dn       = entry.dn,
            lt       = entry.lt,
            rt       = entry.rt,
            fire     = entry.fire,
            reload   = entry.reload,
            aimAngle = entry.aimAngle,
        }
    end
    return {
        up           = comp.up,
        dn           = comp.dn,
        lt           = comp.lt,
        rt           = comp.rt,
        fire         = comp.fire,
        reload       = comp.reload,
        aimAngle     = comp.aimAngle,
        inputHistory = history,
        historySize  = comp.historySize,
    }
end

local SPECIAL_COPIERS = {
    animation = copyAnimation,
    input     = copyInput,
}

---@param w World
---@return table
function World.saveState(w)
    local snap = {
        nextId   = w.nextId,
        rngState = w.rng:getState(),
        entities = {},
    }

    for id in pairs(w.entities) do
        snap.entities[id] = true
    end

    for _, name in pairs(C.Name) do
        local src    = w[name]
        local dst    = {}
        local copier = SPECIAL_COPIERS[name] or copyFlat
        for id, comp in pairs(src) do
            dst[id] = copier(comp)
        end
        snap[name] = dst
    end

    return snap
end

-- END SAVE STATE ------------------------

return World
