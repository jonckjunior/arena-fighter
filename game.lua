local World    = require "world"
local Systems  = require "systems"
local Spawners = require "spawners"
local Lockstep = require "lockstep"
local C        = require "components"
local Maps     = require "maps"
local Assets   = require "assets"
local Rng      = require "rng"

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

-- ── Init ──────────────────────────────────────────────────────────────────────

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

local function gatherFrameInputs(keysPressed)
    local cursor = Systems.getCursorState()
    if network.USE_NETWORK then
        local myInput = Systems.gatherLocalInput(network.networkIndex, state.world, cursor.worldX, cursor.worldY, true,
            keysPressed)
        return Lockstep.tick(network.ls, myInput)
    end

    return {
        [1] = Systems.gatherLocalInput(1, state.world, cursor.worldX, cursor.worldY, false, keysPressed),
        [2] = Systems.gatherLocalInput(2, state.world, cursor.worldX, cursor.worldY, false, keysPressed),
    }
end

local function updateRoundState()
    if not Systems.isRoundOver(state.world) then return end

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

---@param frameInputs table
---@param localPlayerIndex integer
---@param withPresentation boolean
local function runFixedGameplayTick(frameInputs, localPlayerIndex, withPresentation)
    Systems.snapshotPositions(state.world)
    Systems.runSimulation(state.world, frameInputs, FIXED_DT)
    if withPresentation then
        Systems.runPresentationTick(state.world, localPlayerIndex, FIXED_DT)
    end
end

---@param keysPressed RawInput
---@param withPresentation boolean
local function tickSimulation(keysPressed, withPresentation)
    local frameInputs = gatherFrameInputs(keysPressed)
    if not frameInputs then return end

    runFixedGameplayTick(frameInputs, network.networkIndex, withPresentation)
    updateRoundState()
end

---Ticks the match over for network and local
---@param keysPressed RawInput
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

---@param keysPressed RawInput
local function tickFixed(keysPressed)
    if state.gameState == "waiting" then
        state.waitTimer = state.waitTimer - FIXED_DT
        if state.waitTimer <= 0 then
            state.gameState = "playing"
        end
    elseif state.gameState == "playing" then
        tickSimulation(keysPressed, true)
    elseif state.gameState == "roundOver" then
        state.waitTimer = state.waitTimer - FIXED_DT
        if state.waitTimer <= 0 then startRound() end
    elseif state.gameState == "matchOver" then
        tickMatchOver(keysPressed)
    end
end

---@return number
local function currentDrawAlpha()
    if state.gameState == "playing" then
        return state.accumulator / FIXED_DT
    end
    return 1.0
end

-- ── Public API ────────────────────────────────────────────────────────────────

function Game.load()
    Assets.load()
    initNetwork()
    Systems.initPresentation()

    if network.USE_NETWORK then
        network.ls           = Lockstep.connect(network.RELAY_HOST, network.RELAY_PORT, network.NUM_PLAYERS,
            network.INPUT_DELAY)
        network.networkIndex = network.ls.myIndex
        Lockstep.bootstrap(network.ls)
    end

    startMatch()
end

---@param dt number
---@param keysPressed RawInput
function Game.update(dt, keysPressed)
    -- Variable rate work: input I/O, networking, presentation camera.
    Systems.updatePresentationInput(keysPressed)
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

    Systems.updatePresentationCamera(state.world, network.networkIndex, dt)
end

function Game.draw(canvas)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.2, 0.2, 0.2)
    Systems.drawWorldFrame(state.world, currentDrawAlpha())
    love.graphics.setCanvas()
    love.graphics.draw(canvas, 0, 0, 0, SCALE_FACTOR, SCALE_FACTOR)
    Systems.drawScreenUi(
        state.gameState,
        state.waitTimer,
        state.roundWinner,
        state.DRAW,
        network.USE_NETWORK,
        state.localWantsRestart,
        state.scores,
        network.networkIndex,
        network.USE_NETWORK and network.ls.frame or nil,
        network.USE_NETWORK and network.ls.stalledFrames or nil
    )
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
    local rng = Rng.new(9999)
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
        local frameInputs = {
            [1] = Systems.gatherLocalInput(1, state.world, 0, 0, false, {}),
            [2] = Systems.gatherLocalInput(2, state.world, 0, 0, false, {}),
        }
        runFixedGameplayTick(frameInputs, network.networkIndex, false)
        updateRoundState()
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
