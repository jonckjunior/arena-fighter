-- Run as a standalone Love2D app: love relay/
-- For now: accepts connections and assigns each client a player index.
-- No game logic, no input broadcasting yet.

local enet      = require "enet"

local PORT      = 22122
local host      = enet.host_create("*:" .. PORT, 16)
local clients   = {} -- peer → playerIndex
local nextIndex = 1

print("Relay listening on port " .. PORT)

function love.update()
    if not host then return end

    local event = host:service(0)
    while event do
        if event.type == "connect" then
            clients[event.peer] = nextIndex
            print("Player " .. nextIndex .. " connected: " .. tostring(event.peer))

            -- Tell the client which index they are.
            -- Packet: [0xFF][playerIndex] — both plain bytes
            event.peer:send(string.char(0xFF, nextIndex))

            nextIndex = nextIndex + 1
        elseif event.type == "disconnect" then
            local idx = clients[event.peer]
            print("Player " .. (idx or "?") .. " disconnected")
            clients[event.peer] = nil
        end

        event = host:service(0)
    end
end

function love.draw()
    love.graphics.print("Relay running on port " .. PORT, 10, 10)
    love.graphics.print("Players ever connected: " .. (nextIndex - 1), 10, 30)
end
