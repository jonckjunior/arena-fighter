-- fixedmath.lua
-- Deterministic trig lookup table for cross-platform lockstep safety.
--
-- The table is built using pure_sin / pure_cos — polynomials that use only
-- +, -, * which IEEE 754 requires to be correctly-rounded (bitwise identical)
-- on all conforming hardware. This avoids the platform-dependent math.sin/cos
-- which are NOT required to be bit-identical across CPU architectures.
--
-- The 65536-step index space exactly mirrors the lockstep angle pack/unpack
-- so a round-tripped aimAngle always maps to the same table slot on both clients.

---@class FixedMath
local FM      = {}

local STEPS   = 65536             -- must match lockstep's 16-bit angle range
local PI      = 3.141592653589793 -- IEEE 754 double, same on all platforms
local TWO_PI  = PI * 2            -- IEEE 754 multiply: bitwise identical everywhere
local HALF_PI = PI * 0.5

-- ── Pure polynomial core (input must be in [0, pi/2]) ────────────────────────
-- 9th-degree Taylor series. Uses only * and +, so IEEE 754 guarantees
-- bitwise-identical results on x86 and Apple Silicon.
-- Max error at x = pi/2 is ~3.5e-6, giving < 0.005px drift over a bullet lifetime.

local function _sincore(x)
    local x2 = x * x
    return x * (1 + x2 * (-1 / 6 + x2 * (1 / 120 + x2 * (-1 / 5040 + x2 / 362880))))
end

local function _coscore(x)
    local x2 = x * x
    return 1 + x2 * (-0.5 + x2 * (1 / 24 + x2 * (-1 / 720 + x2 / 40320)))
end

-- ── Range reduction ───────────────────────────────────────────────────────────
-- Folds any angle into [0, pi/2] using sin/cos symmetry, applies the core,
-- then restores the correct sign. Only comparisons and negation — no trig.
--
-- sin(-x) = -sin(x)            → handle sign, work with x >= 0
-- sin(pi - x) = sin(x)         → fold [pi/2, pi] back to [0, pi/2]

local function pure_sin(x)
    local sign = 1
    if x < 0 then
        x = -x; sign = -1
    end                                -- reflect: x now in [0, pi]
    if x > HALF_PI then x = PI - x end -- fold:    x now in [0, pi/2]
    return sign * _sincore(x)
end

-- cos(-x) = cos(x)             → take abs, work with x in [0, pi]
-- cos(pi - x) = -cos(x)        → fold [pi/2, pi], flip sign

local function pure_cos(x)
    if x < 0 then x = -x end -- reflect: x now in [0, pi]
    if x <= HALF_PI then
        return _coscore(x)
    else
        return -_coscore(PI - x) -- fold and flip sign
    end
end

-- ── Lookup table ──────────────────────────────────────────────────────────────
-- Built at startup using pure_sin/pure_cos. Index range: 0 .. STEPS-1.
-- Angle formula mirrors lockstep unpackInput: a = (i / 65536) * 2pi - pi

local _sin = {}
local _cos = {}
for i = 0, STEPS - 1 do
    local a = (i / STEPS) * TWO_PI - PI
    _sin[i] = pure_sin(a)
    _cos[i] = pure_cos(a)
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Convert a float angle to a table index 0..STEPS-1.
--- Mirrors lockstep packInput so a round-tripped aimAngle maps to the same slot.
---@param angle number  radians, any range
---@return integer      0..65535
function FM.angleToIndex(angle)
    return math.floor(((angle + PI) / TWO_PI) * STEPS + 0.5) % STEPS
end

--- Deterministic cosine.
---@param angle number
---@return number
function FM.cos(angle)
    return _cos[FM.angleToIndex(angle)]
end

--- Deterministic sine.
---@param angle number
---@return number
function FM.sin(angle)
    return _sin[FM.angleToIndex(angle)]
end

--- Look up cos and sin together by a pre-computed index.
--- Use this when you need both values to avoid computing the index twice.
---@param i integer  0..65535
---@return number cos, number sin
function FM.cosSinByIndex(i)
    return _cos[i], _sin[i]
end

return FM
