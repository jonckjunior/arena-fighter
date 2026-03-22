local C                = require "components"
local STANDARD_GRAVITY = 600

---@class World
---@field nextId number
---@field STANDARD_GRAVITY number
---@field entities table<integer, boolean>
---@field position table<integer, {x: number, y: number, px: number, py: number}>
---@field velocity table<integer, {dx: number, dy: number}>
---@field animation table<integer, {frames: table, current: number, timer: number, duration: number, isPlaying: boolean, angle: number | nil, flipY: integer | nil}>
---@field input table<integer, {prevUp:boolean, up: boolean, dn: boolean, lt: boolean, rt: boolean, fire: boolean, aimAngle: number}>
---@field speed table<integer, {value: number}>
---@field facing table<integer, {dir: number}>
---@field solid table
---@field collider table<integer, {shape: "circle"|"rect", radius: number|nil, w: number|nil, h: number|nil}>
---@field gun table<integer, {cooldown: number, maxCooldown: number, damage: number, bulletSpeed: number}>
---@field bullet table<integer, {ownerId: integer, damage: number, graceFrames: integer}>
---@field lifetime table<integer, {ttl: number}>
---@field equippedBy table<integer, {ownerId: integer}>
---@field drawLayer table<integer, {layer: integer}>
---@field playerIndex table<integer, {index: integer}>
---@field hp table<integer, {current: number, max: number}>
---@field soundEvent table<integer, {soundPath: string, x: number, y: number, playerIndex: integer}>
---@field shakeEvent table<integer, {intensity: number, duration: number, playerIndex: integer}>
---@field gravity table<integer, {g: number}>
---@field grounded table<integer, {value: boolean}>
---@field jumpTimers table<integer, {coyoteTime: number, jumpBuffer: number}>
---@field map love.Image
---@field mapWidth  number
---@field mapHeight number
local World            = {}

---Creates a new world with all its components
---@return World
function World.new()
    local w = {
        nextId           = 1,
        entities         = {},
        STANDARD_GRAVITY = STANDARD_GRAVITY
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

return World
