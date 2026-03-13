local World       = require "world"
local Systems     = require "systems"

local world
local canvas

local FIXED_DT    = 1 / 60
local accumulator = 0

DEBUG             = false

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.window.setTitle("Hello World")
    gameWidth, gameHeight = 480, 270
    local scale = 3
    love.window.setMode(gameWidth * scale, gameHeight * scale)

    canvas = love.graphics.newCanvas(gameWidth, gameHeight)
    canvas:setFilter("nearest", "nearest")

    world = World.new()
    World.spawnPlayer(world, 100, 100)
    World.spawnBarrel(world, 200, 150)
    World.spawnBarrel(world, 216, 150)

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
    cursor.pos.x = cursor.pos.x / 3
    cursor.pos.y = cursor.pos.y / 3

    while accumulator >= FIXED_DT do
        Systems.gatherInput(world)
        Systems.movement(world, FIXED_DT)
        Systems.collisionResolution(world)
        Systems.animation(world, FIXED_DT)
        accumulator = accumulator - FIXED_DT
    end
end

function love.draw()
    love.graphics.setCanvas(canvas)
    love.graphics.clear()
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
