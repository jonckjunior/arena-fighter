---@class Systems
local Systems = {}

local function lerp(a, b, t)
    return a + (b - a) * t
end

---Read keyboard into input components
---@param w World
function Systems.gatherInput(w)
    for id in pairs(w.input) do
        local inp = w.input[id]
        inp.up = love.keyboard.isDown("w")
        inp.dn = love.keyboard.isDown("s")
        inp.lt = love.keyboard.isDown("a")
        inp.rt = love.keyboard.isDown("d")
    end
end

-- Translate input → velocity
---@param w World
---@param dt number
-- systems.lua

function Systems.movement(w, dt)
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

        -- Update facing
        if targetDx > 0 then
            w.facing[id].dir = 1
        elseif targetDx < 0 then
            w.facing[id].dir = -1
        end

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
        return w.position[a].y < w.position[b].y
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
            math.floor(pos.x - iw / 2 + 0.5) + ox, -- offset left by half width
            math.floor(pos.y - ih / 2 + 0.5),      -- offset up by half height
            0, dir, 1
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
