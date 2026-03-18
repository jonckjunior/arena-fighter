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
---@field networkIndex integer
---@field ls LockstepState|nil
local network  = {}

-- ── State ─────────────────────────────────────────────────────────────────────
---@class state
---@field world World|nil
---@field accumulator number
---@field gameState "waiting"|"playing"|"roundOver"|"matchOver"
---@field roundWinner nil
---@field matchWinner nil
---@field waitTimer number
---@field scores table<integer,integer>
---@field roundNumber integer
local state    = {
    world         = nil,
    accumulator   = 0,
    gameState     = "waiting",
    roundWinner   = nil,
    matchWinner   = nil,
    waitTimer     = 0,
    scores        = {},
    roundNumber   = 0,
    DRAW          = -1,
    ROUNDS_TO_WIN = 3,
}

-- ── Camera / Cursor ───────────────────────────────────────────────────────────

---@class cursor
---@field sprite love.Image|nil
---@field x number
---@field y number
local cursor   = {}

---@class camera
---@field x number
---@field y number
---@field LOOK_SPEED number
---@field LOOK_AHEAD number
local camera   = {}

-- ── Init ──────────────────────────────────────────────────────────────────────

local function initCameraAndCursor()
    camera = { x = 0, y = 0, LOOK_SPEED = 8, LOOK_AHEAD = 0.2 }
    cursor = { sprite = love.graphics.newImage("Assets/Sprites/Weapons/Tiles/tile_0024.png"), x = 0, y = 0 }
end

local function initNetwork()
    network.USE_NETWORK  = false
    network.RELAY_HOST   = "localhost"
    network.RELAY_PORT   = 22122
    network.NUM_PLAYERS  = 2
    network.INPUT_DELAY  = 10
    network.networkIndex = 1
    network.ls           = nil
end

-- ── Private ───────────────────────────────────────────────────────────────────
local function updateCamera(w, targetIndex, cx, cy, dt)
    local pid = Utils.find(
        World.query(w, C.Name.playerIndex, C.Name.position),
        function(id) return w.playerIndex[id].index == targetIndex end
    )
    if not pid then return end

    local px = w.position[pid].x
    local py = w.position[pid].y

    local targetX = px + (cx - px) * camera.LOOK_AHEAD - 240
    local targetY = py + (cy - py) * camera.LOOK_AHEAD - 135

    local t = 1 - math.exp(-camera.LOOK_SPEED * dt)
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
    state.waitTimer   = 3.0
end

local function startMatch()
    state.scores = {}
    for i = 1, network.NUM_PLAYERS do
        state.scores[i] = 0
    end
    state.roundNumber = 0
    state.matchWinner = nil
    startRound()
end

local function tickSimulation()
    local frameInputs
    if Game.USE_NETWORK then
        local myInput = Systems.gatherLocalInput(network.networkIndex, state.world, cursor.x, cursor.y)
        frameInputs = Lockstep.tick(network.ls, myInput)
        if not frameInputs then return end
    else
        frameInputs = { [1] = Systems.gatherLocalInput(1, state.world, cursor.x, cursor.y) }
    end

    Systems.runSystems(state.world, frameInputs, FIXED_DT)
    if Systems.isRoundOver(state.world) then
        state.gameState   = "roundOver"
        state.roundWinner = Systems.getRoundWinner(state.world)

        if state.roundWinner ~= state.DRAW then
            state.scores[state.roundWinner] = state.scores[state.roundWinner] + 1
            if state.scores[state.roundWinner] >= state.ROUNDS_TO_WIN then
                state.matchWinner = state.roundWinner
                state.gameState = "matchOver"
            else
                state.gameState = "roundOver"
                state.waitTimer = 2.0
            end
        end
    end
end

local function drawCursor()
    if cursor.sprite then
        local sx = love.mouse.getX() / SCALE_FACTOR
        local sy = love.mouse.getY() / SCALE_FACTOR
        love.graphics.draw(cursor.sprite, sx, sy, 0, 1, 1,
            Utils.round(cursor.sprite:getWidth() / 2),
            Utils.round(cursor.sprite:getHeight() / 2))
    end
end

local function drawNetworkDebug()
    local stall = network.ls.stalledFrames > 0 and "  STALLED x" .. network.ls.stalledFrames or ""
    love.graphics.print("P" .. network.networkIndex .. "  f=" .. network.ls.frame .. stall, 4, 4)
end

local function drawOverlays()
    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    if state.gameState == "waiting" then
        local secs = math.ceil(state.waitTimer)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(secs > 0 and tostring(secs) or "Fight!", 0, sh / 2 - 8, sw, "center")
        love.graphics.setColor(1, 1, 1)
    elseif state.gameState == "roundOver" then
        local text
        if state.roundWinner ~= state.DRAW then
            local pidx = state.world.playerIndex[state.roundWinner]
            text = pidx and ("Player " .. pidx.index .. " wins!") or "Winner!"
        else
            text = "Draw!"
        end
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 0, 0, sw, sh)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(text, 0, sh / 2 - 16, sw, "center")
    elseif state.gameState == "matchOver" then
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 0, 0, sw, sh)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Press R to play again", 0, sh / 2 + 8, sw, "center")
    end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function Game.load()
    initNetwork()
    initCameraAndCursor()

    if Game.USE_NETWORK then
        network.ls           = Lockstep.connect(Game.RELAY_HOST, Game.RELAY_PORT, Game.NUM_PLAYERS, Game.INPUT_DELAY)
        network.networkIndex = network.ls.myIndex
        Lockstep.bootstrap(network.ls)
    end

    startMatch()
end

function Game.update(dt, keysPressed)
    dt = math.min(dt, 0.1)

    cursor.x = love.mouse.getX() / SCALE_FACTOR + camera.x
    cursor.y = love.mouse.getY() / SCALE_FACTOR + camera.y

    if state.gameState == "waiting" then
        state.waitTimer = state.waitTimer - dt
        if state.waitTimer <= 0 then
            state.gameState = "playing"
        end
    elseif state.gameState == "playing" then
        if Game.USE_NETWORK then
            Lockstep.receive(network.ls)
        end

        state.accumulator = state.accumulator + dt
        while state.accumulator >= FIXED_DT do
            tickSimulation()
            state.accumulator = state.accumulator - FIXED_DT
        end
        updateCamera(state.world, network.networkIndex, cursor.x, cursor.y, dt)
    elseif state.gameState == "roundOver" then
        state.waitTimer = state.waitTimer - dt
        if state.waitTimer <= 0 then startRound() end
    elseif state.gameState == "matchOver" then
        if keysPressed["r"] then
            startMatch()
        end
    end
end

function Game.draw(canvas)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.2, 0.2, 0.2)
    love.graphics.push()
    love.graphics.translate(-camera.x, -camera.y)
    local alpha = state.accumulator / FIXED_DT
    Systems.draw(state.world, alpha)
    Systems.drawHpBars(state.world, alpha)
    love.graphics.pop()
    drawCursor()
    love.graphics.setCanvas()

    love.graphics.draw(canvas, 0, 0, 0, SCALE_FACTOR, SCALE_FACTOR)

    if Game.USE_NETWORK then
        drawNetworkDebug()
    end

    drawOverlays()
end

return Game
