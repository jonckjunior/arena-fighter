local World       = require "world"
local Systems     = require "systems"

local world
local canvas

local FIXED_DT    = 1 / 60
local accumulator = 0

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
end

function love.update(dt)
    dt = math.min(dt, 0.1)
    accumulator = accumulator + dt

    while accumulator >= FIXED_DT do
        Systems.gatherInput(world)
        Systems.movement(world, dt)
        Systems.collisionResolution(world)
        Systems.animation(world, dt)
        accumulator = accumulator - FIXED_DT
    end
end

function love.draw()
    love.graphics.setCanvas(canvas)
    love.graphics.clear()
    Systems.draw(world)
    love.graphics.setCanvas()
    love.graphics.draw(canvas, 0, 0, 0, 3, 3)
end
