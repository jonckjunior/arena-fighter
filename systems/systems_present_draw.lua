local World                  = require "world"
local C                      = require "components"
local Assets                 = require "assets"

---@class SystemsPresentDraw
local SystemsPresentDraw     = {}

---Draws all entities with position + animation, sorted by draw layer then y.
---@param w World
---@param alpha number
function SystemsPresentDraw.drawWorld(w, alpha)
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
        local img  = Assets.getImage(anim.frameIds[anim.current])
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
                love.graphics.circle("fill", pos.x + col.ox, pos.y + col.oy, col.radius)
            elseif col.shape == "rect" then
                love.graphics.rectangle("fill",
                    pos.x + col.ox - col.w * 0.5,
                    pos.y + col.oy - col.h * 0.5,
                    col.w, col.h)
            end
            love.graphics.setColor(1, 1, 1)
        end
    end
end

---Draws health bars above entities that have hp + position.
---@param w World
---@param alpha number
function SystemsPresentDraw.drawHpBars(w, alpha)
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

---@param w World
---@param alpha number
function SystemsPresentDraw.drawReloadBars(w, alpha)
    local BAR_W  = 24
    local BAR_H  = 2
    local OFFSET = -10

    local guns   = World.query(w, C.Name.gun, C.Name.equippedBy)
    for _, gid in ipairs(guns) do
        local gun     = w.gun[gid]
        local ownerId = w.equippedBy[gid].ownerId
        local pos     = w.position[ownerId]
        if not pos then goto continue end

        local rx   = pos.px + (pos.x - pos.px) * alpha
        local ry   = pos.py + (pos.y - pos.py) * alpha
        local left = rx - BAR_W / 2
        local top  = ry + OFFSET

        if gun.isReloading then
            local progress = 1 - (gun.reloadTimer / gun.reloadTime)
            love.graphics.setColor(0.2, 0.2, 0.2)
            love.graphics.rectangle("fill", left, top, BAR_W, BAR_H)
            love.graphics.setColor(1, 0.85, 0)
            love.graphics.rectangle("fill", left, top, BAR_W * progress, BAR_H)
        else
            local fill = gun.currentAmmo / gun.maxAmmo
            love.graphics.setColor(0.2, 0.2, 0.2)
            love.graphics.rectangle("fill", left, top, BAR_W, BAR_H)
            love.graphics.setColor(0.3, 0.6, 1)
            love.graphics.rectangle("fill", left, top, BAR_W * fill, BAR_H)
        end

        love.graphics.setColor(1, 1, 1)
        ::continue::
    end
end

return SystemsPresentDraw
