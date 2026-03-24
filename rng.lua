---@class Rng
---@field state integer
local Rng = {}
Rng.__index = Rng

local MODULUS = 2147483647
local MULTIPLIER = 16807

---@param seed integer|nil
---@return Rng
function Rng.new(seed)
    local normalized = math.floor(tonumber(seed) or 1) % MODULUS
    if normalized <= 0 then
        normalized = 1
    end

    return setmetatable({ state = normalized }, Rng)
end

---@return integer
function Rng:getState()
    return self.state
end

---@param state integer
function Rng:setState(state)
    local normalized = math.floor(tonumber(state) or 1) % MODULUS
    if normalized <= 0 then
        normalized = 1
    end
    self.state = normalized
end

---@return number
function Rng:nextFloat()
    self.state = (self.state * MULTIPLIER) % MODULUS
    return self.state / MODULUS
end

---@param a integer|nil
---@param b integer|nil
---@return number|integer
function Rng:random(a, b)
    local value = self:nextFloat()
    if a == nil then
        return value
    end
    if b == nil then
        return math.floor(value * a) + 1
    end
    return math.floor(value * (b - a + 1)) + a
end

return Rng
