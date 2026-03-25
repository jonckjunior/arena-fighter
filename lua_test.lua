local Game = require "game"
local Rng  = require "rng"

local function neutralFrameInputs()
    return {
        [1] = { up = false, dn = false, lt = false, rt = false, fire = false, reload = false, aimAngle = 0 },
        [2] = { up = false, dn = false, lt = false, rt = false, fire = false, reload = false, aimAngle = math.pi },
    }
end

local function advanceUntil(game, predicate, maxFrames)
    maxFrames = maxFrames or 600
    for _ = 1, maxFrames do
        if predicate() then return end
        game:update(game:getFixedDt(), neutralFrameInputs())
    end
    error("Condition was not reached within " .. maxFrames .. " frames")
end

local function findPlayerIdByIndex(w, playerIndex)
    for id, comp in pairs(w.playerIndex) do
        if comp.index == playerIndex then
            return id
        end
    end
    error("Could not find player index " .. playerIndex)
end

local function knockOutPlayer(game, losingPlayerIndex)
    advanceUntil(game, function()
        return game:getState().gameState == "playing"
    end)

    local world = game:getWorld()
    local playerId = findPlayerIdByIndex(world, losingPlayerIndex)
    world.hp[playerId].current = 0
    game:update(game:getFixedDt(), neutralFrameInputs())
end

local function runDeterminismSimulation(seed, frames)
    local rng = Rng.new(seed)
    local game = Game.new()
    game:load()

    for _ = 1, frames do
        game:update(game:getFixedDt(), {
            [1] = {
                up = rng:random() > 0.8,
                dn = rng:random() > 0.8,
                lt = rng:random() > 0.5,
                rt = rng:random() > 0.5,
                fire = rng:random() > 0.9,
                reload = rng:random() > 0.5,
                aimAngle = (rng:random() - 0.5) * math.pi * 2,
            },
            [2] = {
                up = rng:random() > 0.8,
                dn = rng:random() > 0.8,
                lt = rng:random() > 0.5,
                rt = rng:random() > 0.5,
                fire = rng:random() > 0.9,
                reload = rng:random() > 0.5,
                aimAngle = (rng:random() - 0.5) * math.pi * 2,
            },
        })
    end

    return game:getStateHash()
end

local function assertLifecycle()
    local game = Game.new()
    game:load()

    assert(game:getState().gameState == "waiting", "Game should start in waiting")
    game:update(game:getFixedDt(), neutralFrameInputs())
    assert(game:getState().gameState == "playing", "Game should advance from waiting to playing")

    knockOutPlayer(game, 2)
    assert(game:getState().gameState == "roundOver", "Game should enter roundOver after a knockout")
    assert(game:getState().scores[1] == 1, "Winning a round should increment score")

    advanceUntil(game, function()
        return game:getState().gameState == "playing"
    end, 240)

    game:getState().scores[1] = game:getState().ROUNDS_TO_WIN - 1
    knockOutPlayer(game, 2)
    assert(game:getState().gameState == "matchOver", "Final knockout should enter matchOver")
    assert(game:getState().matchWinner == 1, "Match winner should be recorded")

    game:update(game:getFixedDt(), {
        [1] = { up = false, dn = false, lt = false, rt = false, fire = false, reload = true, aimAngle = 0 },
        [2] = { up = false, dn = false, lt = false, rt = false, fire = false, reload = false, aimAngle = math.pi },
    })
    assert(game:getState().gameState == "waiting", "Reload during matchOver should restart the match locally")
end

local hashA = runDeterminismSimulation(9999, 1200)
local hashB = runDeterminismSimulation(9999, 1200)

assert(hashA == hashB, "Determinism check failed: hashes differ")
assertLifecycle()

print("lua_test.lua passed")
print("Deterministic hash: " .. hashA)
