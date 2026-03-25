local Game            = require "game"
local Rng             = require "rng"

local EXPECTED_HASH   = 2118861698

local CONTROLLED_DUEL = {
    shooterX = 80,
    targetX = 140,
    y = 238.5,
    muzzleOffsetX = 0,
}

local function neutralFrameInputs()
    return {
        [1] = { up = false, dn = false, lt = false, rt = false, fire = false, reload = false, aimAngle = 0 },
        [2] = { up = false, dn = false, lt = false, rt = false, fire = false, reload = false, aimAngle = math.pi },
    }
end

local function advanceFrames(game, inputsFactory, frameCount)
    for frame = 1, frameCount do
        local frameInputs = inputsFactory and inputsFactory(frame) or neutralFrameInputs()
        game:update(game:getFixedDt(), frameInputs)
    end
end

local function advanceUntil(game, predicate, maxFrames, inputsFactory)
    maxFrames = maxFrames or 600
    for frame = 1, maxFrames do
        if predicate() then return end
        local frameInputs = inputsFactory and inputsFactory(frame) or neutralFrameInputs()
        game:update(game:getFixedDt(), frameInputs)
    end
    error("Condition was not reached within " .. maxFrames .. " frames")
end

local function framesForSeconds(seconds, fixedDt, extraFrames)
    return math.ceil(seconds / fixedDt) + (extraFrames or 0)
end

local function findPlayerIdByIndex(w, playerIndex)
    for id, comp in pairs(w.playerIndex) do
        if comp.index == playerIndex then
            return id
        end
    end
    error("Could not find player index " .. playerIndex)
end

local function findGunIdByOwner(w, ownerId)
    for id, comp in pairs(w.equippedBy) do
        if comp.ownerId == ownerId then
            return id
        end
    end
    error("Could not find gun for owner " .. ownerId)
end

local function setPosition(w, entityId, x, y)
    w.position[entityId].x = x
    w.position[entityId].y = y
    w.position[entityId].px = x
    w.position[entityId].py = y
end

local function resetGrounded(comp)
    if not comp then return end
    comp.value = true
    comp.wallDir = 0
    comp.framesSinceGrounded = 0
    comp.framesSinceJump = 999
    comp.framesSinceWall = 999
    comp.lastWallDir = 0
end

local function resetGun(gun, muzzleOffsetX)
    gun.cooldown = 0
    gun.currentAmmo = gun.maxAmmo
    gun.isReloading = false
    gun.reloadTimer = 0
    gun.muzzleOffsetX = muzzleOffsetX or gun.muzzleOffsetX
    gun.muzzleOffsetY = 0
end

local function waitForPlaying(game)
    advanceUntil(game, function()
        return game:getState().gameState == "playing"
    end)
end

local function knockOutPlayer(game, losingPlayerIndex)
    waitForPlaying(game)

    local world = game:getWorld()
    local playerId = findPlayerIdByIndex(world, losingPlayerIndex)
    world.hp[playerId].current = 0
    game:update(game:getFixedDt(), neutralFrameInputs())
end

local function prepareControlledDuel(game)
    waitForPlaying(game)

    local world = game:getWorld()
    local shooterId = findPlayerIdByIndex(world, 1)
    local targetId = findPlayerIdByIndex(world, 2)
    local shooterGunId = findGunIdByOwner(world, shooterId)
    local targetGunId = findGunIdByOwner(world, targetId)

    -- Keep both players on the flat ground lane. These coordinates avoid the
    -- center pillars, keep the target within bullet lifetime range, and make a
    -- horizontal shot at angle 0 travel through empty space.
    setPosition(world, shooterId, CONTROLLED_DUEL.shooterX, CONTROLLED_DUEL.y)
    setPosition(world, targetId, CONTROLLED_DUEL.targetX, CONTROLLED_DUEL.y)

    world.velocity[shooterId].dx = 0
    world.velocity[shooterId].dy = 0
    world.velocity[targetId].dx = 0
    world.velocity[targetId].dy = 0

    resetGrounded(world.grounded[shooterId])
    resetGrounded(world.grounded[targetId])

    resetGun(world.gun[shooterGunId], CONTROLLED_DUEL.muzzleOffsetX)
    resetGun(world.gun[targetGunId], CONTROLLED_DUEL.muzzleOffsetX)

    return {
        world = world,
        shooterId = shooterId,
        targetId = targetId,
        shooterGunId = shooterGunId,
        targetGunId = targetGunId,
    }
end

local function playerFireInputs(aimAngle, reload)
    return function()
        return {
            [1] = { up = false, dn = false, lt = false, rt = false, fire = true, reload = reload or false, aimAngle = aimAngle },
            [2] = { up = false, dn = false, lt = false, rt = false, fire = false, reload = false, aimAngle = math.pi },
        }
    end
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

