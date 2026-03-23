---@class PLAYER_CONSTANTS
---@field JUMP_SPEED number
---@field MAX_FALL_SPEED number
---@field VARIABLE_JUMP_CUTOFF number
---@field HALF_GRAVITY_THRESHOLD number
---@field FAST_FALL_MULTIPLIER number
---@field COYOTE_TIME number
---@field JUMP_BUFFER_TIME number

local PLAYER_CONSTANTS = {
    JUMP_SPEED             = 160,  -- pixels/s upward impulse
    MAX_FALL_SPEED         = 300,  -- pixels/s terminal velocity (prevents tunnelling)
    VARIABLE_JUMP_CUTOFF   = 0.35, -- fraction of JUMP_SPEED kept on early key release
    HALF_GRAVITY_THRESHOLD = 28,   -- |dy| below this → half gravity (hang at apex)
    FAST_FALL_MULTIPLIER   = 1.3,  -- extra gravity factor when holding down mid-air
    COYOTE_TIME            = 0.3,  -- how much time after leaving the ground will the player still be treated as grounded to jump
    JUMP_BUFFER_TIME       = 0.1,  -- if the player presses jump, let's buffer it for 0.1s
    GRAVITY                = 460,  -- player's gravity
    HP                     = 100,  -- player's hp
    SPEED                  = 120,  -- player's speed
    GRAVITY_NEAR_PEAK      = 0.8,  -- player's gravity near the peak of their jump
    FALL_FASTER_FORCE      = 10,   -- when the player presses down while in the air, they fall faster by this force
}

return PLAYER_CONSTANTS
