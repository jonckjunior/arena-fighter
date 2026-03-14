-- Run as a standalone Love2D app: love relay/
-- Phase 2: assigns player indices, broadcasts input packets, displays a live log.

local enet      = require "enet"

local PORT      = 22122
local host      = enet.host_create("*:" .. PORT, 16)
local clients   = {} -- peer → playerIndex
local nextIndex = 1

local log       = {} -- newest entry at index 1
local LOG_MAX   = 20

local function addLog(msg)
    table.insert(log, 1, msg)
    if #log > LOG_MAX then log[#log] = nil end
end

print("Relay listening on port " .. PORT)

function love.update()
    if not host then return end

    local event = host:service(0)
    while event do
        if event.type == "connect" then
            clients[event.peer] = nextIndex
            addLog("P" .. nextIndex .. " connected")
            event.peer:send(string.char(0xFF, nextIndex))
            nextIndex = nextIndex + 1
        elseif event.type == "receive" then
            local from    = clients[event.peer] or "?"
            local buttons = string.byte(event.data, 2)
            addLog("P" .. from .. " -> " .. #event.data .. "b  buttons=" .. buttons)

            -- Broadcast to every client except the sender
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

function love.draw()
    love.graphics.print("Relay on port " .. PORT .. "   players: " .. (nextIndex - 1), 10, 10)
    for i, msg in ipairs(log) do
        love.graphics.print(msg, 10, 10 + i * 16)
    end
end
