local World            = require "world"
local C                = require "components"
local FM               = require "fixedmath"
local PLAYER_CONSTANTS = require "player_constants"

---@class SystemsPhysics
local SystemsPhysics   = {}

-- ── Input history query ───────────────────────────────────────────────────────

--- Returns true if `up` was pressed in any of the last `frames` history entries.
---@param inp table  the entity's input component
---@param frames integer
---@return boolean
local function jumpBuffered(inp, frames)
    local limit = math.min(frames, #inp.inputHistory)
    for i = 1, limit do
        if inp.inputHistory[i].up then return true end
    end
    return false
end

-- ── Systems ───────────────────────────────────────────────────────────────────

---Saves positions before physics modifies them (used for interpolated rendering).
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

---Sets horizontal velocity from directional input.
--- Producer: input.lt / input.rt
--- Consumer: velocity.dx
---@param w World
function SystemsPhysics.applyHorizontalMovement(w)
    for _, id in ipairs(World.query(w, C.Name.input, C.Name.speed, C.Name.velocity)) do
        local inp         = w.input[id]
        local targetDx    = (inp.rt and 1 or 0) - (inp.lt and 1 or 0)
        w.velocity[id].dx = targetDx * w.speed[id].value
    end
end

---Checks jump eligibility and fires an upward velocity impulse.
--- Producer: inputHistory, grounded.framesSinceGrounded, grounded.framesSinceJump
--- Consumer: velocity.dy
---@param w World
function SystemsPhysics.applyJump(w)
    local ids = World.query(w, C.Name.input, C.Name.velocity, C.Name.grounded)
    for _, id in ipairs(ids) do
        local inp         = w.input[id]
        local grnd        = w.grounded[id]
        local hasCoyote   = grnd.framesSinceGrounded <= PLAYER_CONSTANTS.COYOTE_FRAMES
        local offCooldown = grnd.framesSinceJump >= PLAYER_CONSTANTS.JUMP_COOLDOWN_FRAMES
        local wantsJump   = jumpBuffered(inp, PLAYER_CONSTANTS.JUMP_BUFFER_FRAMES)

        if wantsJump and hasCoyote and offCooldown then
            w.velocity[id].dy    = -PLAYER_CONSTANTS.JUMP_SPEED
            grnd.framesSinceJump = 0
        end
    end
end

---Fires a wall jump when the player is airborne, near a wall, pressing into it, and presses jump.
--- Uses the same jump buffer and cooldown as the ground jump.
--- wallDir / lastWallDir: -1 = wall on left (player presses lt), 1 = wall on right (player presses rt).
--- Producer: inputHistory, grounded.framesSinceWall, grounded.lastWallDir, grounded.framesSinceJump
--- Consumer: velocity.dx, velocity.dy
---@param w World
function SystemsPhysics.applyWallJump(w)
    for _, id in ipairs(World.query(w, C.Name.input, C.Name.velocity, C.Name.grounded)) do
        local inp  = w.input[id]
        local grnd = w.grounded[id]

        -- Must be airborne — ground jump handles the grounded case.
        if grnd.value then goto continue end

        local hasWallCoyote    = grnd.framesSinceWall <= PLAYER_CONSTANTS.WALL_COYOTE_FRAMES
        local offCooldown      = grnd.framesSinceJump >= PLAYER_CONSTANTS.JUMP_COOLDOWN_FRAMES
        local wantsJump        = jumpBuffered(inp, PLAYER_CONSTANTS.JUMP_BUFFER_FRAMES)

        -- Player must be pressing into the remembered wall side.
        local pressingIntoWall = (grnd.lastWallDir == -1 and inp.lt)
            or (grnd.lastWallDir == 1 and inp.rt)

        if wantsJump and hasWallCoyote and offCooldown and pressingIntoWall then
            -- Vertical impulse identical to a normal jump.
            w.velocity[id].dy = -PLAYER_CONSTANTS.JUMP_SPEED
            -- Small horizontal push away from the wall, overriding applyHorizontalMovement.
            w.velocity[id].dx = -grnd.lastWallDir * PLAYER_CONSTANTS.WALL_JUMP_HORIZONTAL_SPEED
            grnd.framesSinceJump = 0
        end

        ::continue::
    end
end

---Cuts upward velocity short when the jump key is released early.
--- Producer: input.up
--- Consumer: velocity.dy (clamps upward component)
---@param w World
function SystemsPhysics.applyVariableJumpCutoff(w)
    for _, id in ipairs(World.query(w, C.Name.input, C.Name.velocity)) do
        local inp = w.input[id]
        if not inp.up and w.velocity[id].dy < 0 then
            local cutoff = -PLAYER_CONSTANTS.JUMP_SPEED * PLAYER_CONSTANTS.VARIABLE_JUMP_CUTOFF
            if w.velocity[id].dy < cutoff then
                w.velocity[id].dy = cutoff
            end
        end
    end
end

---Increments framesSinceGrounded each airborne frame; resets it on landing.
--- Increments framesSinceWall each frame not in wall contact; resets and snapshots lastWallDir on contact.
--- Also increments framesSinceJump unconditionally every frame.
--- Must run AFTER playerMove so grounded.value and wallDir reflect the current frame.
---@param w World
function SystemsPhysics.updateGroundedTimer(w)
    for _, id in ipairs(World.query(w, C.Name.grounded)) do
        local grnd = w.grounded[id]

        if grnd.value then
            grnd.framesSinceGrounded = 0
        else
            grnd.framesSinceGrounded = grnd.framesSinceGrounded + 1
        end

        if grnd.wallDir ~= 0 then
            grnd.framesSinceWall = 0
            grnd.lastWallDir     = grnd.wallDir
        else
            grnd.framesSinceWall = grnd.framesSinceWall + 1
        end

        grnd.framesSinceJump = grnd.framesSinceJump + 1
    end
end

---Moves player-controlled entities using axis-separated AABB sweeps.
--- Pass 1: move X, resolve horizontal contacts → sets wallDir.
--- Pass 2: move Y, resolve vertical contacts   → sets grounded.value.
--- Ground probe: catches the standing-still case (vel.dy=0).
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
            local sc     = w.collider[sid]
            local sx, sy = w.position[sid].x, w.position[sid].y
            local ox     = (halfAW + sc.w * 0.5) - math.abs(pos.x - sx)
            local oy     = (halfAH + sc.h * 0.5) - math.abs(pos.y - sy)
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
            local sc     = w.collider[sid]
            local sx, sy = w.position[sid].x, w.position[sid].y
            local ox     = (halfAW + sc.w * 0.5) - math.abs(pos.x - sx)
            local oy     = (halfAH + sc.h * 0.5) - math.abs(pos.y - sy)
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
                local sc     = w.collider[sid]
                local sx, sy = w.position[sid].x, w.position[sid].y
                local ox     = (halfAW + sc.w * 0.5) - math.abs(pos.x - sx)
                local oy     = (halfAH + sc.h * 0.5) - math.abs(probeY - sy)
                if ox > 0 and oy > 0 and probeY < sy then
                    w.grounded[id].value = true
                    break
                end
            end
        end
    end
end

---Applies velocity to position for non-player entities (bullets, etc.)
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
