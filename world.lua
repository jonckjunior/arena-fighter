local C               = require "components"
local Rng             = require "rng"

local HASH_PRIME      = 31
local HASH_MODULO     = 2147483647

---@class World
---@field nextId number
---@field entities table<integer, boolean>
---@field position table<integer, {x: number, y: number, px: number, py: number}>
---@field velocity table<integer, {dx: number, dy: number}>
---@field animation table<integer, {frameIds: string[], current: number, timer: number, duration: number, isPlaying: boolean, angle: number | nil, flipY: integer | nil}>
---@field input table<integer, {up: boolean, dn: boolean, lt: boolean, rt: boolean, fire: boolean, reload: boolean, aimAngle: number, inputHistory: table[], historySize: integer}>
---@field speed table<integer, {value: number}>
---@field facing table<integer, {dir: number}>
---@field solid table<integer, {}>
---@field collider table<integer, {shape: "circle"|"rect", radius: number|nil, w: number|nil, h: number|nil, ox: integer, oy: integer}>
---@field gun table<integer, {cooldown: number, maxCooldown: number, damage: number, bulletSpeed: number, spread: number, bulletCount: integer, isReloading: boolean, reloadTime: number, reloadTimer: number, maxAmmo: integer, currentAmmo: integer, muzzleOffsetX: integer, muzzleOffsetY: integer}>
---@field bullet table<integer, {ownerId: integer, damage: number, graceFrames: integer}>
---@field lifetime table<integer, {ttl: number}>
---@field equippedBy table<integer, {ownerId: integer}>
---@field drawLayer table<integer, {layer: integer}>
---@field playerIndex table<integer, {index: integer}>
---@field hp table<integer, {current: number, max: number}>
---@field gravity table<integer, {g: number}>
---@field grounded table<integer, {value: boolean, wallDir: integer, framesSinceGrounded: integer, framesSinceJump: integer, framesSinceWall: integer, lastWallDir: integer}>
---@field presentationEffects {sounds: {soundPath: string, x: number, y: number, playerIndex: integer|nil}[], shakes: {intensity: number, duration: number, playerIndex: integer|nil}[]}
---@field rng Rng
---@field mapAssetId string|nil
---@field mapWidth  number
---@field mapHeight number
local World           = {}

local COMPONENT_NAMES = {}
for _, name in pairs(C.Name) do
    COMPONENT_NAMES[#COMPONENT_NAMES + 1] = name
end
table.sort(COMPONENT_NAMES)

---Creates a new world with all its components.
---@return World
function World.new()
    local w = {
        nextId              = 1,
        entities            = {},
        presentationEffects = { sounds = {}, shakes = {} },
        rng                 = Rng.new(12345),
        mapAssetId          = nil,
        mapWidth            = 0,
        mapHeight           = 0,
    }
    for _, name in pairs(C.Name) do
        -- LuaLS thinks that C.Name could be rng so it complains, so I'm disabling it.
        ---@diagnostic disable-next-line: missing-fields
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
    for _, name in pairs(C.Name) do
        w[name][id] = nil
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
    local frameIds = {}
    for i, frameId in ipairs(comp.frameIds) do
        frameIds[i] = frameId
    end

    return {
        frameIds  = frameIds,
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

---@param src table
---@return table
local function copyEntities(src)
    local dst = {}
    for id in pairs(src) do
        dst[id] = true
    end
    return dst
end

---@param src table|nil
---@param specialName string|nil
---@return table
local function copyComponentTable(src, specialName)
    local dst = {}
    if not src then
        return dst
    end

    local copier = SPECIAL_COPIERS[specialName] or copyFlat
    for id, comp in pairs(src) do
        dst[id] = copier(comp)
    end
    return dst
end

local function clearComponents(w)
    for _, name in ipairs(COMPONENT_NAMES) do
        w[name] = {}
    end
end

---@param value any
---@return integer
local function keySortRank(value)
    local valueType = type(value)
    if valueType == "number" then return 1 end
    if valueType == "string" then return 2 end
    if valueType == "boolean" then return 3 end
    if valueType == "nil" then return 4 end
    return 5
end

---@param value any
---@return string
local function normalizeNumber(value)
    return string.format("%.17g", value)
end

---@param tbl table
---@return integer[]
---@return table[]
local function sortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl) do
        keys[#keys + 1] = key
    end

    table.sort(keys, function(a, b)
        local rankA = keySortRank(a)
        local rankB = keySortRank(b)
        if rankA ~= rankB then
            return rankA < rankB
        end

        local typeA = type(a)
        if typeA == "number" then
            return a < b
        end
        if typeA == "string" then
            return a < b
        end
        if typeA == "boolean" then
            return (a and 1 or 0) < (b and 1 or 0)
        end
        return tostring(a) < tostring(b)
    end)

    return keys
end

---@param hash integer
---@param value integer
---@return integer
local function hashInt(hash, value)
    return (hash * HASH_PRIME + (value % HASH_MODULO)) % HASH_MODULO
end

---@param hash integer
---@param text string
---@return integer
local function hashString(hash, text)
    hash = hashInt(hash, #text)
    for i = 1, #text do
        hash = hashInt(hash, string.byte(text, i))
    end
    return hash
end

---@param hash integer
---@param value any
---@return integer
local function hashValue(hash, value)
    local valueType = type(value)

    if valueType == "nil" then
        return hashInt(hash, 1)
    end

    if valueType == "boolean" then
        hash = hashInt(hash, 2)
        return hashInt(hash, value and 1 or 0)
    end

    if valueType == "number" then
        hash = hashInt(hash, 3)
        return hashString(hash, normalizeNumber(value))
    end

    if valueType == "string" then
        hash = hashInt(hash, 4)
        return hashString(hash, value)
    end

    if valueType == "table" then
        local keys = sortedKeys(value)
        hash = hashInt(hash, 5)
        hash = hashInt(hash, #keys)
        for _, key in ipairs(keys) do
            hash = hashValue(hash, key)
            hash = hashValue(hash, value[key])
        end
        return hash
    end

    error("Unsupported snapshot value type: " .. valueType)
end

---@param w World
---@return table
function World.saveState(w)
    local snap = {
        nextId     = w.nextId,
        rngState   = w.rng:getState(),
        entities   = {},
        mapAssetId = w.mapAssetId,
        mapWidth   = w.mapWidth,
        mapHeight  = w.mapHeight,
    }

    snap.entities = copyEntities(w.entities)

    for _, name in ipairs(COMPONENT_NAMES) do
        snap[name] = copyComponentTable(w[name], name)
    end

    return snap
end

---@param w World
---@param snapshot table
function World.writeState(w, snapshot)
    w.nextId = snapshot.nextId or 1
    w.entities = copyEntities(snapshot.entities or {})
    w.mapAssetId = snapshot.mapAssetId
    w.mapWidth = snapshot.mapWidth or 0
    w.mapHeight = snapshot.mapHeight or 0

    if w.rng and w.rng.setState then
        w.rng:setState(snapshot.rngState)
    else
        w.rng = Rng.new(snapshot.rngState)
    end

    clearComponents(w)
    for _, name in ipairs(COMPONENT_NAMES) do
        w[name] = copyComponentTable(snapshot[name], name)
    end
    w.presentationEffects = { sounds = {}, shakes = {} }
end

---@param snapshot table
---@return integer
function World.hashState(snapshot)
    return hashValue(0, snapshot)
end

-- END SAVE STATE ------------------------

---@param w World
function World.discardPresentationEvents(w)
    w.presentationEffects = { sounds = {}, shakes = {} }
end

return World
