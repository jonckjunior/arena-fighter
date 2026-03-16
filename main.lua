SCALE_FACTOR = 3

local Game   = require "game"
local canvas
local DEBUG  = false

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.window.setTitle("Arena Fighter")
    love.window.setMode(480 * SCALE_FACTOR, 270 * SCALE_FACTOR)

    canvas = love.graphics.newCanvas(480, 270)
    canvas:setFilter("nearest", "nearest")

    love.mouse.setVisible(false)

    Game.load()
end

function love.update(dt)
    Game.update(dt)
end

function love.draw()
    Game.draw(canvas)
end

function love.keypressed(key)
    if key == "f1" then DEBUG = not DEBUG end
    if key == "escape" then love.event.quit() end
    Game.keypressed(key)
end
