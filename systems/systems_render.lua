local World         = require "world"
local C             = require "components"
local FM            = require "fixedmath"

---@class SystemsRender
local SystemsRender = {}

---Writes facing direction from aim angle.
--- Producer: input.aimAngle
--- Consumer: facing.dir
---@param w World
function SystemsRender.updateFacing(w)
    for _, id in ipairs(World.query(w, C.Name.input, C.Name.facing)) do
        w.facing[id].dir = FM.cos(w.input[id].aimAngle) >= 0 and 1 or -1
    end
end

---Enables walk animation when moving horizontally on the ground.
--- Producer: velocity.dx, grounded.value
--- Consumer: animation.isPlaying
---@param w World
function SystemsRender.updateWalkAnimation(w)
    for _, id in ipairs(World.query(w, C.Name.input, C.Name.velocity, C.Name.animation, C.Name.grounded)) do
        local moving              = w.velocity[id].dx ~= 0
        local onFloor             = w.grounded[id].value
        w.animation[id].isPlaying = moving and onFloor
    end
end

---Advances sprite animation timers and cycles frames.
---@param w World
---@param dt number
function SystemsRender.animation(w, dt)
    for _, id in ipairs(World.query(w, C.Name.animation)) do
        local anim = w.animation[id]
        if anim.isPlaying then
            anim.timer = anim.timer + dt
            if anim.timer >= anim.duration then
                anim.timer   = anim.timer - anim.duration
                anim.current = (anim.current % #anim.frames) + 1
            end
        else
            anim.current = 1
            anim.timer   = 0
        end
    end
end

---Draws all entities with position + animation, sorted by draw layer then y.
---@param w World
---@param alpha number  interpolation factor for sub-frame rendering
function SystemsRender.draw(w, alpha)
    local drawables = World.query(w, C.Name.animation, C.Name.position)
    table.sort(drawables, function(a, b)
        local la = w.drawLayer[a] and w.drawLayer[a].layer or 0
        local lb = w.drawLayer[b] and w.drawLayer[b].layer or 0
        if la ~= lb then return la < lb end
        return w.position[a].y < w.position[b].y
    end)

    for _, id in ipairs(drawables) do
        local pos  = w.position[id]
        local anim = w.animation[id]
        local dir  = w.facing[id] and w.facing[id].dir or 1
        local img  = anim.frames[anim.current]
        local iw   = img:getWidth()
        local ih   = img:getHeight()
        local rx   = pos.px + (pos.x - pos.px) * alpha
        local ry   = pos.py + (pos.y - pos.py) * alpha
        love.graphics.draw(img, rx, ry, anim.angle or 0, dir, anim.flipY or 1, iw / 2, ih / 2)
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

---Draws health bars above entities that have hp + position.
---@param w World
---@param alpha number
function SystemsRender.drawHpBars(w, alpha)
    local BAR_W  = 24
    local BAR_H  = 3
    local OFFSET = -14

    for _, id in ipairs(World.query(w, C.Name.hp, C.Name.position)) do
        local hp   = w.hp[id]
        local pos  = w.position[id]
        local rx   = pos.px + (pos.x - pos.px) * alpha
        local ry   = pos.py + (pos.y - pos.py) * alpha
        local left = rx - BAR_W / 2
        local top  = ry + OFFSET
        local fill = math.max(0, hp.current / hp.max)

        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle("fill", left, top, BAR_W, BAR_H)

        love.graphics.setColor(1 - fill, fill, 0)
        love.graphics.rectangle("fill", left, top, BAR_W * fill, BAR_H)

        love.graphics.setColor(1, 1, 1)
    end
end

return SystemsRender
