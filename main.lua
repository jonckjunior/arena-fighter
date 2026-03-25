SCALE_FACTOR = 3
VIEWPORT_W   = 480
VIEWPORT_H   = 270

local Game   = require "game"
local canvas
DEBUG        = false
MONKEY_PATCH = false

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.window.setTitle("Arena Fighter")
    love.window.setMode(VIEWPORT_W * SCALE_FACTOR, VIEWPORT_H * SCALE_FACTOR)

    canvas = love.graphics.newCanvas(VIEWPORT_W, VIEWPORT_H)
    canvas:setFilter("nearest", "nearest")

    love.mouse.setVisible(false)

    if MONKEY_PATCH then
        Game.runHeadlessTest(10000)
        return
    end

    Game.load()
end

local function grabInput()
    return {
        w         = love.keyboard.isDown("w"),
        a         = love.keyboard.isDown("a"),
        s         = love.keyboard.isDown("s"),
        d         = love.keyboard.isDown("d"),
        u         = love.keyboard.isDown("u"),
        h         = love.keyboard.isDown("h"),
        j         = love.keyboard.isDown("j"),
        k         = love.keyboard.isDown("k"),
        r         = love.keyboard.isDown("r"),
        space     = love.keyboard.isDown("space"),
        leftMouse = love.mouse.isDown(1),
    }
end

function love.update(dt)
    Game.update(dt, grabInput())
end

function love.draw()
    Game.draw(canvas)
end

function love.keypressed(key)
    if key == "f1" then DEBUG = not DEBUG end
    if key == "escape" then love.event.quit() end
end
