local Utils = {}

--- Returns the first element in a list satisfying predicate, or nil.
---@generic T
---@param list T[]
---@param predicate fun(item: T): boolean
---@return T|nil
function Utils.find(list, predicate)
    for _, item in ipairs(list) do
        if predicate(item) then return item end
    end
end

---Returns the number rounded to the closes integer
---@param num number
---@return integer
function Utils.round(num)
    return math.floor(num + 0.5)
end

return Utils
