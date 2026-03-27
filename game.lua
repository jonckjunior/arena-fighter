local World    = require "world"
local Sim      = require "systems/systems_sim"
local Spawners = require "spawners"
local Maps     = require "maps"
local C        = require "components"

---@class GameConfig
---@field useNetwork boolean|nil
---@field relayHost string|nil
---@field relayPort integer|nil
---@field numPlayers integer|nil
---@field inputDelay integer|nil
---@field localPlayerIndex integer|nil
---@field roundsToWin integer|nil
---@field fixedDt number|nil
---@field rollbackWindowSize integer|nil

---@class GameNetworkState
---@field USE_NETWORK boolean
---@field RELAY_HOST string
---@field RELAY_PORT integer
---@field NUM_PLAYERS integer
---@field INPUT_DELAY integer
---@field networkIndex integer
---@field ls LockstepState|nil

---@class GameState
---@field world World|nil
---@field accumulator number
---@field gameState "waiting"|"playing"|"roundOver"|"matchOver"
---@field roundWinner integer|nil
---@field matchWinner integer|nil
---@field waitTimer number
---@field scores table<integer, integer>
---@field DRAW integer
---@field ROUNDS_TO_WIN integer
---@field localWantsRestart boolean
---@field simulationFrame integer
---@field rollbackSnapshotsByFrame table<integer, table>
---@field rollbackFrameWindow integer[]
---@field rollbackWindowSize integer

---@class GameInstance
---@field fixedDt number
---@field rollbackWindowSize integer
---@field network GameNetworkState
---@field state GameState
local Game     = {}
Game.__index   = Game
Game.FIXED_DT  = 1 / 60

local function newNetworkState(config)
    return {
        USE_NETWORK = config.useNetwork or false,
        RELAY_HOST = config.relayHost or "localhost",
        RELAY_PORT = config.relayPort or 22122,
        NUM_PLAYERS = config.numPlayers or 2,
        INPUT_DELAY = config.inputDelay or 6,
        networkIndex = config.localPlayerIndex or 1,
        ls = nil,
    }
end

local function newGameState(config)
    return {
        world = nil,
        accumulator = 0,
        gameState = "waiting",
        roundWinner = nil,
        matchWinner = nil,
        waitTimer = 0,
        scores = {},
        DRAW = -1,
        ROUNDS_TO_WIN = config.roundsToWin or 3,
        localWantsRestart = false,
        simulationFrame = 0,
        rollbackSnapshotsByFrame = {},
        rollbackFrameWindow = {},
        rollbackWindowSize = config.rollbackWindowSize or 120,
    }
end

local function getLockstep()
    return require "lockstep"
end

---@param self GameInstance
local function clearRollbackHistory(self)
    self.state.simulationFrame = 0
    self.state.rollbackSnapshotsByFrame = {}
    self.state.rollbackFrameWindow = {}
end

