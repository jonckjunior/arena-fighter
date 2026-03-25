SCALE_FACTOR       = 3
VIEWPORT_W         = 480
VIEWPORT_H         = 270

local Game         = require "game"
local LaunchConfig = require "launch_config"
local SHandleInput = require "systems/systems_handle_input"
local Runtime      = require "systems/systems_present_runtime"
local canvas
---@type GameInstance
local game
DEBUG              = false

---@class RawInput
---@field w boolean
---@field a boolean
---@field s boolean
---@field d boolean
---@field u boolean
---@field h boolean
---@field j boolean
---@field k boolean
---@field r boolean
---@field space boolean
---@field leftMouse boolean
---@field mouseX number
---@field mouseY number

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.window.setTitle("Arena Fighter")
    love.window.setMode(VIEWPORT_W * SCALE_FACTOR, VIEWPORT_H * SCALE_FACTOR)

    canvas = love.graphics.newCanvas(VIEWPORT_W, VIEWPORT_H)
    canvas:setFilter("nearest", "nearest")

    love.mouse.setVisible(false)
    Runtime.init()

    game = Game.new(LaunchConfig.buildGameConfig())
    game:setHooks(Runtime.createGameHooks(game))
    game:load()
end

---@return RawInput
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
        mouseX    = love.mouse.getX() / SCALE_FACTOR,
        mouseY    = love.mouse.getY() / SCALE_FACTOR,
    }
end

function love.update(dt)
    if not game then return end
    local rawInput = grabInput()
    local targetX, targetY = Runtime.getMouseWorldPosition(rawInput)
    local frameInputs = SHandleInput.getGameplayInput(game, rawInput, targetX, targetY)

    game:update(dt, frameInputs)
    Runtime.updatePresentationCursor(rawInput, targetX, targetY)
    Runtime.updatePresentationCamera(game:getWorld(), game:getLocalPlayerIndex(), targetX, targetY, dt)
end

function love.draw()
    if not game then return end
    Runtime.drawGame(game, canvas)
end

function love.keypressed(key)
    if key == "f1" then DEBUG = not DEBUG end
    if key == "escape" then love.event.quit() end
end
