local World    = require "world"
local Systems  = require "systems"
local Spawners = require "spawners"
local Lockstep = require "lockstep"
local Utils    = require "utils"
local C        = require "components"
local Maps     = require "maps"
local Assets   = require "assets"

---@class Game
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
---@field roundWinner integer|nil
---@field matchWinner integer|nil
---@field waitTimer number
---@field scores table<integer,integer>
---@field roundNumber integer
local state    = {
    world             = nil,
    accumulator       = 0,
    gameState         = "waiting",
    roundWinner       = nil,
    matchWinner       = nil,
    waitTimer         = 0,
    scores            = {},
    roundNumber       = 0,
    DRAW              = -1,
    ROUNDS_TO_WIN     = 3,
    localWantsRestart = false, -- true once this client has pressed R
}

-- ── Camera / Cursor ───────────────────────────────────────────────────────────

---@class cursor
---@field spriteId string|nil
---@field x number
---@field y number
local cursor   = {}

---@class camera
---@field x number
---@field y number
---@field LOOK_SPEED number
---@field LOOK_AHEAD number
---@field shake { intensity: number, timer: number, duration: number, shakeOffsetX: number, shakeOffsetY: number }
local camera   = {}

-- ── Init ──────────────────────────────────────────────────────────────────────

local function initCameraAndCursor()
    camera = {
        x = 0,
        y = 0,
        LOOK_SPEED = 8,
        LOOK_AHEAD = 0.2,
        shake = {
            intensity = 0,
            duration = 0.2,
            timer = 0,
            shakeOffsetX = 0,
            shakeOffsetY = 0,
        }
    }
    cursor = { spriteId = "cursor_cross", x = 0, y = 0 }
end

local function initNetwork()
    network.USE_NETWORK  = false
    network.RELAY_HOST   = "localhost"
    network.RELAY_PORT   = 22122
    network.NUM_PLAYERS  = 2
    network.INPUT_DELAY  = 6
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

    camera.x = math.max(0, math.min(camera.x, w.mapWidth - VIEWPORT_W))
    camera.y = math.max(0, math.min(camera.y, w.mapHeight - VIEWPORT_H))
end

local function startRound()
    state.world       = Spawners.fromMapDef(Maps.arena)
    state.gameState   = "waiting"
    state.roundWinner = nil
    state.waitTimer   = 0.0
end

local function startMatch()
    state.scores = {}
    for i = 1, network.NUM_PLAYERS do
        state.scores[i] = 0
    end
    state.roundNumber       = 0
    state.matchWinner       = nil
    state.accumulator       = 0
    state.localWantsRestart = false
    startRound()
end

local function tickSimulation(keysPressed)
    local frameInputs
    if network.USE_NETWORK then
        local myInput = Systems.gatherLocalInput(network.networkIndex, state.world, cursor.x, cursor.y, true, keysPressed)
        frameInputs = Lockstep.tick(network.ls, myInput)
        if not frameInputs then return end
    else
        frameInputs = {
            [1] = Systems.gatherLocalInput(1, state.world, cursor.x, cursor.y, false, keysPressed),
            [2] = Systems.gatherLocalInput(2, state.world, cursor.x, cursor.y, false, keysPressed),
        }
    end

    Systems.runSystems(state.world, frameInputs, network.networkIndex, FIXED_DT)
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


    local intensity, duration = Systems.shakeEvent(state.world, network.networkIndex)
    if intensity > 0 then
        if intensity > camera.shake.intensity then
            camera.shake.intensity = intensity
        end
        if duration > camera.shake.timer then
            camera.shake.timer = duration
            camera.shake.duration = duration
        end
    end

    camera.shake.timer = math.max(0, camera.shake.timer - FIXED_DT)
    if camera.shake.timer > 0 then
        local s = camera.shake.intensity * (camera.shake.timer / camera.shake.duration)
        camera.shake.shakeOffsetX = love.math.random(-s, s)
        camera.shake.shakeOffsetY = love.math.random(-s, s)
    else
        camera.shake.shakeOffsetX = 0
        camera.shake.shakeOffsetY = 0
        camera.shake.intensity = 0
    end
end

local function drawCursor()
    if cursor.spriteId then
        local sprite = Assets.getImage(cursor.spriteId)
        local sx = love.mouse.getX() / SCALE_FACTOR
        local sy = love.mouse.getY() / SCALE_FACTOR
        love.graphics.draw(sprite, sx, sy, 0, 1, 1,
            Utils.round(sprite:getWidth() / 2),
            Utils.round(sprite:getHeight() / 2))
    end
end

local function drawNetworkDebug()
    local stall = network.ls.stalledFrames > 0 and "  STALLED x" .. network.ls.stalledFrames or ""
    love.graphics.print("P" .. network.networkIndex .. "  f=" .. network.ls.frame .. stall, 4, 4)
end

---Draws player scores at the top of the screen.
---@param scores table  scores[playerIndex] = integer
local function drawScores(scores)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("P1: " .. scores[1], 10, 10)
    love.graphics.print("P2: " .. scores[2], love.graphics.getWidth() - 60, 10)
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
            text = "Player " .. state.roundWinner .. " wins!"
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
        if network.USE_NETWORK and state.localWantsRestart then
            love.graphics.printf("Waiting for other players...", 0, sh / 2 + 8, sw, "center")
        else
            love.graphics.printf("Press R to play again", 0, sh / 2 + 8, sw, "center")
        end
    end
end

