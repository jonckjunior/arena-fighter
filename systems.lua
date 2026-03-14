local World    = require "world"
local Spawners = require "spawners"


---@class Systems
local Systems = {}

function Systems.gunFollow(w)
    for gid in pairs(w.equippedBy) do
        local ownerId = w.equippedBy[gid].ownerId
        local pos     = w.position[ownerId]
        local inp     = w.input[ownerId]
        if not pos or not inp then goto continue end

        local angle       = inp.aimAngle
        local offset      = 4
        w.position[gid].x = pos.x + math.cos(angle) * offset
        w.position[gid].y = pos.y + math.sin(angle) * offset + 12

        -- store rotation and vertical flip on animation for draw to use
        if w.animation[gid] then
            w.animation[gid].angle = angle
            w.animation[gid].flipY = math.cos(angle) < 0 and -1 or 1
        end
        ::continue::
    end
end

function Systems.gunCooldown(w)
    for id, gun in pairs(w.gun) do
        if gun.cooldown > 0 then
            gun.cooldown = gun.cooldown - 1
        end
    end
end

function Systems.lifetime(w)
    for id, lt in pairs(w.lifetime) do
        lt.ttl = lt.ttl - FIXED_DT
        if lt.ttl <= 0 then
            World.destroy(w, id)
        end
    end
end

---Returns a raw input table for one local player
---@param playerIndex integer
function Systems.gatherLocalInput(playerIndex)
    local inp = {}

    if playerIndex == 1 then
        inp.up       = love.keyboard.isDown("w")
        inp.dn       = love.keyboard.isDown("s")
        inp.lt       = love.keyboard.isDown("a")
        inp.rt       = love.keyboard.isDown("d")
        inp.fire     = love.mouse.isDown(1)
        -- aim angle stays as float for now, quantize later
        inp.aimAngle = 0
    elseif playerIndex == 2 then
        inp.up       = love.keyboard.isDown("i")
        inp.dn       = love.keyboard.isDown("k")
        inp.lt       = love.keyboard.isDown("j")
        inp.rt       = love.keyboard.isDown("l")
        inp.fire     = love.keyboard.isDown("space")
        inp.aimAngle = 0
    end

    return inp
end

function Systems.fillAimAngles(frameInputs, w)
    for id, pidx in pairs(w.playerIndex) do
        local inp = frameInputs[pidx.index]
        local pos = w.position[id]
        if inp and pos then
            -- for now all players use the mouse, split-screen aim comes later
            local mx = love.mouse.getX() / scaleFactor
            local my = love.mouse.getY() / scaleFactor
            inp.aimAngle = math.atan2(my - pos.y, mx - pos.x)
        end
    end
end

function Systems.applyInputs(w, frameInputs)
    for id, pidx in pairs(w.playerIndex) do
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
    for gid, gun in pairs(w.gun) do
        local eq = w.equippedBy[gid]
        if not eq then goto continue end

        local ownerId = eq.ownerId
        local inp     = w.input[ownerId]
        local gunPos  = w.position[gid]
        local anim    = w.animation[gid]
        if not inp or not gunPos or not anim then goto continue end

        if inp.fire and gun.cooldown == 0 then
            local angle   = inp.aimAngle
            local iw      = anim.frames[anim.current]:getWidth()
            local muzzleX = gunPos.x + math.cos(angle) * (iw / 2)
            local muzzleY = gunPos.y + math.sin(angle) * (iw / 2)

            for i = 1, gun.bulletCount do
                local spreadAngle = (math.random() - 0.5) * 2 * gun.spread
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

-- Translate input → velocity
---@param w World
---@param dt number
function Systems.inputToMovement(w, dt)
    for id in pairs(w.input) do
        if not w.velocity[id] or not w.speed[id] then goto continue end

        local inp      = w.input[id]
        local targetDx = (inp.rt and 1 or 0) - (inp.lt and 1 or 0)
        local targetDy = (inp.dn and 1 or 0) - (inp.up and 1 or 0)

        -- Normalize diagonal movement
        if targetDx ~= 0 and targetDy ~= 0 then
            targetDx = targetDx * 1
            targetDy = targetDy * 1
        end

        w.velocity[id].dx = targetDx * w.speed[id].value
        w.velocity[id].dy = targetDy * w.speed[id].value

        w.facing[id].dir = math.cos(inp.aimAngle) >= 0 and 1 or -1

        -- Apply movement
        if w.position[id] then
            w.position[id].x = w.position[id].x + w.velocity[id].dx * dt
            w.position[id].y = w.position[id].y + w.velocity[id].dy * dt
        end

        if w.animation[id] then
            w.animation[id].isPlaying = (targetDx ~= 0 or targetDy ~= 0)
        end
        ::continue::
    end
end

function Systems.applyVelocity(w, dt)
    for id in pairs(w.velocity) do
        if w.input[id] or not w.position[id] then goto continue end

        w.position[id].x = w.position[id].x + w.velocity[id].dx * dt
        w.position[id].y = w.position[id].y + w.velocity[id].dy * dt
        ::continue::
    end
end

function Systems.bulletTerrainCollision(w)
    local solids = {}
    for id in pairs(w.solid) do
        if w.position[id] and w.collider[id] then
            solids[#solids + 1] = id
        end
    end

    for bid in pairs(w.bullet) do
        if not w.position[bid] or not w.collider[bid] then goto continue end

        for _, sid in ipairs(solids) do
            local dx   = w.position[bid].x - w.position[sid].x
            local dy   = w.position[bid].y - w.position[sid].y
            local minD = w.collider[bid].radius + w.collider[sid].radius

            if dx * dx + dy * dy < minD * minD then
                World.destroy(w, bid)
                break -- bullet is gone, no point checking remaining solids
            end
        end
        ::continue::
    end
end

-- Advance sprite animation
---@param w World
---@param dt number
function Systems.animation(w, dt)
    for id, anim in pairs(w.animation) do
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
    local drawables = {}
    for id in pairs(w.animation) do
        if w.position[id] then
            drawables[#drawables + 1] = id
        end
    end

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

        -- when flipping, offset x by sprite width so it doesn't slide left
        local ox   = dir == -1 and iw or 0
        love.graphics.draw(
            img,
            math.floor(pos.x + 0.5),
            math.floor(pos.y + 0.5),
            anim.angle or 0,
            dir,
            anim.flipY or 1,
            iw / 2,
            ih / 2
        )
    end

    if DEBUG then
        for id in pairs(w.collider) do
            if w.position[id] then
                local pos = w.position[id]
                local r   = w.collider[id].radius
                love.graphics.setColor(1, 0, 0, 0.5)
                love.graphics.circle("fill", pos.x, pos.y, r)
                love.graphics.setColor(1, 1, 1)
            end
        end
    end
end

---Resolves collisions
---@param w World
function Systems.collisionResolution(w)
    -- Collect solids once per frame
    local solids = {}
    for id in pairs(w.solid) do
        if w.position[id] and w.collider[id] then
            solids[#solids + 1] = id
        end
    end

    -- Only move entities that have velocity (players, not barrels)
    for id in pairs(w.velocity) do
        if not w.position[id] or not w.collider[id] then goto continue end

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
        ::continue::
    end
end

return Systems
