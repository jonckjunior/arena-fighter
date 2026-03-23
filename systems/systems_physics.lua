local World            = require "world"
local C                = require "components"
local FM               = require "fixedmath"
local PLAYER_CONSTANTS = require "player_constants"

---@class SystemsPhysics
local SystemsPhysics   = {}

-- ── Collision helper ──────────────────────────────────────────────────────────

-- circleHitsRect: returns true when a circle (center cx,cy radius r) overlaps
-- a rect (center rx,ry size rw×rh).
function SystemsPhysics.circleHitsRect(cx, cy, r, rx, ry, rw, rh)
    local nearX = math.max(rx - rw * 0.5, math.min(cx, rx + rw * 0.5))
    local nearY = math.max(ry - rh * 0.5, math.min(cy, ry + rh * 0.5))
    local dx    = cx - nearX
    local dy    = cy - nearY
    return dx * dx + dy * dy < r * r
end

-- ── Systems ───────────────────────────────────────────────────────────────────

---Saves the current position before they're modified
---@param w World
function SystemsPhysics.snapshotPositions(w)
    for _, id in pairs(w.position) do
        id.px = id.x
        id.py = id.y
    end
end

---Applies gravity to all entities with gravity + velocity components.
---@param w World
---@param dt number
function SystemsPhysics.applyGravity(w, dt)
    for _, id in ipairs(World.query(w, C.Name.gravity, C.Name.velocity)) do
        local isGrounded = w.grounded[id] and w.grounded[id].value
        if not isGrounded then
            local inp       = w.input[id]
            local nearApex  = math.abs(w.velocity[id].dy) < PLAYER_CONSTANTS.HALF_GRAVITY_THRESHOLD
            local gravScale = (inp and nearApex) and PLAYER_CONSTANTS.GRAVITY_NEAR_PEAK or 1.0

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
--- Must run AFTER playerMove so grounded.value is current.
---@param w World
---@param dt number
function SystemsPhysics.updateJumpTimers(w, dt)
    for _, id in ipairs(World.query(w, C.Name.jumpTimers, C.Name.input, C.Name.grounded)) do
        local inp        = w.input[id]
        local jmp        = w.jumpTimers[id]
        local isGrounded = w.grounded[id].value

        if isGrounded then
            jmp.coyoteTime = PLAYER_CONSTANTS.COYOTE_TIME
        else
            jmp.coyoteTime = math.max(jmp.coyoteTime - dt, 0)
        end

        if inp.up and not inp.prevUp and not isGrounded then
            jmp.jumpBuffer = PLAYER_CONSTANTS.JUMP_BUFFER_TIME
        else
            jmp.jumpBuffer = math.max(jmp.jumpBuffer - dt, 0)
        end
    end
end

---Handles horizontal movement and jumping for player-controlled entities.
---@param w World
---@param dt number
function SystemsPhysics.inputToVelocity(w, dt)
    local ids = World.query(w, C.Name.input, C.Name.speed, C.Name.velocity, C.Name.position, C.Name.jumpTimers)
    for _, id in ipairs(ids) do
        local inp         = w.input[id]
        local jmp         = w.jumpTimers[id]

        -- Horizontal
        local targetDx    = (inp.rt and 1 or 0) - (inp.lt and 1 or 0)
        w.velocity[id].dx = targetDx * w.speed[id].value

        -- Jump
        local isGrounded  = w.grounded[id] and w.grounded[id].value
        local hasCoyote   = jmp.coyoteTime > 0
        local wantsJump   = (inp.up and not inp.prevUp) or (jmp.jumpBuffer > 0)
        if wantsJump and (isGrounded or hasCoyote) then
            w.velocity[id].dy = -PLAYER_CONSTANTS.JUMP_SPEED
            jmp.jumpBuffer    = 0
            jmp.coyoteTime    = 0
        end

        -- Variable jump height: release early → cut upward speed
        if not inp.up and w.velocity[id].dy < 0 then
            local cutoff = -PLAYER_CONSTANTS.JUMP_SPEED * PLAYER_CONSTANTS.VARIABLE_JUMP_CUTOFF
            if w.velocity[id].dy < cutoff then
                w.velocity[id].dy = cutoff
            end
        end

        -- Facing direction
        w.facing[id].dir = FM.cos(inp.aimAngle) >= 0 and 1 or -1

        -- Animation
        if w.animation[id] then
            w.animation[id].isPlaying = (targetDx ~= 0) and (w.grounded[id] and w.grounded[id].value)
        end
    end
end

---Moves player-controlled entities using axis-separated AABB sweeps.
--- Pass 1: move X, resolve horizontal contacts → sets wallDir.
--- Pass 2: move Y, resolve vertical contacts   → sets grounded.
--- Ground probe: catches the standing-still case (vel.dy=0, no Y movement).
---@param w World
---@param dt number
function SystemsPhysics.playerMove(w, dt)
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

        -- Pass 1: move X
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

        -- Pass 2: move Y
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

        -- Ground probe: catches standing still on a surface
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

---Applies velocity to position for entities without player input (bullets, etc.)
---@param w World
---@param dt number
function SystemsPhysics.applyVelocity(w, dt)
    for _, id in ipairs(World.query(w, C.Name.velocity, C.Name.position)) do
        if not w.input[id] then
            w.position[id].x = w.position[id].x + w.velocity[id].dx * dt
            w.position[id].y = w.position[id].y + w.velocity[id].dy * dt
        end
    end
end

return SystemsPhysics
