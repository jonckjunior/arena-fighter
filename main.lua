SCALE_FACTOR      = 3
local FIXED_DT    = 1 / 60

local World       = require "world"
local Systems     = require "systems"
local Spawners    = require "spawners"
local Lockstep    = require "lockstep"

local accumulator = 0
local DEBUG       = false
local gameWidth   = 480
local gameHeight  = 270

local world
local canvas
local cursor

local USE_NETWORK = false
local RELAY_HOST  = "localhost"
local RELAY_PORT  = 22122
local NUM_PLAYERS = 2
local INPUT_DELAY = 10

local myIndex     = 1
---@type LockstepState
local ls          = nil

---@type "waiting"|"playing"|"roundOver"
local gameState   = "waiting"
---@type integer|false|nil
local roundWinner = nil -- entity id, false = draw, nil = not decided

local waitTimer   = 3.0 -- seconds before round starts

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function updateCursor()
    cursor.pos.x, cursor.pos.y = love.mouse.getPosition()
    cursor.pos.x = cursor.pos.x / SCALE_FACTOR
    cursor.pos.y = cursor.pos.y / SCALE_FACTOR
end

local function initializeWorld()
    local w = World.new()
    Spawners.player(w, 100, 100, 1)
    Spawners.player(w, 300, 100, 2)
    for id, pidx in pairs(w.playerIndex) do
        if pidx.index == 1 then
            Spawners.gun(w, id, "ak47")
            break
        end
    end
    Spawners.barrel(w, 200, 150)
    Spawners.barrel(w, 216, 150)
    return w
end

local function startRound()
    world       = initializeWorld()
    gameState   = "waiting"
    roundWinner = nil
    waitTimer   = 3.0
end

-- ── Love2D callbacks ──────────────────────────────────────────────────────────

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.window.setTitle("Arena Fighter")
    love.window.setMode(gameWidth * SCALE_FACTOR, gameHeight * SCALE_FACTOR)

    canvas = love.graphics.newCanvas(gameWidth, gameHeight)
    canvas:setFilter("nearest", "nearest")

    if USE_NETWORK then
        ls      = Lockstep.connect(RELAY_HOST, RELAY_PORT, NUM_PLAYERS, INPUT_DELAY)
        myIndex = ls.myIndex
        Lockstep.bootstrap(ls)
    end

    love.mouse.setVisible(false)
    cursor = {
        sprite = love.graphics.newImage("Assets/Sprites/Weapons/Tiles/tile_0024.png"),
        pos    = { x = 0, y = 0 }
    }

    startRound()
end

function love.update(dt)
    dt = math.min(dt, 0.1)

    updateCursor()

    -- Waiting countdown runs in real time, not fixed tick
    if gameState == "waiting" then
        waitTimer = waitTimer - dt
        if waitTimer <= 0 then
            gameState = "playing"
        end
        return
    end

    if USE_NETWORK then
        Lockstep.receive(ls)
    end

    accumulator = accumulator + dt

    while accumulator >= FIXED_DT do
        if gameState ~= "playing" then
            accumulator = accumulator - FIXED_DT
            goto continueAccumulator
        end

        local frameInputs
        if USE_NETWORK then
            local myInput = Systems.gatherLocalInput()
            Systems.fillAimAngleForPlayer(myInput, myIndex, world)
            frameInputs = Lockstep.tick(ls, myInput)
            if not frameInputs then break end -- Not ready for this frame yet, wait for more input packets to arrive
        else
            frameInputs = { [1] = Systems.gatherLocalInput() }
            Systems.fillAimAngles(frameInputs, world)
        end

        Systems.runSystems(world, frameInputs, FIXED_DT)

        local result = Systems.checkWin(world)
        if result then
            gameState   = "roundOver"
            roundWinner = result.winner or false -- false = draw, id = winner
        end

        accumulator = accumulator - FIXED_DT
        ::continueAccumulator::
    end
end

function love.draw()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.2, 0.2, 0.2)
    Systems.draw(world)
    Systems.drawHpBars(world)
    love.graphics.draw(cursor.sprite, cursor.pos.x, cursor.pos.y)
    love.graphics.setCanvas()

    love.graphics.draw(canvas, 0, 0, 0, SCALE_FACTOR, SCALE_FACTOR)

    -- Network debug HUD
    if USE_NETWORK then
        local stall = ls.stalledFrames > 0 and "  STALLED x" .. ls.stalledFrames or ""
        love.graphics.print("P" .. myIndex .. "  f=" .. ls.frame .. stall, 4, 4)
    end

    -- Overlays (drawn at screen resolution)
    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()

    if gameState == "waiting" then
        local secs = math.ceil(waitTimer)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(secs > 0 and tostring(secs) or "Fight!", 0, sh / 2 - 8, sw, "center")
        love.graphics.setColor(1, 1, 1)
    elseif gameState == "roundOver" then
        local text
        if roundWinner then
            local pidx = world.playerIndex[roundWinner]
            text = pidx and ("Player " .. pidx.index .. " wins!") or "Winner!"
        else
            text = "Draw!"
        end
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 0, 0, sw, sh)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(text, 0, sh / 2 - 16, sw, "center")
        love.graphics.printf("Press R to play again", 0, sh / 2 + 8, sw, "center")
        love.graphics.setColor(1, 1, 1)
    end
end

function love.keypressed(key)
    if key == "f1" then DEBUG = not DEBUG end
    if key == "escape" then love.event.quit() end
    if key == "r" and gameState == "roundOver" then startRound() end
end
