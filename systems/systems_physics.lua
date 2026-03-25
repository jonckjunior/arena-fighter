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
    local foundFalse = false
    for i = limit, 1, -1 do
        if inp.inputHistory[i].up == false then foundFalse = true end
        if inp.inputHistory[i].up and foundFalse then return true end
    end
    return false
end

-- ── Systems ───────────────────────────────────────────────────────────────────

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

---Lerps horizontal velocity toward the input-driven target speed.
--- On the ground the gap closes quickly (snappy); in the air it closes slowly,
--- which lets wall-jump (and any other) horizontal impulses bleed off naturally
--- without a separate lock timer.
--- Producer: input.lt / input.rt, grounded.value
--- Consumer: velocity.dx
---@param w World
function SystemsPhysics.applyHorizontalMovement(w)
    for _, id in ipairs(World.query(w, C.Name.input, C.Name.speed, C.Name.velocity, C.Name.grounded)) do
        local inp    = w.input[id]
        local target = ((inp.rt and 1 or 0) - (inp.lt and 1 or 0)) * w.speed[id].value
        local rate   = w.grounded[id].value and PLAYER_CONSTANTS.GROUND_LERP_RATE or PLAYER_CONSTANTS.AIR_LERP_RATE
        local vel    = w.velocity[id]
        vel.dx       = vel.dx + (target - vel.dx) * rate
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

--- Calculates AABB overlap between a mover and a solid.
--- @param w World
--- @param moverCol table The collider component of the moving entity.
--- @param checkX number The hypothetical X position to check.
--- @param checkY number The hypothetical Y position to check.
--- @param sid number The entity ID of the solid.
--- @return number ox, number oy (The overlap amounts on each axis)
--- @return number sx, number sy (The RAW position of the solid entity, without offsets)
--- @return table solidCol (The collider component of the solid)
local function getOverlap(w, moverCol, checkX, checkY, sid)
    local sc           = w.collider[sid]
    local sp           = w.position[sid]

    -- We use offsets here to find the actual distance between collision centers
    local moverCenterX = checkX + moverCol.ox
    local moverCenterY = checkY + moverCol.oy
    local solidCenterX = sp.x + sc.ox
    local solidCenterY = sp.y + sc.oy

    local ox           = (moverCol.w * 0.5 + sc.w * 0.5) - math.abs(moverCenterX - solidCenterX)
    local oy           = (moverCol.h * 0.5 + sc.h * 0.5) - math.abs(moverCenterY - solidCenterY)

    -- NOTE: Returns raw sp.x/sp.y so call sites can handle their own offset logic for signs
    return ox, oy, sp.x, sp.y, sc
end

function SystemsPhysics.playerMove(w, dt)
    local solids = World.query(w, C.Name.solid, C.Name.position, C.Name.collider)
    local movers = World.query(w, C.Name.input, C.Name.velocity, C.Name.position,
        C.Name.collider, C.Name.grounded)

    -- Separation of Duty: Reset transient states
    for _, id in ipairs(movers) do
        local g = w.grounded[id]
        g.value = false
        g.wallDir = 0
    end

    for _, id in ipairs(movers) do
        local vel, pos, col = w.velocity[id], w.position[id], w.collider[id]
        local grounded = w.grounded[id]

        -- Pass 1: Horizontal Movement
        pos.x = pos.x + vel.dx * dt
        for _, sid in ipairs(solids) do
            local ox, oy, sx = getOverlap(w, col, pos.x, pos.y, sid)
            if ox > 0 and oy > 0 then
                local nx = ((pos.x + col.ox) >= sx) and 1 or -1
                pos.x = pos.x + nx * ox
                if nx * vel.dx < 0 then vel.dx = 0 end
                grounded.wallDir = -nx
            end
        end

        -- Pass 2: Vertical Movement
        pos.y = pos.y + vel.dy * dt
        for _, sid in ipairs(solids) do
            local ox, oy, _, sy = getOverlap(w, col, pos.x, pos.y, sid)
            if ox > 0 and oy > 0 then
                local ny = ((pos.y + col.oy) >= sy) and 1 or -1
                pos.y = pos.y + ny * oy

                if ny < 0 then -- Hit top of a solid (floor)
                    grounded.value = true
                    if vel.dy > 0 then vel.dy = 0 end
                elseif ny > 0 then -- Hit bottom of a solid (ceiling)
                    if vel.dy < 0 then vel.dy = 0 end
                end
            end
        end

        -- Ground probe: Check 1 pixel below for standing-still state
        if not grounded.value then
            for _, sid in ipairs(solids) do
                local ox, oy, _, sy, sc = getOverlap(w, col, pos.x, pos.y + 1, sid)
                -- Ensure we are actually above the solid we're probing
                if ox > 0 and oy > 0 and (pos.y + col.oy + 1) < (sy + sc.oy) then
                    grounded.value = true
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
