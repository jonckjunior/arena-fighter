FIXED_DT          = 1 / 60

local World       = require "world"
local Systems     = require "systems"
local Spawners    = require "spawners"
local Lockstep    = require "lockstep"

local accumulator = 0
local DEBUG       = false
local world
local canvas

-- Toggle this to test networking. When false: pure local, myIndex = 1.
local USE_NETWORK = true
local RELAY_HOST  = "localhost" -- change to relay machine's IP for remote play
local RELAY_PORT  = 22122

local myIndex     = 1   -- overwritten by Lockstep.connect() when USE_NETWORK = true
local ls          = nil -- LockstepState, set in love.load when USE_NETWORK = true

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.window.setTitle("Hello World")
    gameWidth, gameHeight = 480, 270
    scaleFactor = 3
    love.window.setMode(gameWidth * scaleFactor, gameHeight * scaleFactor)

    canvas = love.graphics.newCanvas(gameWidth, gameHeight)
    canvas:setFilter("nearest", "nearest")

    -- Connect before spawning — myIndex determines which player we control.
    if USE_NETWORK then
        ls      = Lockstep.connect(RELAY_HOST, RELAY_PORT)
        myIndex = ls.myIndex
    end

    world = World.new()
    Spawners.player(world, 100, 100, 1)
    Spawners.player(world, 300, 100, 2)
    local gunOwner = 1 -- give gun to p1 for now
    for id, pidx in pairs(world.playerIndex) do
        if pidx.index == gunOwner then
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

    -- Drain all pending packets once per frame, before the tick loop.
    if USE_NETWORK then
        Lockstep.receive(ls)
    end

    while accumulator >= FIXED_DT do
        -- Gather local keyboard state for all players (local mode uses both;
        -- networked mode only our own matters — remote gets overwritten below).
        local frameInputs = {
            [1] = Systems.gatherLocalInput(1),
            [2] = Systems.gatherLocalInput(2),
        }

        -- Our player's aim angle comes from the local mouse.
        -- fillAimAngles sets all players, but remote will be overwritten next.
        Systems.fillAimAngles(frameInputs, world)

        if USE_NETWORK then
            -- Replace the remote player's input with whatever arrived from the relay.
            -- Falls back to neutral (standing still, not firing) if nothing yet.
            local remoteIndex = myIndex == 1 and 2 or 1
            frameInputs[remoteIndex] = ls.remoteInputs[remoteIndex] or {
                up = false,
                dn = false,
                lt = false,
                rt = false,
                fire = false,
                aimAngle = 0,
            }

            -- Send our input after aim angle is filled in.
            Lockstep.send(ls, frameInputs[myIndex])
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

    -- Debug: show which player we are when networking is active
    if USE_NETWORK then
        love.graphics.print("Player " .. myIndex, 4, 4)
    end
end

function love.keypressed(key)
    if key == "f1" then DEBUG = not DEBUG end
    if key == "escape" then love.event.quit() end
end
