local World            = require "world"
local Spawners         = require "spawners"
local C                = require "components"
local Utils            = require "utils"
local FM               = require "fixedmath"

local rng              = love.math.newRandomGenerator(12345)
local JUMP_SPEED       = 142 -- pixels/s upward impulse
local COYOTE_TIME      = 0.3 -- seconds you can still jump after walking off a ledge
local JUMP_BUFFER_TIME = 0.1 -- seconds a jump press is remembered before landing
local MAX_FALL_SPEED   = 300 -- pixels/s terminal velocity (prevents tunnelling)

-- ── Collision helpers ─────────────────────────────────────────────────────────
-- All collision functions treat position as the CENTER of the shape.
--
-- getCollisionMTV returns (overlap, nx, ny):
--   overlap > 0  → shapes are penetrating; push A by (nx*overlap, ny*overlap) to resolve
--   overlap == 0 → no contact
--
-- overlaps is a cheap boolean wrapper used where the MTV isn't needed.

---Circle vs rect MTV. Pushes circle out of rect.
---@param cx number  circle center x
---@param cy number  circle center y
---@param r  number  circle radius
---@param rx number  rect center x
---@param ry number  rect center y
---@param rw number  rect width
---@param rh number  rect height
---@return number overlap, number nx, number ny
local function circleRectMTV(cx, cy, r, rx, ry, rw, rh)
    local halfW = rw * 0.5
    local halfH = rh * 0.5
    -- Closest point on rect boundary to circle center
    local nearX = math.max(rx - halfW, math.min(cx, rx + halfW))
    local nearY = math.max(ry - halfH, math.min(cy, ry + halfH))
    local dx    = cx - nearX
    local dy    = cy - nearY
    local dist  = math.sqrt(dx * dx + dy * dy)
    if dist >= r then return 0, 0, 0 end
    if dist > 0 then
        return r - dist, dx / dist, dy / dist
    else
        -- Circle center is fully inside the rect: push out along the shortest axis
        local ox = halfW - math.abs(cx - rx)
        local oy = halfH - math.abs(cy - ry)
        if ox < oy then
            local sign = cx >= rx and 1 or -1
            return ox + r, sign, 0
        else
            local sign = cy >= ry and 1 or -1
            return oy + r, 0, sign
        end
    end
end

---Returns the MTV to push shape A out of shape B.
---@param ax number  A center x
---@param ay number  A center y
---@param ca table   A collider component
---@param bx number  B center x
---@param by number  B center y
---@param cb table   B collider component
---@return number overlap, number nx, number ny
local function getCollisionMTV(ax, ay, ca, bx, by, cb)
    local sa, sb = ca.shape, cb.shape
    assert(sa, "collider A is missing shape field")
    assert(sb, "collider B is missing shape field")

    if sa == "circle" and sb == "circle" then
        local dx   = ax - bx
        local dy   = ay - by
        local dist = math.sqrt(dx * dx + dy * dy)
        local minD = ca.radius + cb.radius
        if dist < minD then
            if dist > 0 then
                return minD - dist, dx / dist, dy / dist
            else
                return minD, 1, 0 -- degenerate: same center, pick arbitrary axis
            end
        end
    elseif sa == "circle" and sb == "rect" then
        return circleRectMTV(ax, ay, ca.radius, bx, by, cb.w, cb.h)
    elseif sa == "rect" and sb == "circle" then
        -- Reuse circle-rect, then flip normal so it pushes A (the rect) out
        local overlap, nx, ny = circleRectMTV(bx, by, cb.radius, ax, ay, ca.w, ca.h)
        return overlap, -nx, -ny
    elseif sa == "rect" and sb == "rect" then
        local halfAW = ca.w * 0.5
        local halfAH = ca.h * 0.5
        local halfBW = cb.w * 0.5
        local halfBH = cb.h * 0.5
        local dx     = ax - bx
        local dy     = ay - by
        local ox     = (halfAW + halfBW) - math.abs(dx)
        local oy     = (halfAH + halfBH) - math.abs(dy)
        if ox > 0 and oy > 0 then
            if ox < oy then
                return ox, dx >= 0 and 1 or -1, 0
            else
                return oy, 0, dy >= 0 and 1 or -1
            end
        end
    end

    return 0, 0, 0
end