---Ticks the match over for network and local
---@param keysPressed table<string, boolean>
local function tickMatchOver(keysPressed)
    if network.USE_NETWORK then
        if keysPressed["r"] then state.localWantsRestart = true end
        local inp = {
            up = false,
            dn = false,
            lt = false,
            rt = false,
            fire = false,
            aimAngle = 0,
            reload = state.localWantsRestart,
        }
        local frameInputs = Lockstep.tick(network.ls, inp)
        if frameInputs then
            local allReady = true
            for i = 1, network.NUM_PLAYERS do
                if not (frameInputs[i] and frameInputs[i].reload) then
                    allReady = false; break
                end
            end
            if allReady then
                startMatch()
                return
            end
        end
    else
        if keysPressed["r"] then
            startMatch()
            return
        end
    end
end

local function tickFixed(keysPressed)
    if state.gameState == "waiting" then
        state.waitTimer = state.waitTimer - FIXED_DT
        if state.waitTimer <= 0 then
            state.gameState = "playing"
        end
    elseif state.gameState == "playing" then
        tickSimulation(keysPressed)
    elseif state.gameState == "roundOver" then
        state.waitTimer = state.waitTimer - FIXED_DT
        if state.waitTimer <= 0 then startRound() end
    elseif state.gameState == "matchOver" then
        tickMatchOver(keysPressed)
    end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function Game.load()
    Assets.load()
    initNetwork()
    initCameraAndCursor()

    if network.USE_NETWORK then
        network.ls           = Lockstep.connect(network.RELAY_HOST, network.RELAY_PORT, network.NUM_PLAYERS,
            network.INPUT_DELAY)
        network.networkIndex = network.ls.myIndex
        Lockstep.bootstrap(network.ls)
    end

    startMatch()
end

function Game.update(dt, keysPressed)
    -- Variable rate: I/O and visuals only
    cursor.x = love.mouse.getX() / SCALE_FACTOR + camera.x
    cursor.y = love.mouse.getY() / SCALE_FACTOR + camera.y
    if network.USE_NETWORK then
        Lockstep.receive(network.ls)
    end

    state.accumulator = state.accumulator + dt
    local maxTicksPerFrame = 6
    local ticksThisFrame = 0
    while state.accumulator >= FIXED_DT and ticksThisFrame < maxTicksPerFrame do
        tickFixed(keysPressed)
        state.accumulator = state.accumulator - FIXED_DT
        ticksThisFrame = ticksThisFrame + 1
    end

    updateCamera(state.world, network.networkIndex, cursor.x, cursor.y, dt)
end

function Game.draw(canvas)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.2, 0.2, 0.2)
    love.graphics.push()
    love.graphics.translate(-camera.x + camera.shake.shakeOffsetX, -camera.y + camera.shake.shakeOffsetY)

    --- WORLD DRAW
    if state.world.mapAssetId then
        love.graphics.draw(Assets.getImage(state.world.mapAssetId), 0, 0)
    end
    local alpha = (state.gameState == "playing") and (state.accumulator / FIXED_DT) or 1.0
    Systems.draw(state.world, alpha)
    Systems.drawHpBars(state.world, alpha)
    Systems.drawReloadBars(state.world, alpha)
    --- END OF WORLD DRAW

    love.graphics.pop()
    drawCursor()
    love.graphics.setCanvas()

    love.graphics.draw(canvas, 0, 0, 0, SCALE_FACTOR, SCALE_FACTOR)

    if network.USE_NETWORK then
        drawNetworkDebug()
    end

    drawOverlays()

    drawScores(state.scores)
end

local function generateStateHash(w)
    local hash = 0
    local prime = 31
    local modulo = 2147483647

    local activeEntities = World.query(w, C.Name.position)
    table.sort(activeEntities)

    for _, id in ipairs(activeEntities) do
        local pos = w.position[id]

        local x = math.floor(pos.x * 10000)
        local y = math.floor(pos.y * 10000)

        hash = (hash * prime + x) % modulo
        hash = (hash * prime + y) % modulo

        if w.velocity[id] then
            local vel = w.velocity[id]
            local dx = math.floor(vel.dx * 10000)
            local dy = math.floor(vel.dy * 10000)
            hash = (hash * prime + dx) % modulo
            hash = (hash * prime + dy) % modulo
        end

        if w.hp[id] then
            local hp = math.floor(w.hp[id].current * 10000)
            hash = (hash * prime + hp) % modulo
        end

        if w.gun[id] then
            hash = (hash * prime + w.gun[id].cooldown) % modulo
        end
    end

    return hash
end

function Game.runHeadlessTest(frames)
    print("Starting headless test for " .. frames .. " frames")
    local rng = love.math.newRandomGenerator(9999)
    local originalGather = Systems.gatherLocalInput

    Systems.gatherLocalInput = function(playerIndex, w, mx, my, USE_NETWORK)
        return {
            up = rng:random() > 0.8,
            dn = rng:random() > 0.8,
            lt = rng:random() > 0.5,
            rt = rng:random() > 0.5,
            fire = rng:random() > 0.9,
            aimAngle = (rng:random() - 0.5) * math.pi * 2,
            reload = rng:random() > 0.5,
        }
    end
    Game.load()

    for i = 1, frames do
        Game.update(FIXED_DT, {})
    end

    local finalHash = generateStateHash(state.world)
    print("=====================================")
    print("Headless Test Complete.")
    print("Final State Hash: " .. finalHash)
    print("Number of entities with position: " .. #state.world.position)
    print("=====================================")

    Systems.gatherLocalInput = originalGather
    love.event.quit()
end

return Game
