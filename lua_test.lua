local Game            = require "game"
local Rng             = require "rng"
local World           = require "world"

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

local function countEntries(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
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

local function assertSnapshotRoundTrip()
    local sourceGame = Game.new()
    sourceGame:load()

    local duel = prepareControlledDuel(sourceGame)
    local sourceWorld = sourceGame:getWorld()
    local sourceGun = sourceWorld.gun[duel.shooterGunId]
    local emptyMagazineInputs = playerFireInputs(-math.pi / 2, false)

    advanceUntil(sourceGame, function()
        return sourceGun.currentAmmo == 0 and sourceGun.isReloading
    end, framesForSeconds(5, sourceGame:getFixedDt(), 0), emptyMagazineInputs)

    sourceWorld.rng:random()
    sourceWorld.rng:random()

    local snapshotA = World.saveState(sourceWorld)
    local hashA = World.hashState(snapshotA)

    local destinationGame = Game.new()
    destinationGame:load()
    waitForPlaying(destinationGame)

    local destinationWorld = destinationGame:getWorld()
    local staleId = World.newEntity(destinationWorld)
    destinationWorld.position[staleId] = { x = -999, y = -888, px = -999, py = -888 }
    destinationWorld.velocity[staleId] = { dx = 111, dy = 222 }
    destinationWorld.mapAssetId = "stale_map"
    destinationWorld.mapWidth = 1
    destinationWorld.mapHeight = 2
    destinationWorld.rng:setState(7)

    World.writeState(destinationWorld, snapshotA)

    local snapshotB = World.saveState(destinationWorld)
    local hashB = World.hashState(snapshotB)

    assert(
        hashA == hashB,
        string.format("World snapshot round-trip should preserve exact state (hashA=%d, hashB=%d)", hashA, hashB)
    )

    assert(snapshotB.nextId == snapshotA.nextId, "writeState should restore nextId")
    assert(snapshotB.rngState == snapshotA.rngState, "writeState should restore RNG state")
    assert(snapshotB.mapAssetId == snapshotA.mapAssetId, "writeState should restore map asset id")
    assert(snapshotB.mapWidth == snapshotA.mapWidth and snapshotB.mapHeight == snapshotA.mapHeight,
        "writeState should restore map dimensions")
    assert(countEntries(snapshotB.entities) == countEntries(snapshotA.entities),
        "writeState should restore the exact entity count")

    assert(destinationWorld.entities[staleId] == nil, "writeState should remove stale entities from the destination world")
    assert(destinationWorld.position[staleId] == nil and destinationWorld.velocity[staleId] == nil,
        "writeState should remove stale components from the destination world")

    local savedGun = snapshotA.gun[duel.shooterGunId]
    local writtenGun = snapshotB.gun[duel.shooterGunId]
    assert(savedGun ~= nil and writtenGun ~= nil, "Round-trip should preserve the shooter's gun component")
    assert(writtenGun.currentAmmo == savedGun.currentAmmo, "writeState should preserve gun ammo")
    assert(writtenGun.isReloading == savedGun.isReloading, "writeState should preserve gun reload state")
    assert(writtenGun.reloadTimer == savedGun.reloadTimer, "writeState should preserve gun reload timer")

    local savedInput = snapshotA.input[duel.shooterId]
    local writtenInput = snapshotB.input[duel.shooterId]
    assert(savedInput ~= nil and writtenInput ~= nil, "Round-trip should preserve the shooter's input component")
    assert(#writtenInput.inputHistory == #savedInput.inputHistory, "writeState should preserve input history length")
    assert(#writtenInput.inputHistory > 0, "Fixture should produce non-empty input history before snapshotting")
    assert(writtenInput.inputHistory[1].fire == savedInput.inputHistory[1].fire,
        "writeState should preserve the latest input history entry")
    assert(writtenInput.inputHistory[1].reload == savedInput.inputHistory[1].reload,
        "writeState should preserve reload input history")
    assert(writtenInput.inputHistory[1].aimAngle == savedInput.inputHistory[1].aimAngle,
        "writeState should preserve aim angle history")

    local savedAnimation = snapshotA.animation[duel.shooterGunId]
    local writtenAnimation = snapshotB.animation[duel.shooterGunId]
    assert(savedAnimation ~= nil and writtenAnimation ~= nil, "Round-trip should preserve gun animation state")
    assert(#writtenAnimation.frameIds == #savedAnimation.frameIds, "writeState should preserve animation frame ids")
    assert(writtenAnimation.frameIds[1] == savedAnimation.frameIds[1],
        "writeState should preserve animation frame ordering")
end

local function assertRollback()
    local game = Game.new({ rollbackWindowSize = 5 })
    game:load()

    assert(game:getSimulationFrame() == 0, "Simulation frame should start at 0")
    assert(not game:canRollbackToFrame(0), "Rollback history should be empty before playing starts")

    waitForPlaying(game)
    assert(game:getState().gameState == "playing", "Fixture should reach playing state")
    assert(game:getSimulationFrame() == 0, "Entering playing should not advance the simulation frame yet")
    assert(not game:canRollbackToFrame(0), "Entering playing should not create a snapshot until the first gameplay tick")

    local duel = prepareControlledDuel(game)
    local rollbackInputs = playerFireInputs(-math.pi / 2, false)

    advanceFrames(game, rollbackInputs, 1)
    assert(game:getSimulationFrame() == 1, "First playing tick should advance the simulation frame to 1")
    assert(game:canRollbackToFrame(0), "First playing tick should record the start-of-frame-0 snapshot")

    local snapshot0 = World.saveState(game:getWorld())
    local hash0 = World.hashState(snapshot0)

    advanceUntil(game, function()
        if game:getSimulationFrame() < 3 then
            return false
        end

        for _ in pairs(game:getWorld().bullet) do
            return true
        end
        return false
    end, framesForSeconds(2, game:getFixedDt(), 0), rollbackInputs)

    local targetFrame = game:getSimulationFrame() - 1
    assert(targetFrame >= 1, "Fixture should advance beyond the first recorded frame")
    assert(game:canRollbackToFrame(targetFrame), "Recently simulated frames should be rollbackable")
    local targetHash = World.hashState(game:getState().rollbackSnapshotsByFrame[targetFrame])

    local staleId = World.newEntity(game:getWorld())
    game:getWorld().position[staleId] = { x = 999, y = 999, px = 999, py = 999 }
    game:getWorld().velocity[staleId] = { dx = 1, dy = 2 }

    advanceFrames(game, rollbackInputs, 2)
    local changedHash = World.hashState(World.saveState(game:getWorld()))
    assert(changedHash ~= hash0, "Later simulation should diverge from the first post-tick world state")

    local missingFrame = game:getSimulationFrame() + 10
    local preMissingHash = World.hashState(World.saveState(game:getWorld()))
    assert(not game:rollbackToFrame(missingFrame), "Rollback to an unknown frame should fail")
    assert(
        World.hashState(World.saveState(game:getWorld())) == preMissingHash,
        "Failed rollback should leave the world unchanged"
    )

    assert(game:rollbackToFrame(targetFrame), "Rollback to a recorded frame should succeed")
    assert(game:getSimulationFrame() == targetFrame, "Rollback should restore the requested simulation frame")
    assert(game:getDrawAlpha() == 0, "Rollback should clear interpolation state by resetting the accumulator")

    local rolledBackSnapshot = World.saveState(game:getWorld())
    local rolledBackHash = World.hashState(rolledBackSnapshot)
    assert(rolledBackHash == targetHash, "Rollback should restore the exact target snapshot")

    assert(game:getWorld().entities[staleId] == nil, "Rollback should remove entities created after the target frame")
    assert(game:getWorld().position[staleId] == nil and game:getWorld().velocity[staleId] == nil,
        "Rollback should remove later component data")

    assert(game:getWorld().gun[duel.shooterGunId].isReloading == rolledBackSnapshot.gun[duel.shooterGunId].isReloading,
        "Rollback should restore gun reload state")
    assert(game:getWorld().input[duel.shooterId].inputHistory[1].fire == rolledBackSnapshot.input[duel.shooterId].inputHistory[1].fire,
        "Rollback should restore input history")
    assert(not game:canRollbackToFrame(targetFrame + 1), "Rollback should discard future history beyond the restored frame")

    advanceFrames(game, rollbackInputs, 7)
    assert(not game:canRollbackToFrame(0), "History should evict the oldest frame once it exceeds the rollback cap")
    assert(game:canRollbackToFrame(game:getSimulationFrame() - 1), "Recent frames should remain rollbackable after pruning")

    knockOutPlayer(game, 2)
    assert(game:getState().gameState == "roundOver", "Fixture should enter roundOver after a knockout")
    local roundRestartFrames = framesForSeconds(game:getState().waitTimer, game:getFixedDt(), 6)
    advanceUntil(game, function()
        return game:getState().gameState == "playing"
    end, roundRestartFrames)
    assert(game:getSimulationFrame() == 0, "Starting a new round should reset the simulation frame")
    assert(not game:canRollbackToFrame(0), "Starting a new round should clear rollback history")
end

local deterministicHash = assertDeterminism()
assertLifecycle()
assertCombatPathKnockout()
assertReload()
assertDrawFlow()
assertSnapshotRoundTrip()
assertRollback()

print("lua_test.lua passed")
print("Deterministic hash: " .. deterministicHash)
