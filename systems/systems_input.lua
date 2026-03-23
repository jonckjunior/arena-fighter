local World        = require "world"
local C            = require "components"
local Utils        = require "utils"

---@class SystemsInput
local SystemsInput = {}

local function getPlayerGun(w, playerId)
    local guns = World.query(w, C.Name.equippedBy, C.Name.position, C.Name.animation)
    return Utils.find(guns, function(id)
        return w.equippedBy[id].ownerId == playerId
    end)
end

---Returns a raw input table for one player
---@param playerIndex integer
---@param w World
---@param mx number
---@param my number
---@param USE_NETWORK boolean
---@return table
function SystemsInput.gatherLocalInput(playerIndex, w, mx, my, USE_NETWORK)
    local inp
    if playerIndex == 1 or USE_NETWORK then
        inp = {
            up       = love.keyboard.isDown("w"),
            dn       = love.keyboard.isDown("s"),
            lt       = love.keyboard.isDown("a"),
            rt       = love.keyboard.isDown("d"),
            fire     = love.mouse.isDown(1),
            aimAngle = 0,
        }
    else
        inp = {
            up       = love.keyboard.isDown("u"),
            dn       = love.keyboard.isDown("j"),
            lt       = love.keyboard.isDown("h"),
            rt       = love.keyboard.isDown("k"),
            fire     = love.keyboard.isDown("space"),
            aimAngle = 0,
        }
    end

    local players = World.query(w, C.Name.playerIndex, C.Name.position, C.Name.input)
    local pid     = Utils.find(players, function(id)
        return w.playerIndex[id].index == playerIndex
    end)
    if not pid then return inp end

    local gunId = getPlayerGun(w, pid)
    if not gunId then return inp end

    local px, py = w.position[gunId].x, w.position[gunId].y
    local dx, dy = mx - px, my - py
    if dx * dx + dy * dy > 5 * 5 then
        inp.aimAngle = math.atan2(dy, dx)
    else
        inp.aimAngle = w.input[pid].aimAngle
    end
    return inp
end

---Copies frame inputs into each player's input component and prepends a
--- raw snapshot to their inputHistory ring buffer.
--- History index 1 is always the most recent frame.
---@param w World
---@param frameInputs table
function SystemsInput.applyInputs(w, frameInputs)
    for _, id in ipairs(World.query(w, C.Name.playerIndex)) do
        local pidx = w.playerIndex[id]
        local inp  = frameInputs[pidx.index]
        if not (inp and w.input[id]) then goto continue end

        -- Update live input state
        w.input[id].up       = inp.up
        w.input[id].dn       = inp.dn
        w.input[id].lt       = inp.lt
        w.input[id].rt       = inp.rt
        w.input[id].fire     = inp.fire
        w.input[id].aimAngle = inp.aimAngle

        -- Prepend snapshot to history, trim to historySize.
        -- Index 1 is always the most recent frame.
        local history        = w.input[id].inputHistory
        table.insert(history, 1, {
            up       = inp.up,
            dn       = inp.dn,
            lt       = inp.lt,
            rt       = inp.rt,
            fire     = inp.fire,
            aimAngle = inp.aimAngle,
        })
        if #history > w.input[id].historySize then
            table.remove(history)
        end

        ::continue::
    end
end

return SystemsInput
