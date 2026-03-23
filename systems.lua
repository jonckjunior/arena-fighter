local World            = require "world"
local Spawners         = require "spawners"
local C                = require "components"
local Utils            = require "utils"
local FM               = require "fixedmath"
local PLAYER_CONSTANTS = require "player_constants"

local rng              = love.math.newRandomGenerator(12345)

-- ── Collision helpers ─────────────────────────────────────────────────────────
-- circleHitsRect: returns true when a circle (center cx,cy radius r) overlaps
-- a rect (center rx,ry size rw×rh). Used only for bullet hit detection — bullets
-- are always circles, terrain and players are always rects.
local function circleHitsRect(cx, cy, r, rx, ry, rw, rh)
    local nearX = math.max(rx - rw * 0.5, math.min(cx, rx + rw * 0.5))
    local nearY = math.max(ry - rh * 0.5, math.min(cy, ry + rh * 0.5))
    local dx    = cx - nearX
    local dy    = cy - nearY
    return dx * dx + dy * dy < r * r
end

-- ── Systems ───────────────────────────────────────────────────────────────────

---@class Systems
local Systems = {}

function Systems.gunFollow(w)
    local guns = World.query(w, C.Name.equippedBy, C.Name.position, C.Name.animation)
    for _, gid in ipairs(guns) do
        local ownerId = w.equippedBy[gid].ownerId
        local pos     = w.position[ownerId]
        local inp     = w.input[ownerId]
        if not pos or not inp then goto continue end

        local angle            = inp.aimAngle
        local offset           = 4
        w.position[gid].x      = pos.x + FM.cos(angle) * offset
        w.position[gid].y      = pos.y + FM.sin(angle) * offset

        -- store rotation and vertical flip on animation for draw to use
        w.animation[gid].angle = angle
        w.animation[gid].flipY = FM.cos(angle) < 0 and -1 or 1
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
function Systems.gatherLocalInput(playerIndex, w, mx, my, USE_NETWORK)
    local inp
    if playerIndex == 1 or USE_NETWORK then
        inp = {
            up       = love.keyboard.isDown("w"),
            dn       = love.keyboard.isDown("s"),
            lt       = love.keyboard.isDown("a"),
            rt       = love.keyboard.isDown("d"),
            fire     = love.mouse.isDown(1),
            aimAngle = 0,
        }
    else
        inp = {
            up       = love.keyboard.isDown("u"),
            dn       = love.keyboard.isDown("j"),
            lt       = love.keyboard.isDown("h"),
            rt       = love.keyboard.isDown("k"),
            fire     = love.keyboard.isDown("space"),
            aimAngle = 0,
        }
    end


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
            w.input[id].prevUp   = w.input[id].up
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
            local muzzleX = gunPos.x + FM.cos(angle) * (iw / 2)
            local muzzleY = gunPos.y + FM.sin(angle) * (iw / 2)

            for i = 1, gun.bulletCount do
                local spreadAngle = (rng:random() - 0.5) * 2 * gun.spread
                local a           = angle + spreadAngle
                Spawners.bullet(w, ownerId, muzzleX, muzzleY,
                    FM.cos(a) * gun.bulletSpeed,
                    FM.sin(a) * gun.bulletSpeed,
                    gun.damage)
            end
            gun.cooldown = gun.maxCooldown
        end
        ::continue::
    end
end

---Reads the input for each entity and apply it's velocity to its position. It also alters the animation state.
---@param w World
---@param dt number
function Systems.inputToVelocity(w, dt)
    local idsToUpdate = World.query(w, C.Name.input, C.Name.speed, C.Name.velocity, C.Name.position, C.Name.jumpTimers)
    for _, id in ipairs(idsToUpdate) do
        local inp           = w.input[id]
        local jmp           = w.jumpTimers[id]
        local targetDx      = (inp.rt and 1 or 0) - (inp.lt and 1 or 0)

        -- Horizontal movement: overwrite dx every frame from input
        w.velocity[id].dx   = targetDx * w.speed[id].value

        local isGroundedNow = w.grounded[id] and w.grounded[id].value
        local hasCoyote     = jmp.coyoteTime > 0
        local wantsJump     = (inp.up and not inp.prevUp) or (jmp.jumpBuffer > 0)
        if wantsJump and (isGroundedNow or hasCoyote) then
            w.velocity[id].dy = -PLAYER_CONSTANTS.JUMP_SPEED
            jmp.jumpBuffer    = 0 -- consume buffer
            jmp.coyoteTime    = 0 -- consume coyote window
        end

        if not inp.up and w.velocity[id].dy < 0 then
            local cutoff = -PLAYER_CONSTANTS.JUMP_SPEED * PLAYER_CONSTANTS.VARIABLE_JUMP_CUTOFF
            if w.velocity[id].dy < cutoff then
                w.velocity[id].dy = cutoff
            end
        end
        if inp.dn and w.grounded[id] and w.grounded[id].value == false then
            w.velocity[id].dy = w.velocity[id].dy + PLAYER_CONSTANTS.FALL_FASTER_FORCE
        end

        w.facing[id].dir = FM.cos(inp.aimAngle) >= 0 and 1 or -1

        if w.animation[id] then
            w.animation[id].isPlaying = (targetDx ~= 0) and (w.grounded[id] and w.grounded[id].value)
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

