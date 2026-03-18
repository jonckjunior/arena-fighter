local World       = require "world"
local Systems     = require "systems"
local Spawners    = require "spawners"
local Lockstep    = require "lockstep"
local Utils       = require "utils"
local C           = require "components"

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
local camera      = { x = 0, y = 0, look_speed = 8, look_ahead = 0.2 }

-- ── Private ───────────────────────────────────────────────────────────────────


local function updateCamera(w, targetIndex, cx, cy, dt)
    local pid = Utils.find(
        World.query(w, C.Name.playerIndex, C.Name.position),
        function(id) return w.playerIndex[id].index == targetIndex end
    )
    if not pid then return end
    local px = w.position[pid].x
    local py = w.position[pid].y

    local targetX = px + (cx - px) * camera.look_ahead - 240
    local targetY = py + (cy - py) * camera.look_ahead - 135

    local t = 1 - math.exp(-camera.look_speed * dt)
    camera.x = camera.x + (targetX - camera.x) * t
    camera.y = camera.y + (targetY - camera.y) * t
end

local function initializeWorld()
    local w = World.new()
    Spawners.player(w, 100, 100, 1)
    Spawners.player(w, 300, 100, 2)
    for id, pidx in pairs(w.playerIndex) do
        Spawners.gun(w, id, "pistol")
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

    cursor.x = love.mouse.getX() / SCALE_FACTOR + camera.x
    cursor.y = love.mouse.getY() / SCALE_FACTOR + camera.y

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
        updateCamera(world, myIndex, cursor.x, cursor.y, dt)

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
    love.graphics.push()
    love.graphics.translate(-camera.x, -camera.y)
    Systems.draw(world)
    Systems.drawHpBars(world)
    love.graphics.pop()
    if cursor.sprite then
        local sx = love.mouse.getX() / SCALE_FACTOR
        local sy = love.mouse.getY() / SCALE_FACTOR
        love.graphics.draw(cursor.sprite, sx, sy, 0, 1, 1,
            Utils.round(cursor.sprite:getWidth() / 2),
            Utils.round(cursor.sprite:getHeight() / 2))
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