local function assertDeterminism()
    local hashA = runDeterminismSimulation(9999, 1200)
    local hashB = runDeterminismSimulation(9999, 1200)

    assert(
        hashA == hashB,
        string.format("Determinism check failed: identical runs diverged (hashA=%d, hashB=%d)", hashA, hashB)
    )
    assert(
        hashA == EXPECTED_HASH,
        string.format(
            "Determinism regression: expected hash %d, got %d (second run %d)",
            EXPECTED_HASH,
            hashA,
            hashB
        )
    )

    return hashA
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

    local roundRestartFrames = framesForSeconds(game:getState().waitTimer, game:getFixedDt(), 6)
    advanceUntil(game, function()
        return game:getState().gameState == "playing"
    end, roundRestartFrames)

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

local function assertCombatPathKnockout()
    local game = Game.new()
    game:load()

    local duel = prepareControlledDuel(game)
    local targetHp = game:getWorld().hp[duel.targetId]
    assert(targetHp and targetHp.current == 100, "Controlled duel should start the target at full health")

    local expectedHpByHit = { 65, 30 }
    local observedHp = {}
    local firingInputs = playerFireInputs(0, false)
    local targetDied = false

    advanceUntil(game, function()
        local world = game:getWorld()
        local hpComp = world.hp[duel.targetId]
        if hpComp then
            local nextExpected = expectedHpByHit[#observedHp + 1]
            if nextExpected and hpComp.current == nextExpected then
                observedHp[#observedHp + 1] = hpComp.current
            end
            return false
        end

        targetDied = true
        return true
    end, framesForSeconds(5, game:getFixedDt(), 0), firingInputs)

    assert(
        #observedHp == 2 and observedHp[1] == 65 and observedHp[2] == 30,
        string.format(
            "Pistol damage path should step target HP through 65 then 30 before death (observed: %s)",
            #observedHp > 0 and table.concat(observedHp, ", ") or "none"
        )
    )
    assert(targetDied, "Target player should die after the third confirmed hit")
    assert(game:getWorld().hp[duel.targetId] == nil, "Target HP component should be removed after death")
    assert(game:getState().gameState == "roundOver", "Real combat knockout should end the round")
    assert(game:getState().scores[1] == 1, "Real combat knockout should increment player 1's score")
end

local function assertReload()
    local game = Game.new()
    game:load()

    local duel = prepareControlledDuel(game)
    local gun = game:getWorld().gun[duel.shooterGunId]
    local emptyMagazineInputs = playerFireInputs(-math.pi / 2, false)

    advanceUntil(game, function()
        return gun.currentAmmo == 0 and gun.isReloading
    end, framesForSeconds(5, game:getFixedDt(), 0), emptyMagazineInputs)

    assert(gun.currentAmmo == 0, "Pistol should reach empty ammo before completing auto-reload")
    assert(gun.isReloading, "Empty magazine should trigger auto-reload")

    advanceFrames(game, emptyMagazineInputs, 1)
    assert(gun.currentAmmo == 0, "Holding fire during reload should not create an extra shot")
    assert(gun.isReloading, "Gun should still be reloading on the next frame")

    local reloadFrames = framesForSeconds(gun.reloadTimer > 0 and gun.reloadTimer or gun.reloadTime, game:getFixedDt(), 1)
    advanceUntil(game, function()
        return not gun.isReloading and gun.currentAmmo == gun.maxAmmo
    end, reloadFrames)

    assert(gun.currentAmmo == gun.maxAmmo, "Reload should refill the magazine to max ammo")
    assert(not gun.isReloading, "Reload should clear the reloading flag when complete")
end

local function assertDrawFlow()
    local game = Game.new()
    game:load()

    waitForPlaying(game)

    local world = game:getWorld()
    local playerOneId = findPlayerIdByIndex(world, 1)
    local playerTwoId = findPlayerIdByIndex(world, 2)
    world.hp[playerOneId].current = 0
    world.hp[playerTwoId].current = 0

    game:update(game:getFixedDt(), neutralFrameInputs())
    assert(game:getState().gameState == "roundOver", "Simultaneous death should still transition through roundOver")
    assert(game:getState().roundWinner == game:getState().DRAW, "Simultaneous death should register as a draw")
    assert(game:getState().scores[1] == 0 and game:getState().scores[2] == 0, "Draws should not award points")

    -- This documents the current draw behavior so a future UX/gameplay change can
    -- update the test deliberately instead of silently changing round flow.
    game:update(game:getFixedDt(), neutralFrameInputs())
    assert(game:getState().gameState == "waiting", "Current draw behavior should restart the round on the next tick")
end

local deterministicHash = assertDeterminism()
assertLifecycle()
assertCombatPathKnockout()
assertReload()
assertDrawFlow()

print("lua_test.lua passed")
print("Deterministic hash: " .. deterministicHash)
