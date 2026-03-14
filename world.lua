---@class World
---@field nextId number
---@field entities table<integer, boolean>
---@field position table<integer, {x: number, y: number}>
---@field velocity table<integer, {dx: number, dy: number}>
---@field animation table<integer, {frames: table, current: number, timer: number, duration: number, isPlaying: boolean}>
---@field input table<integer, {up: boolean, dn: boolean, lt: boolean, rt: boolean, fire: boolean, aimAngle: number}>
---@field speed table<integer, {value: number}>
---@field facing table<integer, {dir: number}>
---@field solid table
---@field collider table<integer, {radius: number}>
---@field gun table<integer, {cooldown: number, maxCooldown: number, damage: number, bulletSpeed: number}>
---@field bullet table<integer, {ownerId: integer, damage: number}>
---@field lifetime table<integer, {ttl: number}>
---@field equippedBy table<integer, {ownerId: integer}>
---@field drawLayer table<integer, {layer: integer}>
---@field playerIndex table<integer, {index: integer}>
local World = {}

---Creates a new world with all its components
---@return table
function World.new()
    return {
        nextId      = 1,
        entities    = {},
        -- components
        position    = {}, -- { x, y }
        velocity    = {}, -- { dx, dy }
        animation   = {}, -- { frames, current, timer, duration, isPlaying }
        input       = {}, -- { up, dn, lt, rt, fire, aimAngle}
        speed       = {}, -- { value }
        facing      = {}, -- { dir }
        solid       = {}, -- {}
        collider    = {}, -- { radius }
        gun         = {}, -- { cooldown, maxCooldown, damage, bulletSpeed }
        bullet      = {}, -- { ownerId, damage }
        lifetime    = {}, -- { ttl }
        equippedBy  = {}, -- { ownerId }
        drawLayer   = {}, -- { layer }
        playerIndex = {}, -- { index }
    }
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
    -- Remove from every component table
    for _, t in pairs(w) do
        if type(t) == "table" then t[id] = nil end
    end
end

return World
