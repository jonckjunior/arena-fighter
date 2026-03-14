FIXED_DT          = 1 / 60

local World       = require "world"
local Systems     = require "systems"
local Spawners    = require "spawners"
local accumulator = 0
local DEBUG       = false
local world
local canvas

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.window.setTitle("Hello World")
    gameWidth, gameHeight = 480, 270
    scaleFactor = 3
    love.window.setMode(gameWidth * scaleFactor, gameHeight * scaleFactor)

    canvas = love.graphics.newCanvas(gameWidth, gameHeight)
    canvas:setFilter("nearest", "nearest")

    world = World.new()
    local pid = Spawners.player(world, 100, 100)
    Spawners.gun(world, pid, "ak47")
    Spawners.barrel(world, 200, 150)
    Spawners.barrel(world, 216, 150)

    -- capture mouse for cursor
    love.mouse.setVisible(false)
    cursor = {
        sprite = love.graphics.newImage("Assets/Sprites/Weapons/Tiles/tile_0024.png"),
        pos    = { x = 0, y = 0 }
    }
end

function love.update(dt)
    dt = math.min(dt, 0.1)
    accumulator = accumulator + dt

    cursor.pos.x, cursor.pos.y = love.mouse.getPosition()
    cursor.pos.x = cursor.pos.x / scaleFactor
    cursor.pos.y = cursor.pos.y / scaleFactor

    while accumulator >= FIXED_DT do
        Systems.gatherInput(world)
        Systems.gunCooldown(world)
        Systems.firing(world)
        Systems.inputToMovement(world, FIXED_DT)
        Systems.applyVelocity(world, FIXED_DT)
        Systems.gunFollow(world)
        Systems.collisionResolution(world)
        Systems.animation(world, FIXED_DT)
        Systems.lifetime(world)
        accumulator = accumulator - FIXED_DT
    end
end

function love.draw()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.2, 0.2, 0.2)
    Systems.draw(world)
    love.graphics.draw(cursor.sprite, cursor.pos.x, cursor.pos.y)
    love.graphics.setCanvas()
    love.graphics.draw(canvas, 0, 0, 0, 3, 3)
end

function love.keypressed(key)
    if key == "f1" then
        DEBUG = not DEBUG
    end

    if key == "escape" then
        love.event.quit()
    end
end
