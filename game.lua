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
---@field roundNumber integer
---@field DRAW integer
---@field ROUNDS_TO_WIN integer
---@field localWantsRestart boolean

---@class GameInstance
---@field fixedDt number
---@field hooks GameHooks
---@field network GameNetworkState
---@field state GameState
local Game    = {}
Game.__index  = Game
Game.FIXED_DT = 1 / 60

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
        roundNumber = 0,
        DRAW = -1,
        ROUNDS_TO_WIN = config.roundsToWin or 3,
        localWantsRestart = false,
    }
end

local function neutralInput()
    return {
        up = false,
        dn = false,
        lt = false,
        rt = false,
        fire = false,
        reload = false,
        aimAngle = 0,
    }
end

local function getLockstep()
    return require "lockstep"
end

---@param self GameInstance
local function startRound(self)
    self.state.world = Spawners.fromMapDef(Maps.arena)
    self.state.gameState = "waiting"
    self.state.roundWinner = nil
    self.state.waitTimer = 0.0
end

---@param self GameInstance
local function startMatch(self)
    self.state.scores = {}
    for i = 1, self.network.NUM_PLAYERS do
        self.state.scores[i] = 0
    end
    self.state.roundNumber = 0
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
---@param frameInputs table
local function runFixedGameplayTick(self, frameInputs)
    if self.hooks.beforeSimulationTick then
        self.hooks.beforeSimulationTick(self.state.world)
    end

    Sim.runSimulation(self.state.world, frameInputs, self.fixedDt)

    if self.hooks.afterSimulationTick then
        self.hooks.afterSimulationTick(self.state.world, self.fixedDt)
    elseif Sim.discardPresentationEvents then
        Sim.discardPresentationEvents(self.state.world)
    end
end

---@param self GameInstance
---@param frameInputs table
---@return table|nil
local function resolveFrameInputs(self, frameInputs)
    frameInputs = frameInputs or {}
    if not self.network.USE_NETWORK then
        return frameInputs
    end

    local localInput = frameInputs[self.network.networkIndex] or neutralInput()
    return getLockstep().tick(self.network.ls, localInput)
end

---@param self GameInstance
---@param frameInputs table
local function tickSimulation(self, frameInputs)
    local resolved = resolveFrameInputs(self, frameInputs)
    if not resolved then return end

    runFixedGameplayTick(self, resolved)
    updateRoundState(self)
end

---@param self GameInstance
---@param frameInputs table
local function tickMatchOver(self, frameInputs)
    local localInput = (frameInputs and frameInputs[self.network.networkIndex]) or neutralInput()
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
---@param frameInputs table
local function tickFixed(self, frameInputs)
    if self.state.gameState == "waiting" then
        self.state.waitTimer = self.state.waitTimer - self.fixedDt
        if self.state.waitTimer <= 0 then
            self.state.gameState = "playing"
        end
    elseif self.state.gameState == "playing" then
        tickSimulation(self, frameInputs)
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
---@param frameInputs table|nil
function Game:update(dt, frameInputs)
    frameInputs = frameInputs or {}

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

---@return World|nil
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