---Simple boolean overlap test (no MTV computed beyond the overlap scalar).
local function overlaps(ax, ay, ca, bx, by, cb)
    return getCollisionMTV(ax, ay, ca, bx, by, cb) > 0
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
    local idsToUpdate = World.query(w, C.Name.input, C.Name.speed, C.Name.velocity, C.Name.position)
    for _, id in ipairs(idsToUpdate) do
        local inp           = w.input[id]
        local targetDx      = (inp.rt and 1 or 0) - (inp.lt and 1 or 0)

        -- Horizontal movement: overwrite dx every frame from input
        w.velocity[id].dx   = targetDx * w.speed[id].value

        -- Jump: fires on the press-edge (false→true) OR when a buffered press is still
        -- active. Allows jumping for COYOTE_TIME seconds after walking off a ledge.
        local isGroundedNow = w.grounded[id] and w.grounded[id].value
        local hasCoyote     = (inp.coyoteTime or 0) > 0
        local wantsJump     = (inp.up and not inp.prevUp) or ((inp.jumpBuffer or 0) > 0)
        if wantsJump and (isGroundedNow or hasCoyote) then
            w.velocity[id].dy = -JUMP_SPEED
            inp.jumpBuffer    = 0 -- consume buffer
            inp.coyoteTime    = 0 -- consume coyote window
        end
        if inp.dn and w.grounded[id] and w.grounded[id].value == false then
            w.velocity[id].dy = w.velocity[id].dy + 10
        end

        w.facing[id].dir = FM.cos(inp.aimAngle) >= 0 and 1 or -1

        w.position[id].x = w.position[id].x + w.velocity[id].dx * dt
        w.position[id].y = w.position[id].y + w.velocity[id].dy * dt

        -- Walk animation only plays while moving on the ground; idle/airborne show frame 1
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
        local bpos = w.position[bid]
        local bcol = w.collider[bid]
        local bullet = w.bullet[bid]
        if bullet.graceFrames > 0 then
            bullet.graceFrames = bullet.graceFrames - 1
            goto continueBullet
        end

        for _, sid in ipairs(solids) do
            local spos = w.position[sid]
            local scol = w.collider[sid]
            if overlaps(bpos.x, bpos.y, bcol, spos.x, spos.y, scol) then
                toDestroy[#toDestroy + 1] = bid
                break -- bullet is gone, no point checking remaining solids
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
        local bcol   = w.collider[bid]
        local hits   = {}

        for _, pid in ipairs(players) do
            if pid == bullet.ownerId then goto continuePlayer end
            if overlaps(bpos.x, bpos.y, bcol, w.position[pid].x, w.position[pid].y, w.collider[pid]) then
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

---Resolves collisions between moving entities and solids using the MTV.
---@param w World
function Systems.collisionResolution(w)
    local solids      = World.query(w, C.Name.solid, C.Name.position, C.Name.collider)
    local idsToUpdate = World.query(w, C.Name.velocity, C.Name.position, C.Name.collider)
    for _, id in ipairs(idsToUpdate) do
        if w.bullet[id] then goto nextEntity end
        local col = w.collider[id]
        for _, sid in ipairs(solids) do
            if sid == id then goto nextSolid end

            local ax, ay          = w.position[id].x, w.position[id].y
            local bx, by          = w.position[sid].x, w.position[sid].y
            local overlap, nx, ny = getCollisionMTV(ax, ay, col, bx, by, w.collider[sid])

            if overlap > 0 then
                w.position[id].x = w.position[id].x + nx * overlap
                w.position[id].y = w.position[id].y + ny * overlap
            end

            ::nextSolid::
        end
        ::nextEntity::
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
            w.velocity[id].dy = w.velocity[id].dy + w.gravity[id].g * dt
            -- Terminal velocity: prevents tunnelling through thin platforms on long falls
            if w.velocity[id].dy > MAX_FALL_SPEED then
                w.velocity[id].dy = MAX_FALL_SPEED
            end
        else
            if w.velocity[id].dy > 0 then
                w.velocity[id].dy = 0
            end
        end
    end
end

function Systems.updateGrounded(w)
    -- clear grounded for everyone first
    for _, id in ipairs(World.query(w, C.Name.grounded)) do
        w.grounded[id].value = false
    end

    local solids = World.query(w, C.Name.solid, C.Name.position, C.Name.collider)
    for _, id in ipairs(World.query(w, C.Name.grounded, C.Name.position, C.Name.collider)) do
        -- The margin: check 1 pixel below the entity
        local checkY = w.position[id].y + 1

        for _, sid in ipairs(solids) do
            if id == sid then goto next_solid end

            local overlap, nx, ny = getCollisionMTV(
                w.position[id].x, checkY, w.collider[id],
                w.position[sid].x, w.position[sid].y, w.collider[sid]
            )

            -- If shifting them down 1 pixel causes an upward overlap, we are on the ground
            if overlap > 0 and ny < -0.5 then
                w.grounded[id].value = true
                break
            end

            ::next_solid::
        end
    end
end

---Ticks coyote time and jump buffer for entities that can jump.
--- Must run AFTER updateGrounded so grounded.value is current.
---@param w World
---@param dt number
function Systems.updateJumpTimers(w, dt)
    for _, id in ipairs(World.query(w, C.Name.input, C.Name.grounded)) do
        local inp        = w.input[id]
        local isGrounded = w.grounded[id].value

        -- Coyote time: full while grounded, drains once airborne
        if isGrounded then
            inp.coyoteTime = COYOTE_TIME
        else
            inp.coyoteTime = math.max((inp.coyoteTime or 0) - dt, 0)
        end

        -- Jump buffer: set when jump is pressed mid-air (edge only)
        if inp.up and not inp.prevUp and not isGrounded then
            inp.jumpBuffer = JUMP_BUFFER_TIME
        else
            inp.jumpBuffer = math.max((inp.jumpBuffer or 0) - dt, 0)
        end
    end
end

function Systems.runSystems(w, frameInputs, localPlayerIndex, FIXED_DT)
    Systems.applyInputs(w, frameInputs)
    Systems.snapshotPositions(w)
    Systems.applyGravity(w, FIXED_DT)
    Systems.inputToVelocity(w, FIXED_DT)
    Systems.applyVelocity(w, FIXED_DT)
    Systems.gunCooldown(w)
    Systems.gunFollow(w)
    Systems.firing(w)
    Systems.bulletPlayerCollision(w)
    Systems.bulletTerrainCollision(w)
    Systems.death(w)
    Systems.collisionResolution(w)
    Systems.updateGrounded(w)
    Systems.updateJumpTimers(w, FIXED_DT)
    Systems.animation(w, FIXED_DT)
    Systems.presentEffects(w, localPlayerIndex)
    Systems.lifetime(w, FIXED_DT)
end

return Systems
