FIXED_DT          = 1 / 60

local World       = require "world"
local Systems     = require "systems"
local Spawners    = require "spawners"
local Lockstep    = require "lockstep"

local accumulator = 0
local DEBUG       = false
local world
local canvas

local USE_NETWORK = true
local RELAY_HOST  = "localhost"
local RELAY_PORT  = 22122
local NUM_PLAYERS = 2
local INPUT_DELAY = 10

local myIndex     = 1
local ls          = nil

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.window.setTitle("Hello World")
    gameWidth, gameHeight = 480, 270
    scaleFactor = 3
    love.window.setMode(gameWidth * scaleFactor, gameHeight * scaleFactor)

    canvas = love.graphics.newCanvas(gameWidth, gameHeight)
    canvas:setFilter("nearest", "nearest")

    if USE_NETWORK then
        ls      = Lockstep.connect(RELAY_HOST, RELAY_PORT, NUM_PLAYERS, INPUT_DELAY)
        myIndex = ls.myIndex
        Lockstep.bootstrap(ls)
    end

    world = World.new()
    Spawners.player(world, 100, 100, 1)
    Spawners.player(world, 300, 100, 2)
    for id, pidx in pairs(world.playerIndex) do
        if pidx.index == 1 then
            Spawners.gun(world, id, "ak47")
            break
        end
    end
    Spawners.barrel(world, 200, 150)
    Spawners.barrel(world, 216, 150)

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

    if USE_NETWORK then
        Lockstep.receive(ls)
    end

    while accumulator >= FIXED_DT do
        local frameInputs

        if USE_NETWORK then
            local myInput = Systems.gatherLocalInput(myIndex)
            Systems.fillAimAngleForPlayer(myInput, myIndex, world)
            Lockstep.send(ls, myInput)

            if not Lockstep.ready(ls) then
                ls.stalledFrames = ls.stalledFrames + 1
                break
            end
            ls.stalledFrames = 0

            frameInputs = Lockstep.consume(ls)
        else
            frameInputs = {
                [1] = Systems.gatherLocalInput(1),
                [2] = Systems.gatherLocalInput(2),
            }
            Systems.fillAimAngles(frameInputs, world)
        end

        Systems.applyInputs(world, frameInputs)
        Systems.gunCooldown(world)
        Systems.gunFollow(world)
        Systems.firing(world)
        Systems.inputToMovement(world, FIXED_DT)
        Systems.applyVelocity(world, FIXED_DT)
        Systems.bulletTerrainCollision(world)
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
    love.graphics.draw(canvas, 0, 0, 0, scaleFactor, scaleFactor)

    if USE_NETWORK then
        local stall = ls.stalledFrames > 0 and "  STALLED x" .. ls.stalledFrames or ""
        love.graphics.print("P" .. myIndex .. "  f=" .. ls.frame .. stall, 4, 4)
    end
end

function love.keypressed(key)
    if key == "f1" then DEBUG = not DEBUG end
    if key == "escape" then love.event.quit() end
end
