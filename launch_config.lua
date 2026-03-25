local LaunchConfig = {}

local DEFAULT_RELAY_HOST = "localhost"
local DEFAULT_RELAY_PORT = 22122
local DEFAULT_INPUT_DELAY = 6

-- Launch usage:
--   love .                                  -> local play
--   love . --network                        -> network play on localhost:22122
--   love . --network --host HOST --port P --input-delay N
-- Environment fallbacks:
--   ARENA_USE_NETWORK, ARENA_RELAY_HOST, ARENA_RELAY_PORT, ARENA_INPUT_DELAY

local function getLaunchArgs()
    local values = {}
    if type(arg) ~= "table" then
        return values
    end

    for _, value in ipairs(arg) do
        if type(value) == "string" then
            values[#values + 1] = value
        end
    end

    return values
end

local function parseBooleanEnv(name)
    local value = os.getenv(name)
    if value == nil then
        return nil
    end

    value = string.lower(value)
    if value == "1" or value == "true" or value == "yes" or value == "on" then
        return true
    end
    if value == "0" or value == "false" or value == "no" or value == "off" then
        return false
    end

    error(string.format("Invalid boolean value for %s: %s", name, value))
end

local function parseIntegerValue(rawValue, label)
    local value = tonumber(rawValue)
    if not value or value % 1 ~= 0 then
        error(string.format("Invalid %s: %s", label, tostring(rawValue)))
    end
    return value
end

local function parseIntegerEnv(name, defaultValue, label)
    local value = os.getenv(name)
    if value == nil or value == "" then
        return defaultValue
    end
    return parseIntegerValue(value, label)
end

local function readFlagValue(args, index, flagName)
    local value = args[index + 1]
    if value == nil or string.sub(value, 1, 2) == "--" then
        error(string.format("Missing value for %s", flagName))
    end
    return value
end

function LaunchConfig.buildGameConfig()
    local config = {
        useNetwork = parseBooleanEnv("ARENA_USE_NETWORK") or false,
        relayHost = os.getenv("ARENA_RELAY_HOST") or DEFAULT_RELAY_HOST,
        relayPort = parseIntegerEnv("ARENA_RELAY_PORT", DEFAULT_RELAY_PORT, "relay port"),
        inputDelay = parseIntegerEnv("ARENA_INPUT_DELAY", DEFAULT_INPUT_DELAY, "input delay"),
    }

    local args = getLaunchArgs()
    local i = 1
    while i <= #args do
        local value = args[i]
        if value == "--network" then
            config.useNetwork = true
        elseif value == "--host" then
            config.relayHost = readFlagValue(args, i, value)
            i = i + 1
        elseif value == "--port" then
            config.relayPort = parseIntegerValue(readFlagValue(args, i, value), "relay port")
            i = i + 1
        elseif value == "--input-delay" then
            config.inputDelay = parseIntegerValue(readFlagValue(args, i, value), "input delay")
            i = i + 1
        end
        i = i + 1
    end

    return config
end

return LaunchConfig
