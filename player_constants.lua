---@class PLAYER_CONSTANTS
---@field JUMP_SPEED number
---@field MAX_FALL_SPEED number
---@field VARIABLE_JUMP_CUTOFF number
---@field HALF_GRAVITY_THRESHOLD number
---@field FAST_FALL_MULTIPLIER number
---@field GRAVITY_NEAR_PEAK number
---@field GRAVITY integer
---@field HP integer
---@field SPEED integer
---@field COYOTE_FRAMES integer
---@field JUMP_BUFFER_FRAMES integer
---@field INPUT_HISTORY_FRAMES integer
---@field JUMP_COOLDOWN_FRAMES integer
---@field WALL_COYOTE_FRAMES integer
---@field WALL_JUMP_HORIZONTAL_SPEED number
---@field GROUND_LERP_RATE number
---@field AIR_LERP_RATE number

local PLAYER_CONSTANTS = {
    JUMP_SPEED                 = 160,  -- pixels/s upward impulse
    MAX_FALL_SPEED             = 300,  -- pixels/s terminal velocity
    VARIABLE_JUMP_CUTOFF       = 0.35, -- fraction of JUMP_SPEED kept on early key release
    HALF_GRAVITY_THRESHOLD     = 28,   -- |dy| below this → half gravity (hang at apex)
    FAST_FALL_MULTIPLIER       = 1.3,  -- extra gravity factor when holding down mid-air
    GRAVITY_NEAR_PEAK          = 1,    -- gravity scale near the apex
    GRAVITY                    = 460,  -- player gravity
    HP                         = 100,
    SPEED                      = 120,

    -- Jump feel (frame-based, deterministic on fixed timestep)
    COYOTE_FRAMES              = 18, -- frames after leaving ground where jump is still allowed
    JUMP_BUFFER_FRAMES         = 12, -- frames of input history to scan for a buffered jump
    JUMP_COOLDOWN_FRAMES       = 20, -- minimum frames between jumps (prevents double-firing)

    -- Input history ring buffer size. Must be >= JUMP_BUFFER_FRAMES.
    -- Larger values let other systems (e.g. wall jump) look further back.
    INPUT_HISTORY_FRAMES       = 30,

    -- Wall jump
    WALL_COYOTE_FRAMES         = 6,   -- frames after leaving a wall where wall jump is still allowed
    WALL_JUMP_HORIZONTAL_SPEED = 120, -- pixels/s push away from the wall on wall jump

    -- Horizontal movement lerp (fraction of gap closed per frame, fixed-timestep deterministic)
    GROUND_LERP_RATE           = 0.35, -- snappy ground acceleration
    AIR_LERP_RATE              = 0.10, -- floaty air steering; lets wall jump impulse bleed off naturally
    ANIMATION_THRESHOLD_SPEED  = 5,
}

return PLAYER_CONSTANTS
