local World       = require "world"
local Systems     = require "systems"
local Spawners    = require "spawners"
local Lockstep    = require "lockstep"

local Game        = {}

-- ── Network config ────────────────────────────────────────────────────────────

Game.USE_NETWORK  = false
Game.RELAY_HOST   = "localhost"
Game.RELAY_PORT   = 22122
Game.NUM_PLAYERS  = 2
Game.INPUT_DELAY  = 10

-- ── State ─────────────────────────────────────────────────────────────────────

local FIXED_DT    = 1 / 60

local world
local accumulator = 0

local myIndex     = 1
---@type LockstepState
local ls          = nil

---@type "waiting"|"playing"|"roundOver"
local gameState   = "waiting"
---@type integer|false|nil
local roundWinner = nil
local waitTimer   = 0.1

local cursor      = { sprite = nil, x = 0, y = 0 }

-- ── Private ───────────────────────────────────────────────────────────────────

local function initializeWorld()
    local w = World.new()
    Spawners.player(w, 100, 100, 1)
    Spawners.player(w, 300, 100, 2)
    for id, pidx in pairs(w.playerIndex) do
        Spawners.gun(w, id, "ak47")
    end
    Spawners.barrel(w, 200, 150)
    Spawners.barrel(w, 216, 150)
    return w
end

local function startRound()
    world       = initializeWorld()
    gameState   = "waiting"
    roundWinner = nil
    waitTimer   = 0.1
end

-- ── Public API ────────────────────────────────────────────────────────────────

function Game.load()
    cursor.sprite = love.graphics.newImage("Assets/Sprites/Weapons/Tiles/tile_0024.png")

    if Game.USE_NETWORK then
        ls      = Lockstep.connect(Game.RELAY_HOST, Game.RELAY_PORT, Game.NUM_PLAYERS, Game.INPUT_DELAY)
        myIndex = ls.myIndex
        Lockstep.bootstrap(ls)
    end

    startRound()
end

function Game.update(dt)
    dt = math.min(dt, 0.1)

    cursor.x = love.mouse.getX() / SCALE_FACTOR
    cursor.y = love.mouse.getY() / SCALE_FACTOR

    if gameState == "waiting" then
        waitTimer = waitTimer - dt
        if waitTimer <= 0 then
            gameState = "playing"
        end
        return
    end

    if Game.USE_NETWORK then
        Lockstep.receive(ls)
    end

    accumulator = accumulator + dt

    while accumulator >= FIXED_DT do
        if gameState ~= "playing" then
            accumulator = accumulator - FIXED_DT
            goto continueAccumulator
        end

        local frameInputs
        if Game.USE_NETWORK then
            local myInput = Systems.gatherLocalInput(myIndex, world, cursor.x, cursor.y)
            frameInputs = Lockstep.tick(ls, myInput)
            if not frameInputs then break end
        else
            frameInputs = { [1] = Systems.gatherLocalInput(1, world, cursor.x, cursor.y) }
        end

        Systems.runSystems(world, frameInputs, FIXED_DT)

        local result = Systems.checkWin(world)
        if result then
            gameState   = "roundOver"
            roundWinner = result.winner or false
        end

        accumulator = accumulator - FIXED_DT
        ::continueAccumulator::
    end
end

function Game.draw(canvas)
    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()

    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.2, 0.2, 0.2)
    Systems.draw(world)
    Systems.drawHpBars(world)
    if cursor.sprite then
        local hw = cursor.sprite:getWidth() / 2
        local hh = cursor.sprite:getHeight() / 2
        love.graphics.draw(cursor.sprite, cursor.x, cursor.y, 0, 1, 1, hw, hh)
    end
    love.graphics.setCanvas()

    love.graphics.draw(canvas, 0, 0, 0, SCALE_FACTOR, SCALE_FACTOR)

    -- Network debug HUD
    if Game.USE_NETWORK then
        local stall = ls.stalledFrames > 0 and "  STALLED x" .. ls.stalledFrames or ""
        love.graphics.print("P" .. myIndex .. "  f=" .. ls.frame .. stall, 4, 4)
    end

    -- Overlays (drawn at screen resolution so text isn't pixelated)
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

function Game.keypressed(key)
    if key == "r" and gameState == "roundOver" then
        startRound()
    end
end

return Game
