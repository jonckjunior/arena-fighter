local World    = require "world"
local Systems  = require "systems"
local Spawners = require "spawners"
local Lockstep = require "lockstep"
local Utils    = require "utils"
local C        = require "components"

local Game     = {}
local FIXED_DT = 1 / 60

-- ── Network config ────────────────────────────────────────────────────────────

---@class network
---@field USE_NETWORK boolean
---@field RELAY_HOST nil
---@field RELAY_PORT integer
---@field NUM_PLAYERS integer
---@field INPUT_DELAY integer
---@field myIndex integer
---@field ls LockstepState|nil
local network  = {
    USE_NETWORK = false,
    RELAY_HOST  = "localhost",
    RELAY_PORT  = 22122,
    NUM_PLAYERS = 2,
    INPUT_DELAY = 10,
    myIndex     = 1,
    ls          = nil,
}

-- ── State ─────────────────────────────────────────────────────────────────────
---@class state
---@field world World|nil
---@field accumulator number
---@field gameState "waiting"|"playing"|"roundOver"
---@field roundWinner nil
---@field matchWinner nil
---@field waitTimer number
---@field scores table<integer,integer>
---@field roundNumber integer
local state    = {
    world       = nil,
    accumulator = 0,
    gameState   = "waiting",
    roundWinner = nil,
    matchWinner = nil,
    waitTimer   = 0,
    scores      = {},
    roundNumber = 0,
}

---@class cursor
---@field sprite love.Image|nil
---@field x number
---@field y number
local cursor   = { sprite = nil, x = 0, y = 0 }

---@class camera
---@field x number
---@field y number
---@field look_speed number
---@field look_ahead number
local camera   = { x = 0, y = 0, look_speed = 8, look_ahead = 0.2 }

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
    state.world       = initializeWorld()
    state.gameState   = "waiting"
    state.roundWinner = nil
    state.waitTimer   = 0.1
end

-- ── Public API ────────────────────────────────────────────────────────────────

function Game.load()
    cursor.sprite = love.graphics.newImage("Assets/Sprites/Weapons/Tiles/tile_0024.png")

    if Game.USE_NETWORK then
        network.ls      = Lockstep.connect(Game.RELAY_HOST, Game.RELAY_PORT, Game.NUM_PLAYERS, Game.INPUT_DELAY)
        network.myIndex = network.ls.myIndex
        Lockstep.bootstrap(network.ls)
    end

    startRound()
end

function Game.update(dt)
    dt = math.min(dt, 0.1)

    cursor.x = love.mouse.getX() / SCALE_FACTOR + camera.x
    cursor.y = love.mouse.getY() / SCALE_FACTOR + camera.y

    if state.gameState == "waiting" then
        state.waitTimer = state.waitTimer - dt
        if state.waitTimer <= 0 then
            state.gameState = "playing"
        end
        return
    end

    if Game.USE_NETWORK then
        Lockstep.receive(network.ls)
    end

    state.accumulator = state.accumulator + dt

    while state.accumulator >= FIXED_DT do
        if state.gameState ~= "playing" then
            state.accumulator = state.accumulator - FIXED_DT
            goto continueAccumulator
        end

        local frameInputs
        if Game.USE_NETWORK then
            local myInput = Systems.gatherLocalInput(network.myIndex, state.world, cursor.x, cursor.y)
            frameInputs = Lockstep.tick(network.ls, myInput)
            if not frameInputs then break end
        else
            frameInputs = { [1] = Systems.gatherLocalInput(1, state.world, cursor.x, cursor.y) }
        end

        Systems.runSystems(state.world, frameInputs, FIXED_DT)
        updateCamera(state.world, network.myIndex, cursor.x, cursor.y, dt)

        local result = Systems.checkWin(state.world)
        if result then
            state.gameState   = "roundOver"
            state.roundWinner = result.winner or false
        end

        state.accumulator = state.accumulator - FIXED_DT
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
    Systems.draw(state.world)
    Systems.drawHpBars(state.world)
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
        local stall = network.ls.stalledFrames > 0 and "  STALLED x" .. network.ls.stalledFrames or ""
        love.graphics.print("P" .. network.myIndex .. "  f=" .. network.ls.frame .. stall, 4, 4)
    end

    -- Overlays (drawn at screen resolution so text isn't pixelated)
    if state.gameState == "waiting" then
        local secs = math.ceil(state.waitTimer)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(secs > 0 and tostring(secs) or "Fight!", 0, sh / 2 - 8, sw, "center")
        love.graphics.setColor(1, 1, 1)
    elseif state.gameState == "roundOver" then
        local text
        if state.roundWinner then
            local pidx = state.world.playerIndex[state.roundWinner]
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
    if key == "r" and state.gameState == "roundOver" then
        startRound()
    end
end

return Game
