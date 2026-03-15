-- Run as a standalone Love2D app: love relay/
-- Assigns player indices. Once all NUM_PLAYERS are connected, sends 0xFE "go"
-- to everyone simultaneously so all clients start from frame 0 at the same time.

local enet        = require "enet"

local PORT        = 22122
local NUM_PLAYERS = 2 -- must match the clients

local host        = enet.host_create("*:" .. PORT, 16)
local clients     = {}    -- peer → playerIndex
local nextIndex   = 1
local started     = false -- true after go signal is sent

local log         = {}
local LOG_MAX     = 20
local function addLog(msg)
    table.insert(log, 1, msg)
    if #log > LOG_MAX then log[#log] = nil end
end

print("Relay listening on port " .. PORT)

---@diagnostic disable-next-line: duplicate-set-field
function love.update()
    if not host then return end

    local event = host:service(0)
    while event do
        if event.type == "connect" then
            clients[event.peer] = nextIndex
            addLog("P" .. nextIndex .. " connected")
            event.peer:send(string.char(0xFF, nextIndex))
            nextIndex = nextIndex + 1

            -- Once all players are connected, send "go" to everyone.
            if nextIndex - 1 == NUM_PLAYERS and not started then
                started = true
                addLog("All players ready — sending go!")
                for peer in pairs(clients) do
                    peer:send(string.char(0xFE))
                end
            end
        elseif event.type == "receive" then
            local from    = clients[event.peer] or "?"
            local frameHi = string.byte(event.data, 2)
            local frameLo = string.byte(event.data, 3)
            local buttons = string.byte(event.data, 4)
            local frame   = frameHi * 256 + frameLo

            for peer in pairs(clients) do
                if peer ~= event.peer then
                    peer:send(event.data)
                end
            end
        elseif event.type == "disconnect" then
            local idx = clients[event.peer]
            addLog("P" .. (idx or "?") .. " disconnected")
            clients[event.peer] = nil
        end

        event = host:service(0)
    end
end

---@diagnostic disable-next-line: duplicate-set-field
function love.draw()
    local status = started and "RUNNING" or ("waiting " .. (nextIndex - 1) .. "/" .. NUM_PLAYERS)
    love.graphics.print("Relay  port=" .. PORT .. "  " .. status, 10, 10)
    for i, msg in ipairs(log) do
        love.graphics.print(msg, 10, 10 + i * 16)
    end
end