---Saves the current position before they're modified
---@param w World
function Systems.snapshotPositions(w)
    for _, id in pairs(w.position) do
        id.px = id.x
        id.py = id.y
    end
end

---Check collision between a bullet and terrain. If any, destroy bullet.
---@param w World
function Systems.bulletTerrainCollision(w)
    local solids    = World.query(w, C.Name.solid, C.Name.position, C.Name.collider)
    local toDestroy = {}

    local bullets   = World.query(w, C.Name.bullet, C.Name.position, C.Name.collider)
    for _, bid in ipairs(bullets) do
        local bullet = w.bullet[bid]
        if bullet.graceFrames > 0 then
            bullet.graceFrames = bullet.graceFrames - 1
            goto continueBullet
        end

        local bpos = w.position[bid]
        local r    = w.collider[bid].radius
        for _, sid in ipairs(solids) do
            local spos = w.position[sid]
            local scol = w.collider[sid]
            if circleHitsRect(bpos.x, bpos.y, r, spos.x, spos.y, scol.w, scol.h) then
                toDestroy[#toDestroy + 1] = bid
                break
            end
        end
        ::continueBullet::
    end

    for _, bid in ipairs(toDestroy) do
        World.destroy(w, bid)
    end
end

---@param w World
function Systems.bulletPlayerCollision(w)
    local players   = World.query(w, C.Name.hp, C.Name.position, C.Name.collider)
    local toDestroy = {}

    local bullets   = World.query(w, C.Name.bullet, C.Name.position, C.Name.collider)
    for _, bid in ipairs(bullets) do
        local bullet = w.bullet[bid]
        local bpos   = w.position[bid]
        local r      = w.collider[bid].radius
        local hits   = {}

        for _, pid in ipairs(players) do
            if pid == bullet.ownerId then goto continuePlayer end
            local pcol = w.collider[pid]
            if circleHitsRect(bpos.x, bpos.y, r, w.position[pid].x, w.position[pid].y, pcol.w, pcol.h) then
                hits[#hits + 1] = pid
            end
            ::continuePlayer::
        end

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
function Systems.draw(w, alpha)
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
        local rx   = pos.px + (pos.x - pos.px) * alpha
        local ry   = pos.py + (pos.y - pos.py) * alpha
        love.graphics.draw(
            img,
            rx,
            ry,
            anim.angle or 0,
            dir,
            anim.flipY or 1,
            iw / 2,
            ih / 2
        )
    end

    if DEBUG then
        for _, id in ipairs(World.query(w, C.Name.position, C.Name.collider)) do
            local pos = w.position[id]
            local col = w.collider[id]
            love.graphics.setColor(1, 0, 0, 0.5)
            if col.shape == "circle" then
                love.graphics.circle("fill", pos.x, pos.y, col.radius)
            elseif col.shape == "rect" then
                love.graphics.rectangle("fill", pos.x - col.w * 0.5, pos.y - col.h * 0.5, col.w, col.h)
            end
            love.graphics.setColor(1, 1, 1)
        end
    end
end

---@param w World
function Systems.drawHpBars(w, alpha)
    local BAR_W  = 24
    local BAR_H  = 3
    local OFFSET = -14 -- pixels below entity center


    local idsToUpdate = World.query(w, C.Name.hp, C.Name.position)
    for _, id in ipairs(idsToUpdate) do
        local hp   = w.hp[id]
        local pos  = w.position[id]
        local rx   = pos.px + (pos.x - pos.px) * alpha
        local ry   = pos.py + (pos.y - pos.py) * alpha
        local left = rx - BAR_W / 2
        local top  = ry + OFFSET
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

---Moves player-controlled entities using axis-separated AABB sweeps.
--- Pass 1: move X, resolve horizontal contacts → sets wallDir.
--- Pass 2: move Y, resolve vertical contacts   → sets grounded.
--- Ground probe: catches the standing-still case (vel.dy=0, no Y movement).
---@param w World
---@param dt number
function Systems.playerMove(w, dt)
    local solids = World.query(w, C.Name.solid, C.Name.position, C.Name.collider)
    local movers = World.query(w, C.Name.input, C.Name.velocity, C.Name.position,
        C.Name.collider, C.Name.grounded)

    for _, id in ipairs(movers) do
        w.grounded[id].value   = false
        w.grounded[id].wallDir = 0
    end

    for _, id in ipairs(movers) do
        local vel    = w.velocity[id]
        local pos    = w.position[id]
        local col    = w.collider[id]
        local halfAW = col.w * 0.5
        local halfAH = col.h * 0.5

        -- Pass 1: move X ───────────────────────────────────────────────────
        pos.x        = pos.x + vel.dx * dt
        for _, sid in ipairs(solids) do
            local sc = w.collider[sid]
            local sx, sy = w.position[sid].x, w.position[sid].y
            local ox = (halfAW + sc.w * 0.5) - math.abs(pos.x - sx)
            local oy = (halfAH + sc.h * 0.5) - math.abs(pos.y - sy)
            if ox > 0 and oy > 0 then
                local nx = (pos.x >= sx) and 1 or -1
                pos.x = pos.x + nx * ox
                if nx * vel.dx < 0 then vel.dx = 0 end
                w.grounded[id].wallDir = -nx
            end
        end

        -- Pass 2: move Y ───────────────────────────────────────────────────
        pos.y = pos.y + vel.dy * dt
        for _, sid in ipairs(solids) do
            local sc = w.collider[sid]
            local sx, sy = w.position[sid].x, w.position[sid].y
            local ox = (halfAW + sc.w * 0.5) - math.abs(pos.x - sx)
            local oy = (halfAH + sc.h * 0.5) - math.abs(pos.y - sy)
            if ox > 0 and oy > 0 then
                local ny = (pos.y >= sy) and 1 or -1
                pos.y = pos.y + ny * oy
                if ny < 0 then
                    w.grounded[id].value = true
                    if vel.dy > 0 then vel.dy = 0 end
                else
                    if vel.dy < 0 then vel.dy = 0 end
                end
            end
        end

        -- Ground probe ─────────────────────────────────────────────────────
        if not w.grounded[id].value then
            local probeY = pos.y + 1
            for _, sid in ipairs(solids) do
                local sc = w.collider[sid]
                local sx, sy = w.position[sid].x, w.position[sid].y
                local ox = (halfAW + sc.w * 0.5) - math.abs(pos.x - sx)
                local oy = (halfAH + sc.h * 0.5) - math.abs(probeY - sy)
                if ox > 0 and oy > 0 and probeY < sy then
                    w.grounded[id].value = true
                    break
                end
            end
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

---@param w World
---@return boolean
function Systems.isRoundOver(w)
    local alive = World.query(w, C.Name.playerIndex, C.Name.hp)
    return #alive <= 1
end

--- Check if the round is over. Returns the index of the winner or -1 if draw
---@param w World
---@return integer
function Systems.getRoundWinner(w)
    local alive = World.query(w, C.Name.playerIndex, C.Name.hp)
    if #alive == 1 then
        return w.playerIndex[alive[1]].index
    else
        return -1 -- draw
    end
end

function Systems.presentEffects(w, localPlayerIndex)
    local listenerX, listenerY = 0, 0
    local players = World.query(w, C.Name.playerIndex, C.Name.position)
    local pid = Utils.find(players, function(id)
        return w.playerIndex[id].index == localPlayerIndex
    end)
    if pid then
        listenerX = w.position[pid].x
        listenerY = w.position[pid].y
        love.audio.setPosition(listenerX, listenerY, 0)
    end

    local toDelete = {}
    for _, id in ipairs(World.query(w, C.Name.soundEvent)) do
        local ev = w.soundEvent[id]
        local src = love.audio.newSource(ev.soundPath, "static")
        if ev.playerIndex == localPlayerIndex then
            -- playSound(ev.soundPath, listenerX, listenerY)
            src:setRelative(true)
            src:setPosition(0, 0, 0)
        else
            -- playSound(ev.soundPath, ev.x, ev.y)
            src:setRelative(false)
            src:setPosition(ev.x, ev.y, 0)
        end
        love.audio.setDistanceModel("linearclamped")
        src:setAttenuationDistances(100, 500)
        src:play()
        toDelete[#toDelete + 1] = id
    end
    for _, id in ipairs(toDelete) do
        World.destroy(w, id)
    end
end

---Computes shake events from the last frame and remove all of them. Returns the event with the highest intensity
---@param w World
---@param localPlayerIndex integer
---@return number
---@return number
function Systems.shakeEvent(w, localPlayerIndex)
    local intensity = 0
    local duration = 0
    local shakeEvents = World.query(w, C.Name.shakeEvent)
    for _, id in ipairs(shakeEvents) do
        local shakeEvent = w.shakeEvent[id]
        if shakeEvent.playerIndex == localPlayerIndex and (shakeEvent.intensity > intensity) then
            intensity = shakeEvent.intensity
            duration = shakeEvent.duration
        end
    end
    for _, id in ipairs(shakeEvents) do
        World.destroy(w, id)
    end
    return intensity, duration
end

function Systems.applyGravity(w, dt)
    for _, id in ipairs(World.query(w, C.Name.gravity, C.Name.velocity)) do
        local isGrounded = w.grounded[id] and w.grounded[id].value
        if not isGrounded then
            -- Half-gravity near the apex: brief hang when |dy| is tiny.
            -- Only for player-controlled entities; bullets fall at full gravity.
            local inp       = w.input[id]
            local nearApex  = math.abs(w.velocity[id].dy) < PLAYER_CONSTANTS.HALF_GRAVITY_THRESHOLD
            local gravScale = (inp and nearApex) and PLAYER_CONSTANTS.GRAVITY_NEAR_PEAK or 1.0

            -- Fast fall: holding down while already falling adds extra pull
            if inp and inp.dn and w.velocity[id].dy > 0 then
                gravScale = gravScale * PLAYER_CONSTANTS.FAST_FALL_MULTIPLIER
            end

            w.velocity[id].dy = w.velocity[id].dy + w.gravity[id].g * dt * gravScale

            if w.velocity[id].dy > PLAYER_CONSTANTS.MAX_FALL_SPEED then
                w.velocity[id].dy = PLAYER_CONSTANTS.MAX_FALL_SPEED
            end
        else
            if w.velocity[id].dy > 0 then
                w.velocity[id].dy = 0
            end
        end
    end
end

---Ticks coyote time and jump buffer for entities that can jump.
--- Must run AFTER updateGrounded so grounded.value is current.
---@param w World
---@param dt number
function Systems.updateJumpTimers(w, dt)
    for _, id in ipairs(World.query(w, C.Name.jumpTimers, C.Name.input, C.Name.grounded)) do
        local inp        = w.input[id]
        local jmp        = w.jumpTimers[id]
        local isGrounded = w.grounded[id].value

        -- Coyote time: full while grounded, drains once airborne
        if isGrounded then
            jmp.coyoteTime = PLAYER_CONSTANTS.COYOTE_TIME
        else
            jmp.coyoteTime = math.max(jmp.coyoteTime - dt, 0)
        end

        -- Jump buffer: set when jump is pressed mid-air (edge only)
        if inp.up and not inp.prevUp and not isGrounded then
            jmp.jumpBuffer = PLAYER_CONSTANTS.JUMP_BUFFER_TIME
        else
            jmp.jumpBuffer = math.max(jmp.jumpBuffer - dt, 0)
        end
    end
end

function Systems.runSystems(w, frameInputs, localPlayerIndex, FIXED_DT)
    Systems.applyInputs(w, frameInputs)
    Systems.snapshotPositions(w)
    Systems.applyGravity(w, FIXED_DT)
    Systems.inputToVelocity(w, FIXED_DT)
    Systems.playerMove(w, FIXED_DT)
    Systems.applyVelocity(w, FIXED_DT)
    Systems.gunCooldown(w)
    Systems.gunFollow(w)
    Systems.firing(w)
    Systems.bulletPlayerCollision(w)
    Systems.bulletTerrainCollision(w)
    Systems.death(w)
    Systems.updateJumpTimers(w, FIXED_DT)
    Systems.animation(w, FIXED_DT)
    Systems.presentEffects(w, localPlayerIndex)
    Systems.lifetime(w, FIXED_DT)
end

return Systems
