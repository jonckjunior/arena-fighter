---@class World
---@field nextId number
---@field entities table<number, boolean>
---@field position table<number, {x: number, y: number}>
---@field velocity table<number, {dx: number, dy: number}>
---@field animation table<number, {frames: table, current: number, timer: number, duration: number, isPlaying: boolean}>
---@field input table<number, {up: boolean, dn: boolean, lt: boolean, rt: boolean}>
---@field speed table<number, {value: number}>
---@field facing table<number, {dir: number}>
---@field solid table
---@field collider table<number, {radius: number}>
local World = {}

---Creates a new world with all its components
---@return table
function World.new()
    return {
        nextId    = 1,
        entities  = {},
        -- components
        position  = {},            -- { x, y }
        velocity  = {},            -- { dx, dy }
        animation = {},            -- { frames, current, timer, duration, isPlaying }
        input     = {},            -- { up, dn, lt, rt }
        speed     = {},            -- { value }
        facing    = {},            -- { dir }
        solid     = {},            -- {}
        collider  = { radius = 8 } -- { radius }
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

---Creates a new player and returns its id
---@param w World
---@param x integer
---@param y integer
---@return integer
function World.spawnPlayer(w, x, y)
    local id        = World.newEntity(w)
    w.position[id]  = { x = x, y = y }
    w.velocity[id]  = { dx = 0, dy = 0 }
    w.speed[id]     = { value = 120 }
    w.input[id]     = { up = false, dn = false, lt = false, rt = false }
    w.animation[id] = {
        frames    = {
            love.graphics.newImage("Assets/Sprites/Players/Tiles/tile_0000.png"),
            love.graphics.newImage("Assets/Sprites/Players/Tiles/tile_0001.png"),
            love.graphics.newImage("Assets/Sprites/Players/Tiles/tile_0002.png"),
        },
        current   = 1,
        timer     = 0,
        duration  = 0.05,
        isPlaying = false,
    }
    w.facing[id]    = { dir = 1 } -- 1 = right, -1 = left
    w.collider[id]  = { radius = 9 }
    return id
end

---Creates a barrel.
---@param w World
---@param x integer
---@param y integer
---@return integer
function World.spawnBarrel(w, x, y)
    local id        = World.newEntity(w)
    w.position[id]  = { x = x, y = y }
    w.collider[id]  = { radius = 9 }
    w.solid[id]     = true -- tag: no data needed
    w.animation[id] = {
        frames = { love.graphics.newImage("Assets/Sprites/Tiles/Tiles/tile_0222.png") },
        current = 1,
        timer = 0,
        duration = 0.1,
        isPlaying = false,
    }
    return id
end

return World
