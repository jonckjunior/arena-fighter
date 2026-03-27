local World         = require "world"
local Spawners      = require "spawners"
local C             = require "components"
local FM            = require "fixedmath"

---@class SystemsCombat
local SystemsCombat = {}

-- ── Collision helper ──────────────────────────────────────────────────────────

-- Bullets are always circles; terrain and players are always rects.
local function circleHitsRect(bpos, bcol, rpos, rcol)
    local cx    = bpos.x + bcol.ox
    local cy    = bpos.y + bcol.oy
    local rx    = rpos.x + rcol.ox
    local ry    = rpos.y + rcol.oy
    local nearX = math.max(rx - rcol.w * 0.5, math.min(cx, rx + rcol.w * 0.5))
    local nearY = math.max(ry - rcol.h * 0.5, math.min(cy, ry + rcol.h * 0.5))
    local dx    = cx - nearX
    local dy    = cy - nearY
    return dx * dx + dy * dy < bcol.radius * bcol.radius
end

-- ── Systems ───────────────────────────────────────────────────────────────────

---Ticks down gun cooldowns each frame.
---@param w World
function SystemsCombat.gunCooldown(w)
    for _, id in ipairs(World.query(w, C.Name.gun)) do
        local gun = w.gun[id]
        if gun.cooldown > 0 then
            gun.cooldown = gun.cooldown - 1
        end
    end
end

---Keeps equipped guns positioned at the owner's muzzle offset.
---@param w World
function SystemsCombat.gunFollow(w)
    local guns = World.query(w, C.Name.equippedBy, C.Name.position)
    for _, gid in ipairs(guns) do
        local ownerId = w.equippedBy[gid].ownerId
        local pos     = w.position[ownerId]
        local inp     = w.input[ownerId]
        if not pos or not inp then goto continue end

        local angle       = inp.aimAngle
        local offset      = 4
        w.position[gid].x = pos.x + FM.cos(angle) * offset
        w.position[gid].y = pos.y + FM.sin(angle) * offset
        ::continue::
    end
end

---Spawns bullets when fire input is held and gun is off cooldown.
---@param w World
function SystemsCombat.firing(w)
    local guns = World.query(w, C.Name.gun, C.Name.equippedBy, C.Name.position)
    for _, gid in ipairs(guns) do
        local gun     = w.gun[gid]
        local eq      = w.equippedBy[gid]
        local gunPos  = w.position[gid]
        local ownerId = eq.ownerId
        local inp     = w.input[ownerId]
        if not inp then goto continue end

        if inp.fire and gun.cooldown == 0
            and not gun.isReloading
            and gun.currentAmmo > 0 then
            local angle         = inp.aimAngle
            local muzzleOffsetX = gun.muzzleOffsetX
            local muzzleOffsetY = gun.muzzleOffsetY
            local muzzleX       = gunPos.x + FM.cos(angle) * (muzzleOffsetX / 2)
            local muzzleY       = gunPos.y + FM.sin(angle) * (muzzleOffsetY / 2)

            for i = 1, gun.bulletCount do
                local spreadAngle = (w.rng:random() - 0.5) * 2 * gun.spread
                local a           = angle + spreadAngle
                Spawners.bullet(w, ownerId, muzzleX, muzzleY,
                    FM.cos(a) * gun.bulletSpeed,
                    FM.sin(a) * gun.bulletSpeed,
                    gun.damage)
            end
            gun.currentAmmo = gun.currentAmmo - gun.bulletCount -- ← new, deduct after firing
            gun.cooldown    = gun.maxCooldown
        end
        ::continue::
    end
end

---Destroys bullets that hit player-owned hp targets.
---@param w World
function SystemsCombat.bulletPlayerCollision(w)
    local players   = World.query(w, C.Name.hp, C.Name.position, C.Name.collider)
    local toDestroy = {}

    local bullets   = World.query(w, C.Name.bullet, C.Name.position, C.Name.collider)
    for _, bid in ipairs(bullets) do
        local bullet = w.bullet[bid]
        local bpos   = w.position[bid]
        local bcol   = w.collider[bid]
        local hits   = {}

        for _, pid in ipairs(players) do
            if pid == bullet.ownerId and bullet.selfDamageGraceFrames > 0 then goto continuePlayer end
            bullet.selfDamageGraceFrames = math.max(bullet.selfDamageGraceFrames - 1, 0)
            local ppos = w.position[pid]
            local pcol = w.collider[pid]
            if circleHitsRect(bpos, bcol, ppos, pcol) then
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

---Destroys bullets that hit solid terrain.
---@param w World
function SystemsCombat.bulletTerrainCollision(w)
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
        local bcol = w.collider[bid]
        for _, sid in ipairs(solids) do
            local spos = w.position[sid]
            local scol = w.collider[sid]
            if circleHitsRect(bpos, bcol, spos, scol) then
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

---Destroys entities whose hp has reached 0, along with their equipped guns.
---@param w World
function SystemsCombat.death(w)
    local toDestroy = {}
    for _, id in ipairs(World.query(w, C.Name.hp)) do
        if w.hp[id].current <= 0 then
            toDestroy[#toDestroy + 1] = id
        end
    end
    for _, id in ipairs(toDestroy) do
        for _, gid in ipairs(World.query(w, C.Name.equippedBy)) do
            if w.equippedBy[gid].ownerId == id then
                World.destroy(w, gid)
            end
        end
        World.destroy(w, id)
    end
end

---Destroys entities whose lifetime timer has expired.
---@param w World
---@param dt number
function SystemsCombat.lifetime(w, dt)
    local toDestroy = {}
    for _, id in ipairs(World.query(w, C.Name.lifetime)) do
        local lt = w.lifetime[id]
        lt.ttl = lt.ttl - dt
        if lt.ttl <= 0 then
            toDestroy[#toDestroy + 1] = id
        end
    end
    for _, id in ipairs(toDestroy) do
        World.destroy(w, id)
    end
end

---Returns true if one or zero players with hp remain.
---@param w World
---@return boolean
function SystemsCombat.isRoundOver(w)
    return #World.query(w, C.Name.playerIndex, C.Name.hp) <= 1
end

---Returns the index of the surviving player, or -1 for a draw.
---@param w World
---@return integer
function SystemsCombat.getRoundWinner(w)
    local alive = World.query(w, C.Name.playerIndex, C.Name.hp)
    if #alive == 1 then
        return w.playerIndex[alive[1]].index
    end
    return -1
end

---Handles manual reload (press key) and auto-reload on empty magazine.
---@param w World
---@param dt number
function SystemsCombat.reload(w, dt)
    local guns = World.query(w, C.Name.gun, C.Name.equippedBy)
    for _, gid in ipairs(guns) do
        local gun         = w.gun[gid]
        local ownerId     = w.equippedBy[gid].ownerId
        local inp         = w.input[ownerId]

        -- Trigger reload: manual key press OR mag is empty (and not already reloading)
        local wantsReload = inp and inp.reload
        local isEmpty     = gun.currentAmmo <= 0
        if not gun.isReloading and (wantsReload or isEmpty) and gun.currentAmmo < gun.maxAmmo then
            gun.isReloading = true
            gun.reloadTimer = gun.reloadTime
        end

        -- Tick the reload timer
        if gun.isReloading then
            gun.reloadTimer = gun.reloadTimer - dt
            if gun.reloadTimer <= 0 then
                gun.currentAmmo = gun.maxAmmo
                gun.isReloading = false
                gun.reloadTimer = 0
            end
        end
    end
end

return SystemsCombat
