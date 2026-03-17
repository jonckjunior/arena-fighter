local World    = require "world"
local Spawners = require "spawners"
local C        = require "components"
local Utils    = require "utils"

local rng      = love.math.newRandomGenerator(12345)

---@class Systems
local Systems  = {}

function Systems.gunFollow(w)
    local guns = World.query(w, C.Name.equippedBy, C.Name.position, C.Name.animation)
    for _, gid in ipairs(guns) do
        local ownerId = w.equippedBy[gid].ownerId
        local pos     = w.position[ownerId]
        local inp     = w.input[ownerId]
        if not pos or not inp then goto continue end

        local angle            = inp.aimAngle
        local offset           = 4
        w.position[gid].x      = pos.x + math.cos(angle) * offset
        w.position[gid].y      = pos.y + math.sin(angle) * offset + 12

        -- store rotation and vertical flip on animation for draw to use
        w.animation[gid].angle = angle
        w.animation[gid].flipY = math.cos(angle) < 0 and -1 or 1
        ::continue::
    end
end

function Systems.gunCooldown(w)
    for _, id in ipairs(World.query(w, C.Name.gun)) do
        local gun = w.gun[id]
        if gun.cooldown > 0 then
            gun.cooldown = gun.cooldown - 1
        end
    end
end

function Systems.lifetime(w, FIXED_DT)
    local toDestroy = {}
    for _, id in ipairs(World.query(w, C.Name.lifetime)) do
        local lt = w.lifetime[id]
        lt.ttl = lt.ttl - FIXED_DT
        if lt.ttl <= 0 then
            toDestroy[#toDestroy + 1] = id
        end
    end

    for _, id in ipairs(toDestroy) do
        World.destroy(w, id)
    end
end

local function getPlayerGun(w, playerId)
    local guns = World.query(w, C.Name.equippedBy, C.Name.position, C.Name.animation)
    local gunId = Utils.find(guns, function(id)
        return w.equippedBy[id].ownerId == playerId
    end)
    return gunId
end

---Returns a raw input table for one player
---@param playerIndex integer
---@param w World
---@param mx number
---@param my number
---@return table
function Systems.gatherLocalInput(playerIndex, w, mx, my)
    local inp     = {
        up       = love.keyboard.isDown("w"),
        dn       = love.keyboard.isDown("s"),
        lt       = love.keyboard.isDown("a"),
        rt       = love.keyboard.isDown("d"),
        fire     = love.mouse.isDown(1),
        aimAngle = 0,
    }

    local players = World.query(w, C.Name.playerIndex, C.Name.position, C.Name.input)
    local pid     = Utils.find(players, function(id)
        return w.playerIndex[id].index == playerIndex
    end)
    if not pid then return inp end

    local gunId = getPlayerGun(w, pid)
    if not gunId then return inp end

    local px, py = w.position[gunId].x, w.position[gunId].y
    local dx, dy = mx - px, my - py
    if dx * dx + dy * dy > 5 * 5 then
        inp.aimAngle = math.atan2(dy, dx)
    else
        inp.aimAngle = w.input[pid].aimAngle
    end
    return inp
end

function Systems.applyInputs(w, frameInputs)
    for _, id in ipairs(World.query(w, C.Name.playerIndex)) do
        local pidx = w.playerIndex[id]
        local inp = frameInputs[pidx.index]
        if inp and w.input[id] then
            w.input[id].up       = inp.up
            w.input[id].dn       = inp.dn
            w.input[id].lt       = inp.lt
            w.input[id].rt       = inp.rt
            w.input[id].fire     = inp.fire
            w.input[id].aimAngle = inp.aimAngle
        end
    end
end

function Systems.firing(w)
    local guns = World.query(w, C.Name.gun, C.Name.equippedBy, C.Name.position, C.Name.animation)
    for _, gid in ipairs(guns) do
        local gun     = w.gun[gid]
        local eq      = w.equippedBy[gid]
        local gunPos  = w.position[gid]
        local anim    = w.animation[gid]

        local ownerId = eq.ownerId
        local inp     = w.input[ownerId]
        if not inp then goto continue end

        if inp.fire and gun.cooldown == 0 then
            local angle   = inp.aimAngle
            local iw      = anim.frames[anim.current]:getWidth()
            local muzzleX = gunPos.x + math.cos(angle) * (iw / 2)
            local muzzleY = gunPos.y + math.sin(angle) * (iw / 2)

            for i = 1, gun.bulletCount do
                local spreadAngle = (rng:random() - 0.5) * 2 * gun.spread
                local a           = angle + spreadAngle
                Spawners.bullet(w, ownerId, muzzleX, muzzleY,
                    math.cos(a) * gun.bulletSpeed,
                    math.sin(a) * gun.bulletSpeed,
                    gun.damage)
            end
            gun.cooldown = gun.maxCooldown
        end
        ::continue::
    end
end

---Reads the input for each entity and apply it's velocity to its position. It also alters the animation state
---@param w World
---@param dt number
function Systems.inputToVelocity(w, dt)
    local idsToUpdate = World.query(w, C.Name.input, C.Name.speed, C.Name.velocity, C.Name.position)
    for _, id in ipairs(idsToUpdate) do
        local inp      = w.input[id]
        local targetDx = (inp.rt and 1 or 0) - (inp.lt and 1 or 0)
        local targetDy = (inp.dn and 1 or 0) - (inp.up and 1 or 0)

        -- Normalize diagonal movement
        if targetDx ~= 0 and targetDy ~= 0 then
            targetDx = targetDx * 0.7071
            targetDy = targetDy * 0.7071
        end

        w.velocity[id].dx = targetDx * w.speed[id].value
        w.velocity[id].dy = targetDy * w.speed[id].value

        w.facing[id].dir = math.cos(inp.aimAngle) >= 0 and 1 or -1

        w.position[id].x = w.position[id].x + w.velocity[id].dx * dt
        w.position[id].y = w.position[id].y + w.velocity[id].dy * dt

        if w.animation[id] then
            w.animation[id].isPlaying = (targetDx ~= 0 or targetDy ~= 0)
        end
    end
end

---Applies the velocity update to position on entities without input
---@param w World
---@param dt number
function Systems.applyVelocity(w, dt)
    local idsToUpdate = World.query(w, C.Name.velocity, C.Name.position)
    for _, id in ipairs(idsToUpdate) do
        if not w.input[id] then
            w.position[id].x = w.position[id].x + w.velocity[id].dx * dt
            w.position[id].y = w.position[id].y + w.velocity[id].dy * dt
        end
    end
end

function Systems.bulletTerrainCollision(w)
    local solids = World.query(w, C.Name.solid, C.Name.position, C.Name.collider)
    local toDestroy = {}

    local bullets = World.query(w, C.Name.bullet, C.Name.position, C.Name.collider)
    for _, bid in ipairs(bullets) do
        for _, sid in ipairs(solids) do
            local dx   = w.position[bid].x - w.position[sid].x
            local dy   = w.position[bid].y - w.position[sid].y
            local minD = w.collider[bid].radius + w.collider[sid].radius

            if dx * dx + dy * dy < minD * minD then
                toDestroy[#toDestroy + 1] = bid
                break -- bullet is gone, no point checking remaining solids
            end
        end
    end

    for _, bid in ipairs(toDestroy) do
        World.destroy(w, bid)
    end
end

---@param w World
function Systems.bulletPlayerCollision(w)
    -- Collect damageable players once — stable list, iteration order irrelevant
    -- since we collect all hits before applying any damage or destroys.
    local players = World.query(w, C.Name.hp, C.Name.position, C.Name.collider)
    local toDestroy = {}

    local bullets = World.query(w, C.Name.bullet, C.Name.position, C.Name.collider)
    for _, bid in ipairs(bullets) do
        local bullet     = w.bullet[bid]
        local bullRadius = w.collider[bid].radius

        -- Collect every player this bullet overlaps this frame.
        -- We don't break early so a large bullet can hit multiple players.
        local hits       = {}
        for _, pid in ipairs(players) do
            if pid == bullet.ownerId then goto continuePlayer end

            local dx   = w.position[bid].x - w.position[pid].x
            local dy   = w.position[bid].y - w.position[pid].y
            local minD = bullRadius + w.collider[pid].radius

            if dx * dx + dy * dy < minD * minD then
                hits[#hits + 1] = pid
            end
            ::continuePlayer::
        end

        -- Apply damage to all hit players, then destroy the bullet.
        -- Doing this after the loop keeps damage application deterministic:
        -- every client sees the same hits table in the same order (ipairs).
        if #hits > 0 then
            for _, pid in ipairs(hits) do
                w.hp[pid].current = w.hp[pid].current - bullet.damage
            end
            toDestroy[#toDestroy + 1] = bid
        end
    end

    for _, bid in ipairs(toDestroy) do
        World.destroy(w, bid)
    end
end

-- Advance sprite animation
---@param w World
---@param dt number
function Systems.animation(w, dt)
    for _, id in ipairs(World.query(w, C.Name.animation)) do
        local anim = w.animation[id]
        if anim.isPlaying then
            anim.timer = anim.timer + dt
            if anim.timer >= anim.duration then
                anim.timer = anim.timer - anim.duration
                anim.current = (anim.current % #anim.frames) + 1
            end
        else
            anim.current = 1
            anim.timer   = 0
        end
    end
end

-- Draw everything with position + animation
---@param w World
function Systems.draw(w)
    -- Collect entities with animation and position, sorted by y-coordinate
    local drawables = World.query(w, C.Name.animation, C.Name.position)
    -- Sort by y-coordinate (ascending) for correct depth ordering
    table.sort(drawables, function(a, b)
        local la = w.drawLayer[a] and w.drawLayer[a].layer or 0
        local lb = w.drawLayer[b] and w.drawLayer[b].layer or 0
        if la ~= lb then
            return la < lb                       -- different layers: sort by layer
        end
        return w.position[a].y < w.position[b].y -- same layer: sort by y
    end)

    -- Draw in sorted order
    for _, id in ipairs(drawables) do
        local pos  = w.position[id]
        local anim = w.animation[id]
        local dir  = w.facing[id] and w.facing[id].dir or 1
        local img  = anim.frames[anim.current]
        local iw   = img:getWidth()
        local ih   = img:getHeight()
        love.graphics.draw(
            img,
            pos.x,
            pos.y,
            anim.angle or 0,
            dir,
            anim.flipY or 1,
            Utils.round(iw / 2),
            Utils.round(ih / 2)
        )
    end

    if DEBUG then
        for _, id in ipairs(World.query(w, C.Name.position, C.Name.collider)) do
            local pos = w.position[id]
            local r   = w.collider[id].radius
            love.graphics.setColor(1, 0, 0, 0.5)
            love.graphics.circle("fill", pos.x, pos.y, r)
            love.graphics.setColor(1, 1, 1)
        end
    end
end

---@param w World
function Systems.drawHpBars(w)
    local BAR_W  = 24
    local BAR_H  = 3
    local OFFSET = -14 -- pixels below entity center


    local idsToUpdate = World.query(w, C.Name.hp, C.Name.position)
    for _, id in ipairs(idsToUpdate) do
        local hp   = w.hp[id]

        local x    = math.floor(w.position[id].x + 0.5)
        local y    = math.floor(w.position[id].y + 0.5)
        local left = x - BAR_W / 2
        local top  = y + OFFSET
        local fill = math.max(0, hp.current / hp.max)

        -- background
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle("fill", left, top, BAR_W, BAR_H)

        -- filled portion
        local r = 1 - fill
        local g = fill
        love.graphics.setColor(r, g, 0)
        love.graphics.rectangle("fill", left, top, BAR_W * fill, BAR_H)

        -- reset color
        love.graphics.setColor(1, 1, 1)
    end
end

---Resolves collisions
---@param w World
function Systems.collisionResolution(w)
    -- Collect solids once per frame
    local solids = World.query(w, C.Name.solid, C.Name.position, C.Name.collider)
    -- Only move entities that have velocity (players, not barrels)
    local idsToUpdate = World.query(w, C.Name.velocity, C.Name.position, C.Name.collider)
    for _, id in ipairs(idsToUpdate) do
        for _, sid in ipairs(solids) do
            if sid == id then goto nextSolid end -- skip self

            local ax, ay = w.position[id].x, w.position[id].y
            local bx, by = w.position[sid].x, w.position[sid].y
            local ra     = w.collider[id].radius
            local rb     = w.collider[sid].radius

            local dx     = ax - bx
            local dy     = ay - by
            local dist   = math.sqrt(dx * dx + dy * dy)
            local minD   = ra + rb

            if dist < minD and dist > 0 then
                -- Push moving entity out along collision normal
                local nx = dx / dist
                local ny = dy / dist
                local overlap = minD - dist
                w.position[id].x = w.position[id].x + nx * overlap
                w.position[id].y = w.position[id].y + ny * overlap
            end

            ::nextSolid::
        end
    end
end

---Destroy entities with 0 hp and their guns (if any)
---@param w World
function Systems.death(w)
    local toDestroy = {}
    for _, id in ipairs(World.query(w, C.Name.hp)) do
        if w.hp[id].current <= 0 then
            toDestroy[#toDestroy + 1] = id
        end
    end
    for _, id in ipairs(toDestroy) do
        -- destroy any guns owned by this entity
        for _, gid in ipairs(World.query(w, C.Name.equippedBy)) do
            if w.equippedBy[gid].ownerId == id then
                World.destroy(w, gid)
            end
        end
        World.destroy(w, id)
    end
end

--- Check if the round is over after death has run.
--- Returns:
---   nil               — round still in progress
---   { winner = id }   — one player remains
---   { winner = nil }  — everyone died on the same frame (draw)
---@param w World
---@return {winner: integer|nil}|nil
function Systems.checkWin(w)
    local alive = World.query(w, C.Name.playerIndex, C.Name.hp)
    if #alive == 1 then return { winner = alive[1] } end
    if #alive == 0 then return { winner = nil } end
    return nil
end

function Systems.runSystems(w, frameInputs, FIXED_DT)
    Systems.applyInputs(w, frameInputs)
    Systems.inputToVelocity(w, FIXED_DT)
    Systems.applyVelocity(w, FIXED_DT)
    Systems.gunCooldown(w)
    Systems.gunFollow(w)
    Systems.firing(w)
    Systems.bulletPlayerCollision(w)
    Systems.bulletTerrainCollision(w)
    Systems.death(w)
    Systems.collisionResolution(w)
    Systems.animation(w, FIXED_DT)
    Systems.lifetime(w, FIXED_DT)
end

return Systems
