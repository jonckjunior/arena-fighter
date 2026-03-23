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

local PLAYER_CONSTANTS = {
    JUMP_SPEED             = 160,  -- pixels/s upward impulse
    MAX_FALL_SPEED         = 300,  -- pixels/s terminal velocity
    VARIABLE_JUMP_CUTOFF   = 0.35, -- fraction of JUMP_SPEED kept on early key release
    HALF_GRAVITY_THRESHOLD = 28,   -- |dy| below this → half gravity (hang at apex)
    FAST_FALL_MULTIPLIER   = 1.3,  -- extra gravity factor when holding down mid-air
    GRAVITY_NEAR_PEAK      = 1,    -- gravity scale near the apex
    GRAVITY                = 460,  -- player gravity
    HP                     = 100,
    SPEED                  = 120,

    -- Jump feel (frame-based, deterministic on fixed timestep)
    COYOTE_FRAMES          = 18, -- frames after leaving ground where jump is still allowed
    JUMP_BUFFER_FRAMES     = 6,  -- frames of input history to scan for a buffered jump
    JUMP_COOLDOWN_FRAMES   = 20, -- minimum frames between jumps (prevents double-firing)

    -- Input history ring buffer size. Must be >= JUMP_BUFFER_FRAMES.
    -- Larger values let other systems (e.g. wall jump) look further back.
    INPUT_HISTORY_FRAMES   = 30,
}

return PLAYER_CONSTANTS
