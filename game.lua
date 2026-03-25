local World    = require "world"
local Sim      = require "systems/systems_sim"
local Spawners = require "spawners"
local Maps     = require "maps"
local C        = require "components"

---@class GameHooks
---@field beforeSimulationTick fun(w: World)|nil
---@field afterSimulationTick fun(w: World, dt: number)|nil

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
---@field hooks GameHooks|nil

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
---@field predictedInputsByFrame table<integer, FrameInputs>
---@field earliestDirtyFrame integer|nil
---@field confirmedInputsForDirtyFrame FrameInputs|nil

---@class GameInstance
---@field fixedDt number
---@field rollbackWindowSize integer
---@field hooks GameHooks
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
        predictedInputsByFrame = {},
        earliestDirtyFrame = nil,
        confirmedInputsForDirtyFrame = nil,
    }
end

local function getLockstep()
    return require "lockstep"
end

---@param frameInputs FrameInputs
---@return FrameInputs
local function copyFrameInputs(frameInputs)
    local copiedInputs = {}

    for playerIndex, input in pairs(frameInputs) do
        copiedInputs[playerIndex] = {
            up = input.up,
            dn = input.dn,
            lt = input.lt,
            rt = input.rt,
            fire = input.fire,
            reload = input.reload,
            aimAngle = input.aimAngle,
        }
    end

    return copiedInputs
end

---@param self GameInstance
---@param frame integer
---@param frameInputs FrameInputs
local function recordPredictedInputs(self, frame, frameInputs)
    self.state.predictedInputsByFrame[frame] = copyFrameInputs(frameInputs)
end

---@param lhs FrameInput|nil
---@param rhs FrameInput|nil
---@return boolean
local function inputsDiffer(lhs, rhs)
    if lhs == nil or rhs == nil then
        return lhs ~= rhs
    end

    return lhs.up ~= rhs.up
        or lhs.dn ~= rhs.dn
        or lhs.lt ~= rhs.lt
        or lhs.rt ~= rhs.rt
        or lhs.fire ~= rhs.fire
        or lhs.reload ~= rhs.reload
        or lhs.aimAngle ~= rhs.aimAngle
end

---@param self GameInstance
---@param frame integer
---@param confirmedInputs FrameInputs
local function markDirtyIfConfirmedInputsDiffer(self, frame, confirmedInputs)
    local predictedInputs = self.state.predictedInputsByFrame[frame]
    if not predictedInputs then
        return
    end

    local mismatched = false

    for playerIndex = 1, self.network.NUM_PLAYERS do
        if inputsDiffer(predictedInputs and predictedInputs[playerIndex], confirmedInputs[playerIndex]) then
            mismatched = true
            break
        end
    end

    if mismatched then
        local isEarlier = self.state.earliestDirtyFrame == nil
            or frame <= self.state.earliestDirtyFrame
        if isEarlier then
            self.state.confirmedInputsForDirtyFrame = copyFrameInputs(confirmedInputs)
        end
        self.state.earliestDirtyFrame = self.state.earliestDirtyFrame
            and math.min(self.state.earliestDirtyFrame, frame)
            or frame
    end
end

---@param self GameInstance
local function clearRollbackHistory(self)
    self.state.simulationFrame = 0
    self.state.rollbackSnapshotsByFrame = {}
    self.state.rollbackFrameWindow = {}
    self.state.predictedInputsByFrame = {}
    self.state.earliestDirtyFrame = nil
    self.state.confirmedInputsForDirtyFrame = nil
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
        self.state.predictedInputsByFrame[oldestFrame] = nil
    end
end