---@param self GameInstance
local function saveRollbackSnapshot(self)
    local frame = self.state.simulationFrame
    local snapshotsByFrame = self.state.rollbackSnapshotsByFrame
    local frameWindow = self.state.rollbackFrameWindow

    if not snapshotsByFrame[frame] then
        frameWindow[#frameWindow + 1] = frame
    end
    snapshotsByFrame[frame] = World.saveState(self.state.world)

    while #frameWindow > self.state.rollbackWindowSize do
        local oldestFrame = table.remove(frameWindow, 1)
        snapshotsByFrame[oldestFrame] = nil
    end
end

---@param self GameInstance
---@param frame integer
local function discardRollbackFramesAfter(self, frame)
    local keptFrames = {}
    local keptSnapshots = {}

    for _, recordedFrame in ipairs(self.state.rollbackFrameWindow) do
        if recordedFrame <= frame then
            keptFrames[#keptFrames + 1] = recordedFrame
            keptSnapshots[recordedFrame] = self.state.rollbackSnapshotsByFrame[recordedFrame]
        end
    end

    self.state.rollbackFrameWindow = keptFrames
    self.state.rollbackSnapshotsByFrame = keptSnapshots
end

---@param self GameInstance
local function startRound(self)
    self.state.world = Spawners.fromMapDef(Maps.arena)
    self.state.gameState = "waiting"
    self.state.roundWinner = nil
    self.state.waitTimer = 0.0
    clearRollbackHistory(self)
end

---@param self GameInstance
local function startMatch(self)
    self.state.scores = {}
    for i = 1, self.network.NUM_PLAYERS do
        self.state.scores[i] = 0
    end
    self.state.matchWinner = nil
    self.state.accumulator = 0
    self.state.localWantsRestart = false
    startRound(self)
end

---@param self GameInstance
local function updateRoundState(self)
    if not Sim.isRoundOver(self.state.world) then return end

    self.state.gameState = "roundOver"
    self.state.roundWinner = Sim.getRoundWinner(self.state.world)

    if self.state.roundWinner ~= self.state.DRAW then
        self.state.scores[self.state.roundWinner] = self.state.scores[self.state.roundWinner] + 1
        if self.state.scores[self.state.roundWinner] >= self.state.ROUNDS_TO_WIN then
            self.state.matchWinner = self.state.roundWinner
            self.state.gameState = "matchOver"
        else
            self.state.gameState = "roundOver"
            self.state.waitTimer = 2.0
        end
    end
end

---@param self GameInstance
---@param frameInputs FrameInputs
local function runFixedGameplayTick(self, frameInputs)
    saveRollbackSnapshot(self)

    Sim.runSimulation(self.state.world, frameInputs, self.fixedDt)

    self.state.simulationFrame = self.state.simulationFrame + 1
end

---@param self GameInstance
---@param frameInputs FrameInputs
local function tickMatchOver(self, frameInputs)
    local localInput = frameInputs[self.network.networkIndex]
    if self.network.USE_NETWORK then
        if localInput.reload then
            self.state.localWantsRestart = true
        end

        local restartInputs = getLockstep().tick(self.network.ls, {
            up = false,
            dn = false,
            lt = false,
            rt = false,
            fire = false,
            aimAngle = 0,
            reload = self.state.localWantsRestart,
        })

        if restartInputs then
            local allReady = true
            for i = 1, self.network.NUM_PLAYERS do
                if not (restartInputs[i] and restartInputs[i].reload) then
                    allReady = false
                    break
                end
            end
            if allReady then
                startMatch(self)
            end
        end
    else
        if localInput.reload then
            startMatch(self)
        end
    end
end

---@param self GameInstance
---@param frameInputs FrameInputs
local function tickFixed(self, frameInputs)
    if self.state.gameState == "waiting" then
        self.state.waitTimer = self.state.waitTimer - self.fixedDt
        if self.state.waitTimer <= 0 then
            self.state.gameState = "playing"
        end
    elseif self.state.gameState == "playing" then
        if self.network.USE_NETWORK then
            local localInput = frameInputs[self.network.networkIndex]
            local syncedInputs = getLockstep().tick(self.network.ls, localInput)
            if syncedInputs then
                runFixedGameplayTick(self, syncedInputs)
                updateRoundState(self)
            end
        else
            runFixedGameplayTick(self, frameInputs)
            updateRoundState(self)
        end
    elseif self.state.gameState == "roundOver" then
        self.state.waitTimer = self.state.waitTimer - self.fixedDt
        if self.state.waitTimer <= 0 then
            startRound(self)
        end
    elseif self.state.gameState == "matchOver" then
        tickMatchOver(self, frameInputs)
    end
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

---@param config GameConfig|nil
---@return GameInstance
function Game.new(config)
    config = config or {}
    return setmetatable({
        fixedDt = config.fixedDt or Game.FIXED_DT,
        rollbackWindowSize = config.rollbackWindowSize or 120,
        network = newNetworkState(config),
        state = newGameState(config),
    }, Game)
end

function Game:load()
    if self.network.USE_NETWORK then
        local Lockstep = getLockstep()
        self.network.ls = Lockstep.connect(
            self.network.RELAY_HOST,
            self.network.RELAY_PORT,
            self.network.NUM_PLAYERS,
            self.network.INPUT_DELAY
        )
        self.network.networkIndex = self.network.ls.myIndex
        Lockstep.bootstrap(self.network.ls)
    end

    startMatch(self)
end

---@param dt number
---@param frameInputs FrameInputs
---@param keepEvents boolean
function Game:update(dt, frameInputs, keepEvents)
    if self.network.USE_NETWORK then
        getLockstep().receive(self.network.ls)
    end

    self.state.accumulator = self.state.accumulator + dt
    local maxTicksPerFrame = 6
    local ticksThisFrame = 0
    while self.state.accumulator >= self.fixedDt and ticksThisFrame < maxTicksPerFrame do
        tickFixed(self, frameInputs)
        self.state.accumulator = self.state.accumulator - self.fixedDt
        ticksThisFrame = ticksThisFrame + 1
    end

    if not keepEvents then
        World.discardPresentationEvents(self.state.world)
    end
end

---@return GameState
function Game:getState()
    return self.state
end

---@return World
function Game:getWorld()
    return self.state.world
end

---@return GameNetworkState
function Game:getNetworkState()
    return self.network
end

---@return integer
function Game:getLocalPlayerIndex()
    return self.network.networkIndex
end

---@return integer
function Game:getPlayerCount()
    return self.network.NUM_PLAYERS
end

---@return boolean
function Game:usesNetwork()
    return self.network.USE_NETWORK
end

---@return number
function Game:getFixedDt()
    return self.fixedDt
end

---@return integer
function Game:getSimulationFrame()
    return self.state.simulationFrame
end

---@param frame integer
---@return boolean
function Game:canRollbackToFrame(frame)
    return self.state.rollbackSnapshotsByFrame[frame] ~= nil
end

---@param frame integer
---@return boolean
function Game:rollbackToFrame(frame)
    local snapshot = self.state.rollbackSnapshotsByFrame[frame]
    if not snapshot then
        return false
    end

    World.writeState(self.state.world, snapshot)
    self.state.simulationFrame = frame
    self.state.accumulator = 0
    discardRollbackFramesAfter(self, frame)
    return true
end

---@return boolean
function Game:rollbackToWindowStart()
    local frame = self.state.rollbackFrameWindow[1]
    if frame == nil then
        return false
    end
    return self:rollbackToFrame(frame)
end

---@return number
function Game:getDrawAlpha()
    if self.state.gameState == "playing" then
        return self.state.accumulator / self.fixedDt
    end
    return 1.0
end

---@return integer
function Game:getStateHash()
    return generateStateHash(self.state.world)
end

return Game
