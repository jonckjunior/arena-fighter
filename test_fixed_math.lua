-- Standalone test: no Love2D needed, run with: lua test_fixedmath.lua

local PI      = 3.141592653589793
local TWO_PI  = PI * 2
local HALF_PI = PI * 0.5
local STEPS   = 65536

local function _sincore(x)
    local x2 = x * x
    return x * (1 + x2 * (-1 / 6 + x2 * (1 / 120 + x2 * (-1 / 5040 + x2 / 362880))))
end

local function _coscore(x)
    local x2 = x * x
    return 1 + x2 * (-0.5 + x2 * (1 / 24 + x2 * (-1 / 720 + x2 / 40320)))
end

local function pure_sin(x)
    local sign = 1
    if x < 0 then
        x = -x; sign = -1
    end
    if x > HALF_PI then x = PI - x end
    return sign * _sincore(x)
end

local function pure_cos(x)
    if x < 0 then x = -x end
    if x <= HALF_PI then
        return _coscore(x)
    else
        return -_coscore(PI - x)
    end
end

local _sin, _cos = {}, {}
for i = 0, STEPS - 1 do
    local a = (i / STEPS) * TWO_PI - PI
    _sin[i] = pure_sin(a)
    _cos[i] = pure_cos(a)
end

local function angleToIndex(angle)
    return math.floor(((angle + PI) / TWO_PI) * STEPS + 0.5) % STEPS
end

local function fm_sin(a) return _sin[angleToIndex(a)] end
local function fm_cos(a) return _cos[angleToIndex(a)] end

-- ── Tests ─────────────────────────────────────────────────────────────────────

local named = {
    { "−π", -PI },
    { "−3π/4", -3 * PI / 4 },
    { "−π/2", -HALF_PI },
    { "−π/4", -PI / 4 },
    { "0", 0 },
    { "π/6", PI / 6 },
    { "π/4", PI / 4 },
    { "π/3", PI / 3 },
    { "π/2", HALF_PI },
    { "2π/3", 2 * PI / 3 },
    { "3π/4", 3 * PI / 4 },
    { "π", PI },
}

-- Angles that would actually appear in the game: evenly spaced around a circle,
-- as if a player aimed in 16 directions, packed and unpacked through lockstep.
local game_angles = {}
for k = 0, 15 do
    local raw        = -PI + k * (TWO_PI / 16)
    local idx        = math.floor(((raw + PI) / TWO_PI) * STEPS + 0.5) % STEPS
    local unpacked   = (idx / STEPS) * TWO_PI - PI -- simulates lockstep round-trip
    game_angles[k + 1] = { string.format("dir %2d", k), unpacked }
end

local function run(label, angles)
    print(string.format("\n── %s ──", label))
    print(string.format("%-12s  %10s  %10s  %12s  %12s", "angle", "fm_sin", "ref_sin", "sin_err", "cos_err"))
    print(string.rep("-", 62))

    local max_sin_err, max_cos_err = 0, 0
    for _, t in ipairs(angles) do
        local name, a = t[1], t[2]
        local fs, fc  = fm_sin(a), fm_cos(a)
        local rs, rc  = math.sin(a), math.cos(a)
        local se, ce  = math.abs(fs - rs), math.abs(fc - rc)
        max_sin_err   = math.max(max_sin_err, se)
        max_cos_err   = math.max(max_cos_err, ce)
        print(string.format("%-12s  %10.6f  %10.6f  %12.3e  %12.3e", name, fs, rs, se, ce))
    end
    print(string.format("%-12s  %10s  %10s  %12.3e  %12.3e", "MAX", "", "", max_sin_err, max_cos_err))
end

run("named angles", named)
run("game round-trip angles (lockstep pack→unpack)", game_angles)

-- ── Worst case sweep ──────────────────────────────────────────────────────────
print("\n── full sweep: worst case over all 65536 indices ──")
local wsin, wcos, wsin_i, wcos_i = 0, 0, 0, 0
for i = 0, STEPS - 1 do
    local a  = (i / STEPS) * TWO_PI - PI
    local se = math.abs(_sin[i] - math.sin(a))
    local ce = math.abs(_cos[i] - math.cos(a))
    if se > wsin then wsin, wsin_i = se, i end
    if ce > wcos then wcos, wcos_i = ce, i end
end
local function angle_of(i) return (i / STEPS) * TWO_PI - PI end
print(string.format("  worst sin err: %.4e  at index %d  (angle %.6f rad)", wsin, wsin_i, angle_of(wsin_i)))
print(string.format("  worst cos err: %.4e  at index %d  (angle %.6f rad)", wcos, wcos_i, angle_of(wcos_i)))
print(string.format("  pixel impact at bullet speed 600, over 120 frames: %.6f px", 600 * (1 / 60) * wsin * 120))