---@param self GameInstance
---@param frame integer
local function discardRollbackFramesAfter(self, frame)
    local keptFrames = {}
    local keptSnapshots = {}
    local keptPredictedInputs = {}

    for _, recordedFrame in ipairs(self.state.rollbackFrameWindow) do
        if recordedFrame <= frame then
            keptFrames[#keptFrames + 1] = recordedFrame
            keptSnapshots[recordedFrame] = self.state.rollbackSnapshotsByFrame[recordedFrame]
            keptPredictedInputs[recordedFrame] = self.state.predictedInputsByFrame[recordedFrame]
        end
    end

    self.state.rollbackFrameWindow = keptFrames
    self.state.rollbackSnapshotsByFrame = keptSnapshots
    self.state.predictedInputsByFrame = keptPredictedInputs
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

local runFixedGameplayTick

---@param self GameInstance
local function clearDirtyPrediction(self)
    self.state.earliestDirtyFrame = nil
    self.state.confirmedInputsForDirtyFrame = nil
end

---@param self GameInstance
local function reconcileDirtyFrames(self)
    local dirtyFrame = self.state.earliestDirtyFrame
    if dirtyFrame == nil then
        return
    end

    if not self.state.rollbackSnapshotsByFrame[dirtyFrame] then
        print(string.format("[prediction] Missing rollback snapshot for dirty frame %d; clearing dirty state.",
            dirtyFrame))
        clearDirtyPrediction(self)
        return
    end

    local replayEndFrame = self.state.simulationFrame
    local confirmedDirtyInputs = self.state.confirmedInputsForDirtyFrame
    local replayInputsByFrame = {}

    if dirtyFrame < replayEndFrame and not confirmedDirtyInputs then
        print(string.format("[prediction] Missing confirmed inputs for dirty frame %d; clearing dirty state.", dirtyFrame))
        clearDirtyPrediction(self)
        return
    end

    for replayFrame = dirtyFrame, replayEndFrame - 1 do
        local replayInputs = replayFrame == dirtyFrame and confirmedDirtyInputs
            or self.state.predictedInputsByFrame[replayFrame]

        if not replayInputs then
            print(string.format("[prediction] Missing replay inputs for frame %d; clearing dirty state.", replayFrame))
            clearDirtyPrediction(self)
            return
        end

        replayInputsByFrame[replayFrame] = replayInputs
    end

    self:rollbackToFrame(dirtyFrame)

    while self.state.simulationFrame < replayEndFrame do
        local replayFrame = self.state.simulationFrame
        local replayInputs = replayInputsByFrame[replayFrame]
        runFixedGameplayTick(self, replayInputs, true)
    end

    clearDirtyPrediction(self)
end

---@param self GameInstance
---@param frameInputs FrameInputs
---@param isReplay boolean|nil
runFixedGameplayTick = function(self, frameInputs, isReplay)
    if not isReplay and self.state.predictedInputsByFrame[self.state.simulationFrame] == nil then
        recordPredictedInputs(self, self.state.simulationFrame, frameInputs)
    end
    saveRollbackSnapshot(self)

    if not isReplay and self.hooks.beforeSimulationTick then
        self.hooks.beforeSimulationTick(self.state.world)
    end

    Sim.runSimulation(self.state.world, frameInputs, self.fixedDt)

    if isReplay then
        if Sim.discardPresentationEvents then
            Sim.discardPresentationEvents(self.state.world)
        end
    elseif self.hooks.afterSimulationTick then
        self.hooks.afterSimulationTick(self.state.world, self.fixedDt)
    elseif Sim.discardPresentationEvents then
        Sim.discardPresentationEvents(self.state.world)
    end

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
        reconcileDirtyFrames(self)

        if self.network.USE_NETWORK then
            -- Lockstep currently returns the confirmed inputs for the frame we are
            -- about to simulate. Only compare against frames we have actually
            -- predicted already; the current raw local input is for a future
            -- target frame under lockstep delay, not necessarily this frame.
            local currentFrame = self.state.simulationFrame
            local localInput = frameInputs[self.network.networkIndex]
            local syncedInputs = getLockstep().tick(self.network.ls, localInput)
            if syncedInputs then
                markDirtyIfConfirmedInputsDiffer(self, currentFrame, syncedInputs)
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
        hooks = config.hooks or {},
        network = newNetworkState(config),
        state = newGameState(config),
    }, Game)
end

---@param hooks GameHooks|nil
function Game:setHooks(hooks)
    self.hooks = hooks or {}
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
function Game:update(dt, frameInputs)
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
