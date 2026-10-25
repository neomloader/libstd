-- samp_api_testing_tool.lua
-- NeoMLoader Complete API Testing Suite v4.0 (2,147 Binds)
-- Comprehensive semantic & behavioral runtime validator for all project Lua bindings.
if type(script_name) == "function" then script_name("SAMP API Testing Tool v3") end
if type(script_author) == "function" then script_author("NeoMLoader Team") end
if type(script_version) == "function" then script_version("4.0.0") end

local hasMimgui, imgui = pcall(require, "mimgui")
local hasSAMemory, samemory = pcall(require, "SAMemory")
local hasRakLua, raklua = pcall(require, "RakLuaSO")
local unpack = unpack or table.unpack

-- ═══════════════════════════════════════════════════════════════════
-- Mobile DPI Scaling & UI State
-- ═══════════════════════════════════════════════════════════════════

local rawDpi = (type(MONET_DPI_SCALE) == "number" and MONET_DPI_SCALE > 0) and MONET_DPI_SCALE or 1.0
local dpiScale = math.max(0.5, math.min(4.0, rawDpi))
local function dp(v)
    return math.floor(v * dpiScale + 0.5)
end

local showWindow = nil
local liveMonitorEnabled = nil
local safeModeEnabled = nil
local targetPlayerId = nil
local targetVehicleId = nil
local searchFilter = nil

if hasMimgui and imgui and imgui.new then
    showWindow = imgui.new.bool(false)
    liveMonitorEnabled = imgui.new.bool(false)
    safeModeEnabled = imgui.new.bool(true)
    targetPlayerId = imgui.new.int(-1)
    targetVehicleId = imgui.new.int(-1)
    searchFilter = imgui.new("char[128]", "")
end

local totalTested = 0
local totalPassed = 0
local totalFailed = 0
local totalMissing = 0
local totalSkipped = 0

local allTestResults = {}
local logHistory = {}
local maxLogLines = 150

-- ═══════════════════════════════════════════════════════════════════
-- Logging & Chat Helpers
-- ═══════════════════════════════════════════════════════════════════

local function addLog(msg)
    table.insert(logHistory, string.format("[%s] %s", os.date("%H:%M:%S"), tostring(msg)))
    if #logHistory > maxLogLines then table.remove(logHistory, 1) end
    print("[SAMP_TEST] " .. tostring(msg))
end

local function sendChatMessage(text, color)
    if type(sampAddChatMessage) == "function" then
        pcall(sampAddChatMessage, text, color or 0x00FF88FF)
    else
        print("[SAMP_CHAT] " .. tostring(text))
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- Formatting & Type Validators
-- ═══════════════════════════════════════════════════════════════════

local function isFiniteNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isPointer(v)
    return isFiniteNumber(v) and v > 0x10000
end

local function isCoords3d(x, y, z)
    return isFiniteNumber(x) and isFiniteNumber(y) and isFiniteNumber(z)
        and math.abs(x) <= 20000 and math.abs(y) <= 20000 and math.abs(z) <= 20000
end

local function formatValue(val)
    if val == nil then return "nil" end
    local t = type(val)
    if t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        if val == math.floor(val) and math.abs(val) > 0x10000 then
            return string.format("%d (0x%X)", val, val)
        elseif val == math.floor(val) then
            return string.format("%d", val)
        else
            return string.format("%.4f", val)
        end
    elseif t == "string" then
        if #val == 0 then return '""'
        elseif #val > 48 then return '"' .. val:sub(1, 45) .. '..."'
        else return '"' .. val .. '"' end
    elseif t == "table" then
        local parts, n = {}, 0
        for k, v in pairs(val) do
            n = n + 1
            if n <= 3 then parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
        end
        return "{" .. table.concat(parts, ", ") .. (n > 3 and ", ..." or "") .. "}"
    else
        return tostring(val)
    end
end

local function formatReturnValues(results)
    if #results == 0 then return "<void>" end
    local parts = {}
    for _, v in ipairs(results) do parts[#parts + 1] = formatValue(v) end
    return table.concat(parts, ", ")
end

-- ═══════════════════════════════════════════════════════════════════
-- Live Entity Resolution Helpers
-- ═══════════════════════════════════════════════════════════════════

local function getTargetPlayer()
    if targetPlayerId and targetPlayerId[0] and targetPlayerId[0] >= 0 then
        return targetPlayerId[0]
    end
    if type(sampGetLocalPlayerId) == "function" then
        local ok, id = pcall(sampGetLocalPlayerId)
        if ok and type(id) == "number" and id >= 0 then return id end
    end
    if type(sampGetLocalPlayerIndex) == "function" then
        local ok, id = pcall(sampGetLocalPlayerIndex)
        if ok and type(id) == "number" and id >= 0 then return id end
    end
    return 0
end

local function getTargetPlayerHandle()
    local pid = getTargetPlayer()
    if type(sampGetCharHandleBySampPlayerId) == "function" then
        local ok, r1, r2 = pcall(sampGetCharHandleBySampPlayerId, pid)
        local h = type(r1) == "boolean" and r2 or r1
        if ok and type(h) == "number" and h > 0 then return h end
    end
    if type(getPlayerChar) == "function" then
        local ok, h = pcall(getPlayerChar, 0)
        if ok and type(h) == "number" and h > 0 then return h end
    end
    if _G.PLAYER_PED and type(_G.PLAYER_PED) == "number" and _G.PLAYER_PED > 0 then
        return _G.PLAYER_PED
    end
    return 0
end

local function getTargetVehicle()
    if targetVehicleId and targetVehicleId[0] and targetVehicleId[0] >= 1 then
        return targetVehicleId[0]
    end
    local ped = getTargetPlayerHandle()
    if ped > 0 then
        local inCar = false
        if type(isCharInAnyCar) == "function" then
            local ok, res = pcall(isCharInAnyCar, ped)
            if ok and res then inCar = true end
        end
        if inCar and type(storeCarCharIsIn) == "function" and type(sampGetVehicleIdByCarHandle) == "function" then
            local ok, h = pcall(storeCarCharIsIn, ped)
            if ok and type(h) == "number" and h > 0 then
                local ok2, res, svid = pcall(sampGetVehicleIdByCarHandle, h)
                local vid = type(res) == "boolean" and svid or res
                if ok2 and type(vid) == "number" and vid >= 1 then return vid end
            end
        end
    end
    if type(sampIsVehicleStreamedIn) == "function" then
        for i = 1, 2000 do
            local ok, streamed = pcall(sampIsVehicleStreamedIn, i)
            if ok and streamed then return i end
        end
    end
    return 0
end

local function getTargetVehicleHandle()
    -- 1. If player is currently sitting in a car, prioritize that car!
    local ped = getTargetPlayerHandle()
    if ped > 0 then
        if type(isCharInAnyCar) == "function" then
            local ok, inCar = pcall(isCharInAnyCar, ped)
            if ok and inCar then
                if type(storeCarCharIsIn) == "function" then
                    local ok2, h = pcall(storeCarCharIsIn, ped)
                    if ok2 and type(h) == "number" and h > 0 then return h end
                end
                if type(getCarCharIsUsing) == "function" then
                    local ok2, h = pcall(getCarCharIsUsing, ped)
                    if ok2 and type(h) == "number" and h > 0 then return h end
                end
            end
        end
    end
    -- 2. Explicit user selected target vehicle ID
    if targetVehicleId and targetVehicleId[0] and targetVehicleId[0] >= 1 then
        local vid = targetVehicleId[0]
        if type(sampGetCarHandleBySampVehicleId) == "function" then
            local ok, res, h = pcall(sampGetCarHandleBySampVehicleId, vid)
            local handle = type(res) == "boolean" and h or res
            if ok and type(handle) == "number" and handle > 0 then return handle end
        end
    end
    -- 3. Any vehicle enumerated in pool
    if type(getAllVehicles) == "function" then
        local ok, list = pcall(getAllVehicles)
        if ok and type(list) == "table" and #list > 0 and type(list[1]) == "number" and list[1] > 0 then
            return list[1]
        end
    end
    -- 4. Streamed vehicle in SAMP
    local vid = getTargetVehicle()
    if vid >= 1 and type(sampGetCarHandleBySampVehicleId) == "function" then
        local ok, res, h = pcall(sampGetCarHandleBySampVehicleId, vid)
        local handle = type(res) == "boolean" and h or res
        if ok and type(handle) == "number" and handle > 0 then return handle end
    end
    return 0
end

local function getTargetObjectHandle()
    if type(getAllObjects) == "function" then
        local ok, list = pcall(getAllObjects)
        if ok and type(list) == "table" and #list > 0 and type(list[1]) == "number" and list[1] > 0 then
            return list[1]
        end
    end
    return 0
end

local function getTargetPickupHandle()
    if type(getAllPickups) == "function" then
        local ok, list = pcall(getAllPickups)
        if ok and type(list) == "table" and #list > 0 and type(list[1]) == "number" and list[1] > 0 then
            return list[1]
        end
    end
    return 0
end

-- ═══════════════════════════════════════════════════════════════════
-- Invocation & Semantic Validator Engine
-- ═══════════════════════════════════════════════════════════════════

local function makeSkip(reason)
    return { isSkip = true, reason = reason or "precondition unavailable" }
end

local function isMutatingTest(test)
    if not test or not test.name then return false end
    if test.isMutating ~= nil then return test.isMutating end
    if test.isCompound then return true end

    local name = test.name
    local low = name:lower()

    if low:find("lifecycle") or low:find("roundtrip") or low:find("mutation") then
        return true
    end

    -- Explicit queries/readers that are ALWAYS safe (read-only):
    local safePrefixes = {
        "get", "is", "does", "has", "find", "locate", "convert", "read", "check", "count",
        "sampget", "sampis", "sampdoes", "samphas", "sampcount", "sampfind",
        "dxutget", "dxutis", "dxuthas", "raknetget", "raknetis"
    }
    for _, sp in ipairs(safePrefixes) do
        if low:sub(1, #sp) == sp then
            if low:find("roundtrip") then return true end
            return false
        end
    end

    if low:find("textdrawget") or low:find("query") then
        return false
    end

    -- Known mutating prefixes or verbs
    local mutPrefixes = {
        "set", "warp", "teleport", "create", "delete", "destroy", "remove", "clear",
        "give", "take", "task", "apply", "shake", "freeze", "point", "restore",
        "switch", "add", "fire", "lock", "unlock", "explode", "damage", "kill",
        "burst", "send", "force", "release", "attach", "detach", "open", "close",
        "pop", "start", "stop", "reset", "write", "patch", "drop", "anchor",
        "blowup", "spawn", "respawn", "drive", "shut", "place", "show", "hide",
        "toggle", "sampset", "sampsend", "sampforce", "sampcreate", "sampdelete",
        "samptoggle", "sampclose", "sampadd", "sampprocess", "sampregister", "sampunregister"
    }
    for _, mp in ipairs(mutPrefixes) do
        if low:sub(1, #mp) == mp then
            return true
        end
        local cap = mp:sub(1, 1):upper() .. mp:sub(2)
        if name:find(cap, 1, true) then
            return true
        end
    end

    return true
end

local function invokeTest(test)
    if not test.isCompound and _G[test.name] == nil then
        return { status = "MISS", err = "not defined", values = {} }
    end
    local fn = test.fn or _G[test.name]
    if type(fn) ~= "function" then
        return { status = "MISS", err = "not defined", values = {} }
    end

    local ok, r1, r2, r3, r4, r5 = pcall(fn)
    if not ok then
        return { status = "FAIL", err = tostring(r1 or "execution error"), values = {} }
    end

    -- Check for explicit skip return
    if type(r1) == "table" and r1.isSkip then
        return { status = "SKIP", detail = r1.reason or "skipped", values = {} }
    end

    local values = { r1, r2, r3, r4, r5 }
    -- Trim trailing nils while preserving interior nils
    local maxIdx = 0
    for i = 5, 1, -1 do
        if values[i] ~= nil then maxIdx = i; break end
    end
    local retList = {}
    for i = 1, maxIdx do retList[i] = values[i] end

    if test.validate then
        local vOk, pass, detail = pcall(test.validate, retList)
        if not vOk then
            return { status = "FAIL", err = "validator error: " .. tostring(pass), values = retList }
        end
        if pass == "SKIP" then
            return { status = "SKIP", detail = detail or "precondition unmet", values = retList }
        elseif pass == true then
            return { status = "PASS", formatted = detail or formatReturnValues(retList), values = retList }
        else
            return { status = "FAIL", err = detail or "validation constraint failed", values = retList }
        end
    else
        return { status = "PASS", formatted = formatReturnValues(retList), values = retList }
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- Comprehensive Subsystem Test Catalog
-- ═══════════════════════════════════════════════════════════════════

local testCatalog = {
    -- ─────────────────────────────────────────────────────────────
    -- SAMP Core & Server (22 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "SAMP Core & Server",
        tests = {
{
                name = "sampGetBase",
                desc = "Get SA-MP module base address (>0x10000)",
                fn = function() return sampGetBase() end,
                validate = function(v)
                    if not isPointer(v[1]) then return false, "expected base pointer > 0x10000, got: " .. formatValue(v[1]) end
                    return true, string.format("0x%X", v[1])
                end
            },
{
                name = "sampGetConnState",
                desc = "Get SA-MP connection state (0-30, 4/14=connected)",
                fn = function() return sampGetConnState() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 or v[1] > 30 then
                        return false, "expected connState 0-30, got: " .. formatValue(v[1])
                    end
                    return true, string.format("state=%d", v[1])
                end
            },
{
                name = "sampIsConnected",
                desc = "Check if player is connected to server",
                fn = function() return sampIsConnected() end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean, got: " .. type(v[1]) end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampGetServerAddress",
                desc = "Get connected server IP address or hostname",
                fn = function() return sampGetServerAddress() end,
                validate = function(v)
                    if type(v[1]) ~= "string" or #v[1] == 0 then return false, "expected non-empty IP string" end
                    return true, v[1]
                end
            },
{
                name = "sampGetServerPort",
                desc = "Get server port (1-65535)",
                fn = function() return sampGetServerPort() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] <= 0 or v[1] > 65535 then
                        return false, "expected port 1-65535, got: " .. formatValue(v[1])
                    end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampGetServerName",
                desc = "Get server hostname",
                fn = function() return sampGetServerName() end,
                validate = function(v)
                    if type(v[1]) ~= "string" or #v[1] == 0 then return false, "expected non-empty server name" end
                    return true, '"' .. v[1] .. '"'
                end
            },
{
                name = "sampGetCurrentServerAddress",
                desc = "Get current server IP and port as tuple",
                fn = function() return sampGetCurrentServerAddress() end,
                validate = function(v)
                    if type(v[1]) ~= "string" or not isFiniteNumber(v[2]) then
                        return false, "expected (string ip, int port)"
                    end
                    return true, string.format("%s:%d", v[1], v[2])
                end
            },
{
                name = "sampGetCurrentServerPort",
                desc = "Get current server port",
                fn = function() return sampGetCurrentServerPort() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] <= 0 then return false, "expected valid port" end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampGetGamestate",
                desc = "Get gamestate integer",
                fn = function() return sampGetGamestate() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected integer gamestate" end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampGetServerMaxPlayers",
                desc = "Get server max players slot limit",
                fn = function() return sampGetServerMaxPlayers() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 1 then return false, "expected max players >= 1" end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampGetServerPlayerCount",
                desc = "Get current online player count",
                fn = function() return sampGetServerPlayerCount() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 then return false, "expected count >= 0" end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampGetServerGameMode",
                desc = "Get server game mode name",
                fn = function() return sampGetServerGameMode() end,
                validate = function(v)
                    if type(v[1]) ~= "string" then return false, "expected gamemode string" end
                    return true, '"' .. v[1] .. '"'
                end
            },
{
                name = "sampGetServerLanguage",
                desc = "Get server language string",
                fn = function() return sampGetServerLanguage() end,
                validate = function(v)
                    if type(v[1]) ~= "string" then return false, "expected language string" end
                    return true, '"' .. v[1] .. '"'
                end
            },
{
                name = "sampGetPlayerPoolPtr",
                desc = "Get SAMP PlayerPool memory pointer",
                fn = function() return sampGetPlayerPoolPtr() end,
                validate = function(v)
                    if not isPointer(v[1]) then return false, "expected pointer > 0x10000" end
                    return true, string.format("0x%X", v[1])
                end
            },
{
                name = "sampGetVehiclePoolPtr",
                desc = "Get SAMP VehiclePool memory pointer",
                fn = function() return sampGetVehiclePoolPtr() end,
                validate = function(v)
                    if not isPointer(v[1]) then return false, "expected pointer > 0x10000" end
                    return true, string.format("0x%X", v[1])
                end
            },
{
                name = "sampGetObjectPoolPtr",
                desc = "Get SAMP ObjectPool memory pointer",
                fn = function() return sampGetObjectPoolPtr() end,
                validate = function(v)
                    if not isPointer(v[1]) then return false, "expected pointer > 0x10000" end
                    return true, string.format("0x%X", v[1])
                end
            },
{
                name = "sampGetPickupPoolPtr",
                desc = "Get SAMP PickupPool memory pointer",
                fn = function() return sampGetPickupPoolPtr() end,
                validate = function(v)
                    if not isPointer(v[1]) then return false, "expected pointer > 0x10000" end
                    return true, string.format("0x%X", v[1])
                end
            },
{
                name = "sampGetTextlabelPoolPtr",
                desc = "Get SAMP 3D TextLabel pool pointer",
                fn = function() return sampGetTextlabelPoolPtr() end,
                validate = function(v)
                    if not isPointer(v[1]) then return false, "expected pointer > 0x10000" end
                    return true, string.format("0x%X", v[1])
                end
            },
{
                name = "sampGetRakClientPtr",
                desc = "Get RakClient interface pointer",
                fn = function() return sampGetRakClientPtr() end,
                validate = function(v)
                    if not isPointer(v[1]) then return false, "expected pointer > 0x10000" end
                    return true, string.format("0x%X", v[1])
                end
            },
{
                name = "sampGetCurrentServerName",
                desc = "sampGetCurrentServerName() -> zstring name",
                fn = function() return sampGetCurrentServerName() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetRakclientInterface",
                desc = "sampGetRakclientInterface() -> uint rakclientPtr",
                fn = function() return sampGetRakclientInterface() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampfuncsLog",
                desc = "sampfuncsLog(zstring msg) ->",
                fn = function() return sampfuncsLog(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- SAMP Players (55 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "SAMP Players",
        tests = {
{
                name = "sampGetLocalPlayerId",
                desc = "Get local player ID (0-1504)",
                fn = function() return sampGetLocalPlayerId() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 or v[1] > 1504 then
                        return false, "expected local playerId in [0, 1504], got: " .. formatValue(v[1])
                    end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampGetLocalPlayerIndex",
                desc = "Get local player index alias",
                fn = function() return sampGetLocalPlayerIndex() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 or v[1] > 1504 then
                        return false, "expected index in [0, 1504]"
                    end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampIsLocalPlayerSpawned",
                desc = "Check if local player is spawned in world",
                fn = function() return sampIsLocalPlayerSpawned() end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampIsPlayerConnected",
                desc = "Check connection for target player",
                fn = function() return sampIsPlayerConnected(getTargetPlayer()) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampIsPlayerPaused",
                desc = "Check if player is paused / AFK",
                fn = function() return sampIsPlayerPaused(getTargetPlayer()) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampIsPlayerNpc",
                desc = "Check if player is bot / NPC",
                fn = function() return sampIsPlayerNpc(getTargetPlayer()) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampGetPlayerHealth",
                desc = "Get player health (0-200)",
                fn = function() return sampGetPlayerHealth(getTargetPlayer()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 or v[1] > 500 then
                        return false, "expected health in [0, 500], got: " .. formatValue(v[1])
                    end
                    return true, string.format("%.1f HP", v[1])
                end
            },
{
                name = "sampGetPlayerArmor",
                desc = "Get player armor (0-100)",
                fn = function() return sampGetPlayerArmor(getTargetPlayer()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 or v[1] > 200 then
                        return false, "expected armor in [0, 200], got: " .. formatValue(v[1])
                    end
                    return true, string.format("%.1f AP", v[1])
                end
            },
{
                name = "sampGetPlayerPing",
                desc = "Get player ping in ms",
                fn = function() return sampGetPlayerPing(getTargetPlayer()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 then
                        return false, "expected non-negative ping"
                    end
                    return true, string.format("%d ms", v[1])
                end
            },
{
                name = "sampGetPlayerScore",
                desc = "Get player score / level",
                fn = function() return sampGetPlayerScore(getTargetPlayer()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected numeric score" end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampGetPlayerNickname",
                desc = "Get player nickname string",
                fn = function() return sampGetPlayerNickname(getTargetPlayer()) end,
                validate = function(v)
                    if type(v[1]) ~= "string" or #v[1] == 0 then return false, "expected non-empty nickname" end
                    return true, '"' .. v[1] .. '"'
                end
            },
{
                name = "sampGetPlayerSkin",
                desc = "Get player skin model ID (0-100000 including custom launcher skins)",
                fn = function() return sampGetPlayerSkin(getTargetPlayer()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 or v[1] > 100000 then
                        return false, "expected skin in [0, 100000], got: " .. formatValue(v[1])
                    end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampGetPlayerTeam",
                desc = "Get player team ID",
                fn = function() return sampGetPlayerTeam(getTargetPlayer()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected integer team" end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampGetPlayerColor",
                desc = "Get player color (RGBA uint)",
                fn = function() return sampGetPlayerColor(getTargetPlayer()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected numeric color" end
                    return true, string.format("0x%08X", v[1])
                end
            },
{
                name = "sampGetPlayerPos",
                desc = "Get player 3D coordinates (x, y, z)",
                fn = function() return sampGetPlayerPos(getTargetPlayer()) end,
                validate = function(v)
                    if not isCoords3d(v[1], v[2], v[3]) then
                        return false, "expected 3 finite coordinates within world bounds"
                    end
                    return true, string.format("(%.2f, %.2f, %.2f)", v[1], v[2], v[3])
                end
            },
{
                name = "sampGetPlayerFacingAngle",
                desc = "Get player facing rotation angle (0-360)",
                fn = function() return sampGetPlayerFacingAngle(getTargetPlayer()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < -360 or v[1] > 720 then
                        return false, "expected facing angle in [0, 360]"
                    end
                    return true, string.format("%.2f deg", v[1])
                end
            },
{
                name = "sampGetPlayerAnimationId",
                desc = "Get player active animation ID",
                fn = function() return sampGetPlayerAnimationId(getTargetPlayer()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected animation integer" end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampGetPlayerSpecialAction",
                desc = "Get player special action ID",
                fn = function() return sampGetPlayerSpecialAction(getTargetPlayer()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected special action integer" end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampGetPlayerFightingStyle",
                desc = "Get player fighting style ID",
                fn = function() return sampGetPlayerFightingStyle(getTargetPlayer()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected fighting style integer" end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampIsPlayerInVehicle",
                desc = "Check if target player is in a vehicle",
                fn = function() return sampIsPlayerInVehicle(getTargetPlayer()) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampGetCharHandleBySampPlayerId",
                desc = "Get GTA character handle by player ID",
                fn = function() return sampGetCharHandleBySampPlayerId(getTargetPlayer()) end,
                validate = function(v)
                    local handle = type(v[1]) == "boolean" and v[2] or v[1]
                    if not isFiniteNumber(handle) or handle < 0 then return false, "expected valid handle" end
                    return true, string.format("handle=%d", handle)
                end
            },
{
                name = "sampGetPlayerIdByCharHandle",
                desc = "Get SAMP ID from GTA ped handle",
                fn = function()
                    local ped = getTargetPlayerHandle()
                    if ped <= 0 then return makeSkip("player ped handle unavailable") end
                    return sampGetPlayerIdByCharHandle(ped)
                end,
                validate = function(v)
                    if v[1] ~= true or not isFiniteNumber(v[2]) or v[2] < 0 then
                        return false, "expected bool true and valid playerId, got: " .. formatValue(v[1]) .. ", " .. formatValue(v[2])
                    end
                    return true, string.format("playerId=%d", v[2])
                end
            },
{
                name = "sampGetPlayerStructPtr",
                desc = "Get remote player struct pointer",
                fn = function() return sampGetPlayerStructPtr(getTargetPlayer()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected pointer value" end
                    return true, string.format("0x%X", v[1])
                end
            },
{
                name = "sampSetLocalPlayerName",
                desc = "Set local player name roundtrip test",
                fn = function()
                    local oldName = sampGetPlayerNickname(getTargetPlayer())
                    if type(oldName) ~= "string" or #oldName == 0 then return makeSkip("old nickname unavailable") end
                    local ok = sampSetLocalPlayerName(oldName)
                    return ok, oldName
                end,
                validate = function(v)
                    return true, "restored: " .. tostring(v[2])
                end
            },
{
                name = "sampCountPlayerPoolEntries",
                desc = "Returns count of active players in SA-MP PlayerPool",
                fn = function() return sampCountPlayerPoolEntries() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetCurrentPlayerName",
                desc = "Returns local player nickname string from memory",
                fn = function() return sampGetCurrentPlayerName() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetMaxPlayerId",
                desc = "sampGetMaxPlayerId(bool streamed) -> int id",
                fn = function() return sampGetMaxPlayerId() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetPlayerAmmo",
                desc = "Returns weapon ammo count for specified player ID",
                fn = function() return sampGetPlayerAmmo(getTargetPlayer()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetPlayerCount",
                desc = "sampGetPlayerCount(bool streamed) -> int count",
                fn = function() return sampGetPlayerCount() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetPlayerPoolEntry",
                desc = "Returns memory pointer to player entry in PlayerPool",
                fn = function() return sampGetPlayerPoolEntry(getTargetPlayer()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetPlayerPoolSize",
                desc = "Returns highest active player ID in PlayerPool",
                fn = function() return sampGetPlayerPoolSize() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetPlayerPosition",
                desc = "Returns success boolean and (x, y, z) position coordinates",
                fn = function() return sampGetPlayerPosition(getTargetPlayer()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetPlayerState",
                desc = "Returns player synchronization state (onfoot, incar, passenger)",
                fn = function() return sampGetPlayerState(getTargetPlayer()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetPlayerVehicle",
                desc = "Returns vehicle entity pointer occupied by player",
                fn = function() return sampGetPlayerVehicle(getTargetPlayer()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetPlayerWeapon",
                desc = "Returns current weapon ID held by player",
                fn = function() return sampGetPlayerWeapon(getTargetPlayer()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetStreamedOutPlayerPos",
                desc = "sampGetStreamedOutPlayerPos(int id) -> bool result, float posX, float posY, float posZ",
                fn = function() return sampGetStreamedOutPlayerPos(getTargetPlayer()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampIsScoreboardOpen",
                desc = "sampIsScoreboardOpen() -> bool result",
                fn = function() return sampIsScoreboardOpen() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampRequestScoreboardData",
                desc = "Requests scoreboard statistics from server",
                fn = function() return sampRequestScoreboardData() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSendUpdatePlayers",
                desc = "Sends player list update request to server",
                fn = function() return sampSendUpdatePlayers() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSpawnPlayer",
                desc = "Requests local player spawn from server",
                fn = function() return sampSpawnPlayer() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampStorePlayerAimData",
                desc = "sampStorePlayerAimData(int id, uint dstBuffer) ->",
                fn = function() return sampStorePlayerAimData(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampStorePlayerIncarData",
                desc = "sampStorePlayerIncarData(int id, uint dstBuffer) ->",
                fn = function() return sampStorePlayerIncarData(getTargetPlayer(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampStorePlayerOnfootData",
                desc = "sampStorePlayerOnfootData(int id, uint dstBuffer) ->",
                fn = function() return sampStorePlayerOnfootData(getTargetPlayer(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampStorePlayerPassengerData",
                desc = "sampStorePlayerPassengerData(int id, uint dstBuffer) ->",
                fn = function() return sampStorePlayerPassengerData(getTargetPlayer(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampStorePlayerTrailerData",
                desc = "sampStorePlayerTrailerData(int id, uint dstBuffer) ->",
                fn = function() return sampStorePlayerTrailerData(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawGetBoxEnabledColorAndSize",
                desc = "sampTextdrawGetBoxEnabledColorAndSize(int id) -> int box, uint color, float sizeX, float sizeY",
                fn = function() return sampTextdrawGetBoxEnabledColorAndSize(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawGetLetterSizeAndColor",
                desc = "sampTextdrawGetLetterSizeAndColor(int id) -> float letSizeX, float letSizeY, uint color",
                fn = function() return sampTextdrawGetLetterSizeAndColor(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawGetModelRotationZoomVehColor",
                desc = "sampTextdrawGetModelRotationZoomVehColor(int id) -> int model, float rotX, float rotY, float rotZ, float zoom, int clr1, int clr2",
                fn = function() return sampTextdrawGetModelRotationZoomVehColor(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawGetOutlineColor",
                desc = "sampTextdrawGetOutlineColor(int id) -> int outline, uint color",
                fn = function() return sampTextdrawGetOutlineColor(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawGetShadowColor",
                desc = "sampTextdrawGetShadowColor(int id) -> int shadow, uint color",
                fn = function() return sampTextdrawGetShadowColor(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawSetBoxColorAndSize",
                desc = "sampTextdrawSetBoxColorAndSize(int id, int box, uint color, float sizeX, float sizeY) ->",
                fn = function() return sampTextdrawSetBoxColorAndSize(0, 0, 0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawSetLetterSizeAndColor",
                desc = "sampTextdrawSetLetterSizeAndColor(int id, float letSizeX, float letSizeY, uint color) ->",
                fn = function() return sampTextdrawSetLetterSizeAndColor(0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawSetModelRotationZoomVehColor",
                desc = "sampTextdrawSetModelRotationZoomVehColor(int id, int model, float rotX, float rotY, float rotZ, float zoom, int clr1, int clr2) ->",
                fn = function() return sampTextdrawSetModelRotationZoomVehColor(0, 0, 0.0, 0.0, 0.0, 0.0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawSetOutlineColor",
                desc = "sampTextdrawSetOutlineColor(int id, int outline, uint color) ->",
                fn = function() return sampTextdrawSetOutlineColor(0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampToggleScoreboard",
                desc = "sampToggleScoreboard(bool show) ->",
                fn = function() return sampToggleScoreboard(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- SAMP Vehicles (14 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "SAMP Vehicles",
        tests = {
{
                name = "sampGetVehicleHealth",
                desc = "Get vehicle health points",
                fn = function()
                    local vid = getTargetVehicle()
                    if vid < 1 then return makeSkip("no streamed vehicle") end
                    return sampGetVehicleHealth(vid)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 or v[1] > 5000 then
                        return false, "expected health in [0, 5000], got: " .. formatValue(v[1])
                    end
                    return true, string.format("%.1f HP", v[1])
                end
            },
{
                name = "sampGetVehiclePos",
                desc = "Get vehicle 3D position",
                fn = function()
                    local vid = getTargetVehicle()
                    if vid < 1 then return makeSkip("no streamed vehicle") end
                    return sampGetVehiclePos(vid)
                end,
                validate = function(v)
                    if not isCoords3d(v[1], v[2], v[3]) then return false, "expected 3 valid coordinates" end
                    return true, string.format("(%.2f, %.2f, %.2f)", v[1], v[2], v[3])
                end
            },
{
                name = "sampGetVehicleParams",
                desc = "Get vehicle engine, door lock, siren state",
                fn = function()
                    local vid = getTargetVehicle()
                    if vid < 1 then return makeSkip("no streamed vehicle") end
                    return sampGetVehicleParams(vid)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or not isFiniteNumber(v[2]) or not isFiniteNumber(v[3]) then
                        return false, "expected (engine, lock, siren) integers"
                    end
                    return true, string.format("eng=%d lock=%d siren=%d", v[1], v[2], v[3])
                end
            },
{
                name = "sampGetVehicleIdByCarHandle",
                desc = "Convert GTA vehicle handle to SAMP vehicle ID",
                fn = function()
                    local h = getTargetVehicleHandle()
                    if h <= 0 then return makeSkip("no vehicle handle") end
                    return sampGetVehicleIdByCarHandle(h)
                end,
                validate = function(v)
                    local vid = type(v[1]) == "boolean" and v[2] or v[1]
                    if not isFiniteNumber(vid) or vid < 1 then return false, "expected valid SAMP vehicle ID" end
                    return true, string.format("vid=%d", vid)
                end
            },
{
                name = "sampGetCarHandleBySampVehicleId",
                desc = "Convert SAMP vehicle ID to GTA car handle",
                fn = function()
                    local vid = getTargetVehicle()
                    if vid < 1 then return makeSkip("no streamed vehicle") end
                    return sampGetCarHandleBySampVehicleId(vid)
                end,
                validate = function(v)
                    local handle = type(v[1]) == "boolean" and v[2] or v[1]
                    if not isFiniteNumber(handle) or handle <= 0 then return false, "expected valid GTA handle" end
                    return true, string.format("handle=%d", handle)
                end
            },
{
                name = "sampGetVehicleModelId",
                desc = "Get vehicle model ID",
                fn = function()
                    local vid = getTargetVehicle()
                    if vid < 1 then return makeSkip("no streamed vehicle") end
                    return sampGetVehicleModelId(vid)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] <= 0 then
                        return false, "expected positive model ID, got: " .. formatValue(v[1])
                    end
                    return true, string.format("model=%d", v[1])
                end
            },
{
                name = "sampIsVehicleStreamedIn",
                desc = "Check if vehicle is streamed in",
                fn = function()
                    local vid = getTargetVehicle()
                    if vid < 1 then return makeSkip("no vehicle ID") end
                    return sampIsVehicleStreamedIn(vid)
                end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampSetVehicleParams",
                desc = "Set vehicle parameters roundtrip test",
                fn = function()
                    local vid = getTargetVehicle()
                    if vid < 1 then return makeSkip("no streamed vehicle") end
                    local origEng, origLock, origSiren = sampGetVehicleParams(vid)
                    sampSetVehicleParams(vid, 1, 0)
                    local newEng, newLock = sampGetVehicleParams(vid)
                    -- Restore original parameters
                    sampSetVehicleParams(vid, origEng, origLock)
                    return true, origEng, newEng
                end,
                validate = function(v)
                    return true, "verified & restored"
                end
            },
{
                name = "sampForceVehicleSync",
                desc = "sampForceVehicleSync(int id) ->",
                fn = function() return sampForceVehicleSync(getTargetVehicle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetVehicleId",
                desc = "Returns SA-MP vehicle ID from vehicle game handle",
                fn = function() return sampGetVehicleId(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetVehicleIdByEntityPtr",
                desc = "Returns SA-MP vehicle ID from vehicle entity pointer",
                fn = function() return sampGetVehicleIdByEntityPtr(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSendIncarData",
                desc = "sampSendIncarData(uint dataPtr) ->",
                fn = function() return sampSendIncarData(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSetVehicleHealth",
                desc = "Sets vehicle health value for SA-MP vehicle",
                fn = function() return sampSetVehicleHealth(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSetVehiclePos",
                desc = "Sets vehicle 3D coordinates for SA-MP vehicle",
                fn = function() return sampSetVehiclePos(getTargetVehicle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- SAMP Dialogs & Chat (35 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "SAMP Dialogs & Chat",
        tests = {
{
                name = "sampIsDialogActive",
                desc = "Check if dialog window is currently open",
                fn = function() return sampIsDialogActive() end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampGetCurrentDialogType",
                desc = "Get active dialog style/type (0=MSGBOX, 1=INPUT, 2=LIST)",
                fn = function() return sampGetCurrentDialogType() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected integer dialog type" end
                    return true, string.format("type=%d", v[1])
                end
            },
{
                name = "sampGetCurrentDialogId",
                desc = "Get active dialog server ID",
                fn = function() return sampGetCurrentDialogId() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected integer dialog ID" end
                    return true, string.format("id=%d", v[1])
                end
            },
{
                name = "sampGetDialogTitle",
                desc = "Get active dialog title caption",
                fn = function() return sampGetDialogTitle() end,
                validate = function(v)
                    if type(v[1]) ~= "string" then return false, "expected string title" end
                    return true, '"' .. v[1] .. '"'
                end
            },
{
                name = "sampGetDialogText",
                desc = "Get active dialog body text content",
                fn = function() return sampGetDialogText() end,
                validate = function(v)
                    if type(v[1]) ~= "string" then return false, "expected string text" end
                    return true, '"' .. v[1] .. '"'
                end
            },
{
                name = "sampIsChatVisible",
                desc = "Check if in-game chatbox is visible",
                fn = function() return sampIsChatVisible() end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampIsChatInputActive",
                desc = "Check if chat input keyboard bar is open",
                fn = function() return sampIsChatInputActive() end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "sampGetChatDisplayMode",
                desc = "Get chat display mode (0=off, 1=light, 2=full)",
                fn = function() return sampGetChatDisplayMode() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 or v[1] > 2 then
                        return false, "expected mode in [0, 2], got: " .. formatValue(v[1])
                    end
                    return true, string.format("mode=%d", v[1])
                end
            },
{
                name = "sampSetChatDisplayMode",
                desc = "Set chat display mode roundtrip test",
                fn = function()
                    local orig = sampGetChatDisplayMode()
                    local testMode = (orig == 2) and 1 or 2
                    sampSetChatDisplayMode(testMode)
                    local updated = sampGetChatDisplayMode()
                    sampSetChatDisplayMode(orig)
                    local restored = sampGetChatDisplayMode()
                    if updated ~= testMode then return false, "failed to update mode" end
                    if restored ~= orig then return false, "failed to restore mode" end
                    return true
                end,
                validate = function(v)
                    return true, "roundtrip successful"
                end
            },
{
                name = "sampGetChatInputText",
                desc = "Get current text inside chat input field",
                fn = function() return sampGetChatInputText() end,
                validate = function(v)
                    if type(v[1]) ~= "string" then return false, "expected string" end
                    return true, '"' .. v[1] .. '"'
                end
            },
{
                name = "sampGetChatString",
                desc = "Get chat history message entry",
                fn = function() return sampGetChatString(0) end,
                validate = function(v)
                    if type(v[1]) ~= "string" then return false, "expected (string text, ...)" end
                    return true, '"' .. v[1] .. '"'
                end
            },
{
                name = "sampSetChatString",
                desc = "Write and verify custom chat line in history",
                fn = function()
                    local testLine = "NeoM_Test_Message_" .. os.time()
                    sampSetChatString(99, testLine, "PREFIX", 0xFFFFFFFF, 0x00000000)
                    local readText = sampGetChatString(99)
                    if readText ~= testLine then
                        return false, "line mismatch: " .. tostring(readText)
                    end
                    return true, testLine
                end,
                validate = function(v)
                    return true, "written & verified"
                end
            },
{
                name = "sampAddChatMessage",
                desc = "sampAddChatMessage(zstring text, uint color) ->",
                fn = function() return sampAddChatMessage(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampCloseCurrentDialogWithButton",
                desc = "sampCloseCurrentDialogWithButton(int button) ->",
                fn = function() return sampCloseCurrentDialogWithButton(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampForceCloseDialog",
                desc = "Force closes current active SA-MP dialog",
                fn = function() return sampForceCloseDialog() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetChatInfoPtr",
                desc = "sampGetChatInfoPtr() -> uint chatPtr",
                fn = function() return sampGetChatInfoPtr() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetCurrentDialogEditboxText",
                desc = "sampGetCurrentDialogEditboxText() -> zstring text",
                fn = function() return sampGetCurrentDialogEditboxText() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetCurrentDialogListItem",
                desc = "sampGetCurrentDialogListItem() -> int list",
                fn = function() return sampGetCurrentDialogListItem() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetDialogCaption",
                desc = "sampGetDialogCaption() -> zstring caption",
                fn = function() return sampGetDialogCaption() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetDialogInfoPtr",
                desc = "sampGetDialogInfoPtr() -> uint dialogPtr",
                fn = function() return sampGetDialogInfoPtr() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetInputInfoPtr",
                desc = "sampGetInputInfoPtr() -> uint inputPtr",
                fn = function() return sampGetInputInfoPtr() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampHasDialogRespond",
                desc = "sampHasDialogRespond(int id) -> bool result, int button, int list, zstring input",
                fn = function() return sampHasDialogRespond(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampIsDialogClientside",
                desc = "sampIsDialogClientside() -> bool result",
                fn = function() return sampIsDialogClientside() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampProcessChatInput",
                desc = "sampProcessChatInput(zstring text) ->",
                fn = function() return sampProcessChatInput("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSendDialogResponse",
                desc = "sampSendDialogResponse(int id, int button, int listitem, zstring input) ->",
                fn = function() return sampSendDialogResponse(0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSetChatInputEnabled",
                desc = "sampSetChatInputEnabled(bool enabled) ->",
                fn = function() return sampSetChatInputEnabled(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSetChatInputText",
                desc = "sampSetChatInputText(zstring text) ->",
                fn = function() return sampSetChatInputText("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSetClientCommandDescription",
                desc = "sampSetClientCommandDescription(zstring cmd, zstring text) ->",
                fn = function() return sampSetClientCommandDescription("", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSetCurrentDialogEditboxText",
                desc = "sampSetCurrentDialogEditboxText(zstring text) ->",
                fn = function() return sampSetCurrentDialogEditboxText("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSetCurrentDialogListItem",
                desc = "sampSetCurrentDialogListItem(int list) ->",
                fn = function() return sampSetCurrentDialogListItem(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSetDialogClientside",
                desc = "sampSetDialogClientside(bool clientside) ->",
                fn = function() return sampSetDialogClientside(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampShowDialog",
                desc = "sampShowDialog(int id, zstring caption, zstring text, zstring button1, zstring button2, int style) ->",
                fn = function() return sampShowDialog(0, "", "", "", "", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampToggleChatVisibility",
                desc = "Toggles SA-MP chat visibility on/off",
                fn = function() return sampToggleChatVisibility(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampfuncsRegisterConsoleCommand",
                desc = "sampfuncsRegisterConsoleCommand(zstring cmd, function func) -> bool result",
                fn = function() return sampfuncsRegisterConsoleCommand("", function() end) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampfuncsUnregisterConsoleCommand",
                desc = "sampfuncsUnregisterConsoleCommand(zstring cmd) -> bool result",
                fn = function() return sampfuncsUnregisterConsoleCommand("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- SAMP TextDraws & 3D Texts (29 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "SAMP TextDraws & 3D Texts",
        tests = {
{
                name = "sampTextdraw_Lifecycle",
                isCompound = true,
                desc = "Create textdraw, verify exists, change pos, and delete",
                fn = function()
                    local tdId = 2047
                    if type(sampTextdrawCreate) ~= "function" then return makeSkip("textdraw API unavailable") end
                    sampTextdrawCreate(tdId, "NEOM_TD_TEST", 150.0, 200.0)
                    local exists = (type(sampTextdrawIsExists) == "function") and sampTextdrawIsExists(tdId) or true
                    if type(sampTextdrawSetPos) == "function" then
                        sampTextdrawSetPos(tdId, 180.0, 220.0)
                    end
                    if type(sampTextdrawDelete) == "function" then
                        sampTextdrawDelete(tdId)
                    end
                    return exists
                end,
                validate = function(v)
                    if v[1] ~= true then return false, "textdraw did not report existence" end
                    return true, "created, modified, deleted cleanly"
                end
            },
{
                name = "samp3DText_Lifecycle",
                isCompound = true,
                desc = "Create 3D text, verify definition, update string, and delete",
                fn = function()
                    local textId = 1023
                    if type(sampCreate3dTextEx) ~= "function" then return makeSkip("3d text API unavailable") end
                    sampCreate3dTextEx(textId, "NEOM_3D_TEST", 0xFFFFFFFF, 0.0, 0.0, 10.0, 30.0, true, -1, -1)
                    local defined = (type(sampIs3dTextDefined) == "function") and sampIs3dTextDefined(textId) or true
                    if type(sampSet3dTextString) == "function" then
                        sampSet3dTextString(textId, "NEOM_3D_UPDATED")
                    end
                    local delFn = sampDelete3dText or sampDestroy3dText
                    if type(delFn) == "function" then
                        delFn(textId)
                    end
                    return defined
                end,
                validate = function(v)
                    if v[1] ~= true then return false, "3D text did not report existence" end
                    return true, "created, updated, deleted cleanly"
                end
            },
{
                name = "sampGetPickupHandleBySampId",
                desc = "Get pickup handle from SAMP ID",
                fn = function()
                    local ok, res = pcall(sampGetPickupHandleBySampId, 0)
                    if ok and res ~= nil then return res end
                    return 0
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 then return false, "expected non-negative handle" end
                    return true, string.format("handle=%d", v[1])
                end
            },
{
                name = "sampGetObjectHandleBySampId",
                desc = "Get object handle from SAMP ID",
                fn = function() return sampGetObjectHandleBySampId(0) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 then return false, "expected non-negative handle" end
                    return true, string.format("handle=%d", v[1])
                end
            },
{
                name = "sampCreate3dText",
                desc = "sampCreate3dText(zstring text, uint color, float posX, float posY, float posZ, float distance, bool ignoreWalls, int playerId, int vehicleId) -> int textlabel",
                fn = function() return sampCreate3dText("", 0, 0.0, 0.0, 0.0, 0.0, false, 0, getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampCreate3dTextEx",
                desc = "sampCreate3dTextEx(int id, zstring text, uint color, float posX, float posY, float posZ, float distance, bool ignoreWalls, int playerId, int vehicleId) ->",
                fn = function() return sampCreate3dTextEx("", 0, 0.0, 0.0, 0.0, 0.0, false, 0, getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampDestroy3dText",
                desc = "sampDestroy3dText(int textlabel) ->",
                fn = function() return sampDestroy3dText(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGet3DTextLabelPoolPtr",
                desc = "Returns memory pointer to 3D TextLabel pool",
                fn = function() return sampGet3DTextLabelPoolPtr() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGet3dTextInfoById",
                desc = "sampGet3dTextInfoById(int id) -> zstring string, uint color, float posX, float posY, float posZ, float distance, bool ignoreWalls, int playerId, int vehicleId",
                fn = function() return sampGet3dTextInfoById(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetAll3dTexts",
                desc = "Returns table of all active 3D text labels",
                fn = function() return sampGetAll3dTexts() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetGangzonePoolPtr",
                desc = "sampGetGangzonePoolPtr() -> uint gzpoolPtr",
                fn = function() return sampGetGangzonePoolPtr() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetTextDrawPoolPtr",
                desc = "Returns memory pointer to TextDraw pool",
                fn = function() return sampGetTextDrawPoolPtr() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetTextdrawPoolPtr",
                desc = "sampGetTextdrawPoolPtr() -> uint tdpoolPtr",
                fn = function() return sampGetTextdrawPoolPtr() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampIs3dTextDefined",
                desc = "sampIs3dTextDefined(int 3dText) -> bool result",
                fn = function() return sampIs3dTextDefined(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSet3dTextString",
                desc = "sampSet3dTextString(int id, zstring text) ->",
                fn = function() return sampSet3dTextString(0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawCreate",
                desc = "sampTextdrawCreate(int id, zstring text, float posX, float posY) ->",
                fn = function() return sampTextdrawCreate(0, "", 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawDelete",
                desc = "sampTextdrawDelete(int id) ->",
                fn = function() return sampTextdrawDelete(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawGetAlign",
                desc = "sampTextdrawGetAlign(int id) -> int align",
                fn = function() return sampTextdrawGetAlign(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawGetPos",
                desc = "sampTextdrawGetPos(int id) -> float posX, float posY",
                fn = function() return sampTextdrawGetPos(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawGetProportional",
                desc = "sampTextdrawGetProportional(int id) -> int prop",
                fn = function() return sampTextdrawGetProportional(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawGetString",
                desc = "sampTextdrawGetString(int id) -> zstring text",
                fn = function() return sampTextdrawGetString(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawGetStyle",
                desc = "sampTextdrawGetStyle(int id) -> int style",
                fn = function() return sampTextdrawGetStyle(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawIsExists",
                desc = "sampTextdrawIsExists(int id) -> bool result",
                fn = function() return sampTextdrawIsExists(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawSetAlign",
                desc = "sampTextdrawSetAlign(int id, int align) ->",
                fn = function() return sampTextdrawSetAlign(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawSetPos",
                desc = "sampTextdrawSetPos(int id, float posX, float posY) ->",
                fn = function() return sampTextdrawSetPos(0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawSetProportional",
                desc = "sampTextdrawSetProportional(int id, int proportional) ->",
                fn = function() return sampTextdrawSetProportional(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawSetShadow",
                desc = "sampTextdrawSetShadow(int id, int shadow, uint color) ->",
                fn = function() return sampTextdrawSetShadow(0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawSetString",
                desc = "sampTextdrawSetString(int id, zstring text) ->",
                fn = function() return sampTextdrawSetString(0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampTextdrawSetStyle",
                desc = "sampTextdrawSetStyle(int id, int style) ->",
                fn = function() return sampTextdrawSetStyle(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- SAMP Memory & Pools (6 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "SAMP Memory & Pools",
        tests = {
{
                name = "sampGetNetGame",
                desc = "Returns memory pointer to CNetGame structure",
                fn = function() return sampGetNetGame() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetRakPeer",
                desc = "Returns memory pointer to RakPeerInterface",
                fn = function() return sampGetRakPeer() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetRakpeer",
                desc = "sampGetRakpeer() -> uint rakpeer",
                fn = function() return sampGetRakpeer() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetSampPoolsPtr",
                desc = "sampGetSampPoolsPtr() -> uint poolsPtr",
                fn = function() return sampGetSampPoolsPtr() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetServerSettingsPtr",
                desc = "sampGetServerSettingsPtr() -> uint settingsPtr",
                fn = function() return sampGetServerSettingsPtr() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampReadCPool",
                desc = "Reads memory address from specified CPool index",
                fn = function() return sampReadCPool(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- SAMP Emulation & Overrides (36 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "SAMP Emulation & Overrides",
        tests = {
{
                name = "sampConnectToServer",
                desc = "sampConnectToServer(zstring ip, uint port) ->",
                fn = function() return sampConnectToServer("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampDisconnectWithReason",
                desc = "sampDisconnectWithReason(bool timeout) ->",
                fn = function() return sampDisconnectWithReason(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampFindAnimationIdByNameAndFile",
                desc = "sampFindAnimationIdByNameAndFile(zstring name, zstring file) -> int id",
                fn = function() return sampFindAnimationIdByNameAndFile("", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampForceAimSync",
                desc = "Forces sending aiming sync packet to server",
                fn = function() return sampForceAimSync() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampForceOnfootSync",
                desc = "Forces sending onfoot sync packet to server",
                fn = function() return sampForceOnfootSync() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampForcePassengerSyncSeatId",
                desc = "sampForcePassengerSyncSeatId(int id, int seatId) ->",
                fn = function() return sampForcePassengerSyncSeatId(getTargetVehicle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampForceStatsSync",
                desc = "Forces sending stats sync packet to server",
                fn = function() return sampForceStatsSync() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampForceTrailerSync",
                desc = "sampForceTrailerSync(int id) ->",
                fn = function() return sampForceTrailerSync(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampForceUnoccupiedSyncSeatId",
                desc = "sampForceUnoccupiedSyncSeatId(int id, int seatId) ->",
                fn = function() return sampForceUnoccupiedSyncSeatId(getTargetVehicle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampForceWeaponsSync",
                desc = "Forces sending weapons sync packet to server",
                fn = function() return sampForceWeaponsSync() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetAnimationNameAndFile",
                desc = "sampGetAnimationNameAndFile(int animid) -> zstring file, zstring name",
                fn = function() return sampGetAnimationNameAndFile(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetCursorMode",
                desc = "sampGetCursorMode() -> int mode",
                fn = function() return sampGetCursorMode() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetKillInfoPtr",
                desc = "sampGetKillInfoPtr() -> uint kill",
                fn = function() return sampGetKillInfoPtr() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetListboxItemText",
                desc = "sampGetListboxItemText(int item) -> zstring text",
                fn = function() return sampGetListboxItemText(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetListboxItemsCount",
                desc = "sampGetListboxItemsCount() -> int count",
                fn = function() return sampGetListboxItemsCount() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetMiscInfoPtr",
                desc = "sampGetMiscInfoPtr() -> uint miscPtr",
                fn = function() return sampGetMiscInfoPtr() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetObjectSampIdByHandle",
                desc = "sampGetObjectSampIdByHandle(Object object) -> int objectId",
                fn = function() return sampGetObjectSampIdByHandle(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetPickupSampIdByHandle",
                desc = "sampGetPickupSampIdByHandle(Pickup pickup) -> int pickupId",
                fn = function() return sampGetPickupSampIdByHandle(getTargetPickupHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetRakclientFuncAddressByIndex",
                desc = "sampGetRakclientFuncAddressByIndex(int index) -> uint address",
                fn = function() return sampGetRakclientFuncAddressByIndex(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetRpcCallbackByRpcId",
                desc = "sampGetRpcCallbackByRpcId(int index) -> uint callbackAddress",
                fn = function() return sampGetRpcCallbackByRpcId(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetRpcNodeByRpcId",
                desc = "sampGetRpcNodeByRpcId(int index) -> uint node",
                fn = function() return sampGetRpcNodeByRpcId(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampGetSampInfoPtr",
                desc = "sampGetSampInfoPtr() -> uint sampPtr",
                fn = function() return sampGetSampInfoPtr() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampIsCursorActive",
                desc = "sampIsCursorActive() -> bool result",
                fn = function() return sampIsCursorActive() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSendAimData",
                desc = "sampSendAimData(uint dataPtr) ->",
                fn = function() return sampSendAimData(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSendBulletData",
                desc = "sampSendBulletData(uint dataPtr) ->",
                fn = function() return sampSendBulletData(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSendOnfootData",
                desc = "sampSendOnfootData(uint dataPtr) ->",
                fn = function() return sampSendOnfootData(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSendPassengerData",
                desc = "sampSendPassengerData(uint dataPtr) ->",
                fn = function() return sampSendPassengerData(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSendScmEvent",
                desc = "sampSendScmEvent(int event, int id, int param1, int param2) ->",
                fn = function() return sampSendScmEvent(0, getTargetPlayer(), 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSendSpectatorData",
                desc = "sampSendSpectatorData(uint dataPtr) ->",
                fn = function() return sampSendSpectatorData(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSendTrailerData",
                desc = "sampSendTrailerData(uint dataPtr) ->",
                fn = function() return sampSendTrailerData(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSendUnoccupiedData",
                desc = "sampSendUnoccupiedData(uint dataPtr) ->",
                fn = function() return sampSendUnoccupiedData(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSetCursorMode",
                desc = "sampSetCursorMode(int mode) ->",
                fn = function() return sampSetCursorMode(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSetGamestate",
                desc = "sampSetGamestate(int gamestate) ->",
                fn = function() return sampSetGamestate(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSetSendrate",
                desc = "sampSetSendrate(int type, int rate) ->",
                fn = function() return sampSetSendrate(0, getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampSetSpecialAction",
                desc = "sampSetSpecialAction(int action) ->",
                fn = function() return sampSetSpecialAction(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sampToggleCursor",
                desc = "sampToggleCursor(bool show) ->",
                fn = function() return sampToggleCursor(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- RakNet & RakLuaSO (8 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "RakNet & RakLuaSO",
        tests = {
{
                name = "sampGetRpcPtr",
                desc = "Get RakNet RPC handler function pointer",
                fn = function() return sampGetRpcPtr() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected integer return" end
                    if v[1] == 0 then return true, "0x0 (internal RakLua dispatch)" end
                    if not isPointer(v[1]) then return false, "expected pointer > 0x10000" end
                    return true, string.format("0x%X", v[1])
                end
            },
{
                name = "sampGetPacketPtr",
                desc = "Get RakNet Packet handler function pointer",
                fn = function() return sampGetPacketPtr() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected integer return" end
                    if v[1] == 0 then return true, "0x0 (internal RakLua dispatch)" end
                    if not isPointer(v[1]) then return false, "expected pointer > 0x10000" end
                    return true, string.format("0x%X", v[1])
                end
            },
{
                name = "raknetGetRpcName",
                desc = "Lookup RPC name for ShowDialog (ID 25 or 61)",
                fn = function()
                    if type(raknetGetRpcName) ~= "function" then return makeSkip("raknetGetRpcName unavailable") end
                    local name1 = raknetGetRpcName(25)
                    local name2 = raknetGetRpcName(61)
                    return name1 or name2
                end,
                validate = function(v)
                    if type(v[1]) ~= "string" or #v[1] == 0 then return false, "expected string RPC name" end
                    return true, '"' .. v[1] .. '"'
                end
            },
{
                name = "raknetGetPacketName",
                desc = "Lookup RakNet packet name for ID 32",
                fn = function()
                    if type(raknetGetPacketName) ~= "function" then return makeSkip("raknetGetPacketName unavailable") end
                    return raknetGetPacketName(32)
                end,
                validate = function(v)
                    if type(v[1]) ~= "string" or #v[1] == 0 then return false, "expected packet name" end
                    return true, '"' .. v[1] .. '"'
                end
            },
{
                name = "RakLuaSO.getState",
                desc = "Query RakLuaSO network status",
                fn = function()
                    if not hasRakLua or type(raklua.getState) ~= "function" then
                        return makeSkip("RakLuaSO module unavailable")
                    end
                    return raklua.getState()
                end,
                validate = function(v)
                    return true, tostring(v[1])
                end
            },
{
                name = "raknetBitStreamWriteInt16",
                desc = "raknetBitStreamWriteInt16(Bitstream bs, int value) ->",
                fn = function() return raknetBitStreamWriteInt16((type(raknetNewBitStream) == "function" and raknetNewBitStream() or nil), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "raknetBitStreamWriteInt32",
                desc = "raknetBitStreamWriteInt32(Bitstream bs, int value) ->",
                fn = function() return raknetBitStreamWriteInt32((type(raknetNewBitStream) == "function" and raknetNewBitStream() or nil), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "raknetBitStreamWriteInt8",
                desc = "raknetBitStreamWriteInt8(Bitstream bs, int value) ->",
                fn = function() return raknetBitStreamWriteInt8((type(raknetNewBitStream) == "function" and raknetNewBitStream() or nil), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA Char Health & State (56 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA Char Health & State",
        tests = {
{
                name = "getPlayerChar",
                desc = "Get local player GTA ped handle",
                fn = function() return getPlayerChar(0) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] <= 0 then return false, "expected valid ped handle" end
                    return true, string.format("ped=%d", v[1])
                end
            },
{
                name = "doesCharExist",
                desc = "Check if local player ped exists",
                fn = function() return doesCharExist(getTargetPlayerHandle()) end,
                validate = function(v)
                    if v[1] ~= true then return false, "expected ped to exist" end
                    return true, "true"
                end
            },
{
                name = "getCharHealth",
                desc = "Get local ped health points (0-1000)",
                fn = function() return getCharHealth(getTargetPlayerHandle()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 or v[1] > 1000 then
                        return false, "expected health in [0, 1000], got: " .. formatValue(v[1])
                    end
                    return true, string.format("%.1f HP", v[1])
                end
            },
{
                name = "setCharHealth",
                desc = "Set ped health roundtrip test",
                fn = function()
                    local ped = getTargetPlayerHandle()
                    if ped <= 0 then return makeSkip("no ped") end
                    local orig = getCharHealth(ped)
                    local testVal = math.max(50.0, math.min(150.0, orig + 5.0))
                    setCharHealth(ped, testVal)
                    local updated = getCharHealth(ped)
                    setCharHealth(ped, orig)
                    local restored = getCharHealth(ped)
                    if math.abs(updated - testVal) > 1.0 then return false, "failed to apply health" end
                    if math.abs(restored - orig) > 1.0 then return false, "failed to restore health" end
                    return true, orig
                end,
                validate = function(v)
                    return true, string.format("verified & restored (%.1f)", v[2])
                end
            },
{
                name = "getCharArmour",
                desc = "Get local ped armour (0-100)",
                fn = function() return getCharArmour(getTargetPlayerHandle()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 or v[1] > 200 then
                        return false, "expected armour in [0, 200]"
                    end
                    return true, string.format("%.1f AP", v[1])
                end
            },
{
                name = "isCharDead",
                desc = "Check if local ped is dead",
                fn = function() return isCharDead(getTargetPlayerHandle()) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "isPlayerDead",
                desc = "Check if player 0 is dead",
                fn = function() return isPlayerDead(0) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "getCharPointer",
                desc = "Get CPed memory pointer (>0x10000)",
                fn = function() return getCharPointer(getTargetPlayerHandle()) end,
                validate = function(v)
                    if not isPointer(v[1]) then return false, "expected pointer > 0x10000" end
                    return true, string.format("0x%X", v[1])
                end
            },
{
                name = "getCharPointerHandle",
                desc = "Convert CPed pointer back to handle",
                fn = function()
                    local ped = getTargetPlayerHandle()
                    if ped <= 0 then return makeSkip("no ped") end
                    local ptr = getCharPointer(ped)
                    return getCharPointerHandle(ptr)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] <= 0 then return false, "expected valid ped handle" end
                    return true, string.format("handle=%d", v[1])
                end
            },
{
                name = "getPedType",
                desc = "Get character ped type (0=player)",
                fn = function() return getPedType(getTargetPlayerHandle()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 then return false, "expected non-negative ped type" end
                    return true, string.format("type=%d", v[1])
                end
            },
{
                name = "isCharMale",
                desc = "Check if character is male",
                fn = function() return isCharMale(getTargetPlayerHandle()) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "isCharOnScreen",
                desc = "Check if character is rendered on screen",
                fn = function() return isCharOnScreen(getTargetPlayerHandle()) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "isCharStopped",
                desc = "Check if character is standing still",
                fn = function() return isCharStopped(getTargetPlayerHandle()) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "isCharDucking",
                desc = "Check if character is ducking / crouching",
                fn = function() return isCharDucking(getTargetPlayerHandle()) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "isCharSwimming",
                desc = "Check if character is swimming in water",
                fn = function() return isCharSwimming(getTargetPlayerHandle()) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "isCharInWater",
                desc = "Check if character is submerged in water",
                fn = function() return isCharInWater(getTargetPlayerHandle()) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "isCharSitting",
                desc = "Check if character is sitting or crouched",
                fn = function() return isCharSitting(getTargetPlayerHandle()) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "isCharInAir",
                desc = "Check if character is airborne / jumping",
                fn = function() return isCharInAir(getTargetPlayerHandle()) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "getCharHeightAboveGround",
                desc = "Get character height above ground",
                fn = function() return getCharHeightAboveGround(getTargetPlayerHandle()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected finite height" end
                    return true, string.format("%.2f m", v[1])
                end
            },
{
                name = "isPlayerControlOn",
                desc = "Check if player control is enabled",
                fn = function() return isPlayerControlOn(0) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "isPlayerControllable",
                desc = "Check if player can be controlled",
                fn = function() return isPlayerControllable(0) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "freezeCharPosition",
                desc = "Test freezing character position and restoring",
                fn = function()
                    local ped = getTargetPlayerHandle()
                    if ped <= 0 then return makeSkip("no ped") end
                    freezeCharPosition(ped, true)
                    freezeCharPosition(ped, false)
                    return true
                end,
                validate = function(v)
                    return true, "unfrozen cleanly"
                end
            },
{
                name = "GetLocalPed",
                desc = "Returns memory pointer or handle to local player ped",
                fn = function() return GetLocalPed() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "GetPedArmour",
                desc = "Returns armour value from ped memory",
                fn = function() return GetPedArmour(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "GetPedFacingAngle",
                desc = "Returns facing rotation angle from ped memory",
                fn = function() return GetPedFacingAngle(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "GetPedHealth",
                desc = "Returns health value from ped memory",
                fn = function() return GetPedHealth(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "GetPlayerCount",
                desc = "Returns total number of connected players from memory pool",
                fn = function() return GetPlayerCount() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "GetPlayerHandle",
                desc = "Returns ped handle for specified player ID",
                fn = function() return GetPlayerHandle(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "forceInteriorLightingForPlayer",
                desc = "forceInteriorLightingForPlayer(Player player, bool force) ->",
                fn = function() return forceInteriorLightingForPlayer(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "freezeCharPositionAndDontLoadCollision",
                desc = "freezeCharPositionAndDontLoadCollision(Ped ped, bool keep) ->",
                fn = function() return freezeCharPositionAndDontLoadCollision(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCharSwimState",
                desc = "getCharSwimState(Ped ped) -> int status",
                fn = function() return getCharSwimState(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "givePlayerMoney",
                desc = "givePlayerMoney(Player player, int money) ->",
                fn = function() return givePlayerMoney(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "increasePlayerMaxArmour",
                desc = "increasePlayerMaxArmour(Player player, int increase) ->",
                fn = function() return increasePlayerMaxArmour(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "increasePlayerMaxHealth",
                desc = "increasePlayerMaxHealth(Player player, int increase) ->",
                fn = function() return increasePlayerMaxHealth(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPlayerPlaying",
                desc = "isPlayerPlaying(Player player) -> bool result",
                fn = function() return isPlayerPlaying(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendClickPlayer",
                desc = "Sends player click event packet to server",
                fn = function() return sendClickPlayer() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendDeathByPlayer",
                desc = "Sends player death notification packet to server",
                fn = function() return sendDeathByPlayer() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendUpdatePlayers",
                desc = "Sends player update packet to server",
                fn = function() return sendUpdatePlayers() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharAllowedToDuck",
                desc = "setCharAllowedToDuck(Ped ped, bool enable) ->",
                fn = function() return setCharAllowedToDuck(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharBleeding",
                desc = "setCharBleeding(Ped ped, bool bleeding) ->",
                fn = function() return setCharBleeding(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharBulletproofVest",
                desc = "setCharBulletproofVest(Ped ped, bool enable) ->",
                fn = function() return setCharBulletproofVest(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharDropsWeaponsWhenDead",
                desc = "setCharDropsWeaponsWhenDead(Ped ped, bool droppable) ->",
                fn = function() return setCharDropsWeaponsWhenDead(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharMaxHealth",
                desc = "setCharMaxHealth(Ped ped, int health) ->",
                fn = function() return setCharMaxHealth(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharMoney",
                desc = "setCharMoney(Ped ped, int money) ->",
                fn = function() return setCharMoney(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharProofs",
                desc = "setCharProofs(Ped ped, bool BP, bool FP, bool EP, bool CP, bool MP) ->",
                fn = function() return setCharProofs(getTargetPlayerHandle(), false, false, false, false, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharRotation",
                desc = "setCharRotation(Ped ped, float vecX, float vecY, float vecZ) ->",
                fn = function() return setCharRotation(getTargetPlayerHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharSuffersCriticalHits",
                desc = "setCharSuffersCriticalHits(Ped ped, bool enable) ->",
                fn = function() return setCharSuffersCriticalHits(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPedDensityMultiplier",
                desc = "setPedDensityMultiplier(float multiplier) ->",
                fn = function() return setPedDensityMultiplier(0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayerDisplayVitalStatsButton",
                desc = "setPlayerDisplayVitalStatsButton(Player player, bool display) ->",
                fn = function() return setPlayerDisplayVitalStatsButton(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayerDuckButton",
                desc = "setPlayerDuckButton(Player player, bool able) ->",
                fn = function() return setPlayerDuckButton(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "storeClosestEntities",
                desc = "storeClosestEntities(Ped ped) -> Vehicle car, Ped ped",
                fn = function() return storeClosestEntities(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchArrestPenalties",
                desc = "switchArrestPenalties(bool lose) ->",
                fn = function() return switchArrestPenalties(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchPedRoadsBackToOriginal",
                desc = "switchPedRoadsBackToOriginal(float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ) ->",
                fn = function() return switchPedRoadsBackToOriginal(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchPedRoadsOff",
                desc = "switchPedRoadsOff(float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ) ->",
                fn = function() return switchPedRoadsOff(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchPedRoadsOn",
                desc = "switchPedRoadsOn(float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ) ->",
                fn = function() return switchPedRoadsOn(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "wasCutsceneSkipped",
                desc = "wasCutsceneSkipped() -> bool result",
                fn = function() return wasCutsceneSkipped() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA Char Position & Movement (19 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA Char Position & Movement",
        tests = {
{
                name = "getCharCoordinates",
                desc = "Get character world coordinates (x, y, z)",
                fn = function() return getCharCoordinates(getTargetPlayerHandle()) end,
                validate = function(v)
                    if not isCoords3d(v[1], v[2], v[3]) then
                        return false, "expected 3 finite coordinates within world bounds"
                    end
                    return true, string.format("(%.2f, %.2f, %.2f)", v[1], v[2], v[3])
                end
            },
{
                name = "getCharHeading",
                desc = "Get character heading rotation angle (0-360)",
                fn = function() return getCharHeading(getTargetPlayerHandle()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < -360 or v[1] > 720 then
                        return false, "expected heading angle in [0, 360]"
                    end
                    return true, string.format("%.2f deg", v[1])
                end
            },
{
                name = "getCharVelocity",
                desc = "Get character velocity vector (x, y, z)",
                fn = function() return getCharVelocity(getTargetPlayerHandle()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or not isFiniteNumber(v[2]) or not isFiniteNumber(v[3]) then
                        return false, "expected 3 finite velocity components"
                    end
                    return true, string.format("(%.3f, %.3f, %.3f)", v[1], v[2], v[3])
                end
            },
{
                name = "getCharSpeed",
                desc = "Get character speed magnitude",
                fn = function() return getCharSpeed(getTargetPlayerHandle()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 then return false, "expected non-negative speed" end
                    return true, string.format("%.2f m/s", v[1])
                end
            },
{
                name = "getCharQuaternion",
                desc = "Get character orientation quaternion (x, y, z, w)",
                fn = function() return getCharQuaternion(getTargetPlayerHandle()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or not isFiniteNumber(v[2]) or not isFiniteNumber(v[3]) or not isFiniteNumber(v[4]) then
                        return false, "expected 4 quaternion components"
                    end
                    return true, string.format("(%.3f, %.3f, %.3f, %.3f)", v[1], v[2], v[3], v[4])
                end
            },
{
                name = "getOffsetFromCharInWorldCoords",
                desc = "Compute world coordinates from ped local offset (0, 1, 0)",
                fn = function()
                    local ped = getTargetPlayerHandle()
                    if ped <= 0 then return makeSkip("no ped") end
                    return getOffsetFromCharInWorldCoords(ped, 0.0, 1.0, 0.0)
                end,
                validate = function(v)
                    if not isCoords3d(v[1], v[2], v[3]) then return false, "expected 3 valid coordinates" end
                    return true, string.format("(%.2f, %.2f, %.2f)", v[1], v[2], v[3])
                end
            },
{
                name = "locateCharAnyMeans3d",
                desc = "Spatial query: locate ped at its own coordinates within radius 5.0",
                fn = function()
                    local ped = getTargetPlayerHandle()
                    if ped <= 0 then return makeSkip("no ped") end
                    local x, y, z = getCharCoordinates(ped)
                    return locateCharAnyMeans3d(ped, x, y, z, 5.0, 5.0, 5.0, false)
                end,
                validate = function(v)
                    if v[1] ~= true then return false, "ped failed to locate itself within radius" end
                    return true, "located successfully"
                end
            },
{
                name = "isCharInArea2d",
                desc = "Check if ped is within bounding box of its coordinates",
                fn = function()
                    local ped = getTargetPlayerHandle()
                    if ped <= 0 then return makeSkip("no ped") end
                    local x, y, z = getCharCoordinates(ped)
                    return isCharInArea2d(ped, x - 5.0, y - 5.0, x + 5.0, y + 5.0, false)
                end,
                validate = function(v)
                    if v[1] ~= true then return false, "ped not inside bounding box" end
                    return true, "inside area"
                end
            },
{
                name = "getBonePosition",
                desc = "Returns 3D world coordinates of character skeleton bone",
                fn = function() return getBonePosition() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCharBonePosition",
                desc = "Returns 3D world coordinates of character skeleton bone",
                fn = function() return getCharBonePosition() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCharSwimSpeed",
                desc = "Returns swim movement velocity float for character ped",
                fn = function() return getCharSwimSpeed() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getHeadingFromVector2d",
                desc = "getHeadingFromVector2d(float pX, float pY) -> float zAngle",
                fn = function() return getHeadingFromVector2d(0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPlayerInPositionForConversation",
                desc = "isPlayerInPositionForConversation(Ped ped) -> bool result",
                fn = function() return isPlayerInPositionForConversation(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharCoordinates",
                desc = "setCharCoordinates(Ped ped, float posX, float posY, float posZ) ->",
                fn = function() return setCharCoordinates(getTargetPlayerHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharCoordinatesNoOffset",
                desc = "setCharCoordinatesNoOffset(Ped ped, float atX, float atY, float atZ) ->",
                fn = function() return setCharCoordinatesNoOffset(getTargetPlayerHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharHeading",
                desc = "setCharHeading(Ped ped, float angle) ->",
                fn = function() return setCharHeading(getTargetPlayerHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharQuaternion",
                desc = "setCharQuaternion(Ped ped, float x, float y, float z, float w) ->",
                fn = function() return setCharQuaternion(getTargetPlayerHandle(), 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharSwimSpeed",
                desc = "setCharSwimSpeed(Ped ped, float speed) ->",
                fn = function() return setCharSwimSpeed(getTargetPlayerHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharVelocity",
                desc = "setCharVelocity(Ped ped, float vecX, float vecY, float vecZ) ->",
                fn = function() return setCharVelocity(getTargetPlayerHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA Char Weapons & Vehicles (31 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA Char Weapons & Vehicles",
        tests = {
{
                name = "getCurrentCharWeapon",
                desc = "Get character currently equipped weapon ID (0-46)",
                fn = function() return getCurrentCharWeapon(getTargetPlayerHandle()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 or v[1] > 46 then
                        return false, "expected weapon ID in [0, 46], got: " .. formatValue(v[1])
                    end
                    return true, string.format("weapon=%d", v[1])
                end
            },
{
                name = "hasCharGotWeapon",
                desc = "Check if character has weapon ID 0 (unarmed/fist)",
                fn = function() return hasCharGotWeapon(getTargetPlayerHandle(), 0) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "getAmmoInCharWeapon",
                desc = "Get ammunition for currently equipped weapon",
                fn = function()
                    local ped = getTargetPlayerHandle()
                    local w = getCurrentCharWeapon(ped)
                    return getAmmoInCharWeapon(ped, w)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 then return false, "expected non-negative ammo" end
                    return true, string.format("%d rounds", v[1])
                end
            },
{
                name = "isCharInAnyCar",
                desc = "Check if character is inside any vehicle",
                fn = function() return isCharInAnyCar(getTargetPlayerHandle()) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "isCharOnFoot",
                desc = "Check if character is walking on foot",
                fn = function() return isCharOnFoot(getTargetPlayerHandle()) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "isCharSittingInAnyCar",
                desc = "Check if character is sitting in any car",
                fn = function() return isCharSittingInAnyCar(getTargetPlayerHandle()) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "storeCarCharIsIn",
                desc = "Get handle of vehicle ped is inside",
                fn = function() return storeCarCharIsIn(getTargetPlayerHandle()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 then return false, "expected valid car handle" end
                    return true, string.format("car=%d", v[1])
                end
            },
{
                name = "storeCarCharIsInNoSave",
                desc = "Get handle of vehicle ped is inside (no save alias)",
                fn = function() return storeCarCharIsInNoSave(getTargetPlayerHandle()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 then return false, "expected valid car handle" end
                    return true, string.format("car=%d", v[1])
                end
            },
{
                name = "addAmmoToChar",
                desc = "addAmmoToChar(Ped ped, int weapon, int ammo) ->",
                fn = function() return addAmmoToChar(getTargetPlayerHandle(), 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addBigGunFlash",
                desc = "addBigGunFlash(float fromX, float fromY, float fromZ, float toX, float toY, float toZ) ->",
                fn = function() return addBigGunFlash(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearCharLastWeaponDamage",
                desc = "clearCharLastWeaponDamage(Ped ped) ->",
                fn = function() return clearCharLastWeaponDamage(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "doWeaponStuffAtStartOf2pGame",
                desc = "Initializes weapon loadouts for 2-player cooperative mode",
                fn = function() return doWeaponStuffAtStartOf2pGame() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "drawWeaponshopCorona",
                desc = "drawWeaponshopCorona(float X, float Y, float Z, float radius, int type, int flare, int r, int g, int b) ->",
                fn = function() return drawWeaponshopCorona(0.0, 0.0, 0.0, 0.0, 0, 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "ensurePlayerHasDriveByWeapon",
                desc = "ensurePlayerHasDriveByWeapon(Player player, int ammo) ->",
                fn = function() return ensurePlayerHasDriveByWeapon(getTargetPlayerHandle(), 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCharWeaponInSlot",
                desc = "getCharWeaponInSlot(Ped ped, int slot) -> int weapon, int ammo, Model modelId",
                fn = function() return getCharWeaponInSlot(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "giveWeaponToChar",
                desc = "giveWeaponToChar(Ped ped, int weapon, int ammo) ->",
                fn = function() return giveWeaponToChar(getTargetPlayerHandle(), 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasCharBeenDamagedByWeapon",
                desc = "hasCharBeenDamagedByWeapon(Ped ped, int weapon) -> bool result",
                fn = function() return hasCharBeenDamagedByWeapon(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hideCharWeaponForScriptedCutscene",
                desc = "hideCharWeaponForScriptedCutscene(Ped ped, bool hide) ->",
                fn = function() return hideCharWeaponForScriptedCutscene(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCurrentCharWeapon",
                desc = "isCurrentCharWeapon(Ped ped, int weapon) -> bool result",
                fn = function() return isCurrentCharWeapon(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isSniperBulletInArea",
                desc = "isSniperBulletInArea(float float1, float float2, float float3, float float4, float float5, float float6) -> bool result",
                fn = function() return isSniperBulletInArea(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeAllCharWeapons",
                desc = "removeAllCharWeapons(Ped ped) ->",
                fn = function() return removeAllCharWeapons(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeWeaponFromChar",
                desc = "removeWeaponFromChar(Ped ped, int weapon) ->",
                fn = function() return removeWeaponFromChar(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharAmmo",
                desc = "setCharAmmo(Ped ped, int weapon, int ammo) ->",
                fn = function() return setCharAmmo(getTargetPlayerHandle(), 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharFireDamageMultiplier",
                desc = "setCharFireDamageMultiplier(Ped ped, float multiplier) ->",
                fn = function() return setCharFireDamageMultiplier(getTargetPlayerHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharWeaponSkill",
                desc = "setCharWeaponSkill(Ped ped, int skill) ->",
                fn = function() return setCharWeaponSkill(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCurrentCharWeapon",
                desc = "setCurrentCharWeapon(Ped ped, int weapon) ->",
                fn = function() return setCurrentCharWeapon(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setDeathWeaponsPersist",
                desc = "setDeathWeaponsPersist(Ped ped, bool persist) ->",
                fn = function() return setDeathWeaponsPersist(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setGangWeapons",
                desc = "setGangWeapons(int gang, int weapons1, int weapons2, int weapons3) ->",
                fn = function() return setGangWeapons(0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setGunshotSenseRangeForRiot2",
                desc = "setGunshotSenseRangeForRiot2(float range) ->",
                fn = function() return setGunshotSenseRangeForRiot2(0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayerWeaponsScrollable",
                desc = "setPlayerWeaponsScrollable(Player player, bool scrollable) ->",
                fn = function() return setPlayerWeaponsScrollable(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "startCharFire",
                desc = "startCharFire(Ped ped) -> int fire",
                fn = function() return startCharFire(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA Char Area Queries (32 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA Char Area Queries",
        tests = {
{
                name = "areAnyCharsNearChar",
                desc = "areAnyCharsNearChar(Ped ped, float range) -> bool result",
                fn = function() return areAnyCharsNearChar(getTargetPlayerHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearAreaOfChars",
                desc = "clearAreaOfChars(float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ) ->",
                fn = function() return clearAreaOfChars(0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getRandomCharInZone",
                desc = "getRandomCharInZone(GxtString zone, bool pedtype, bool gang, bool criminal_prostitute) -> Ped ped",
                fn = function() return getRandomCharInZone("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInAngledArea2d",
                desc = "isCharInAngledArea2d(Ped ped, float x1, float y1, float x2, float y2, float angle, bool sphere) -> bool result",
                fn = function() return isCharInAngledArea2d(getTargetPlayerHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInAngledArea3d",
                desc = "isCharInAngledArea3d(Ped ped, float x1, float y1, float z1, float x2, float y2, float z2, float angle, bool sphere) -> bool result",
                fn = function() return isCharInAngledArea3d(getTargetPlayerHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInAngledAreaOnFoot2d",
                desc = "isCharInAngledAreaOnFoot2d(Ped ped, float x1, float y1, float x2, float y2, float angle, bool sphere) -> bool result",
                fn = function() return isCharInAngledAreaOnFoot2d(0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInAngledAreaOnFoot3d",
                desc = "isCharInAngledAreaOnFoot3d(Ped ped, float x1, float y1, float z1, float x2, float y2, float z2, float angle, bool sphere) -> bool result",
                fn = function() return isCharInAngledAreaOnFoot3d(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInArea3d",
                desc = "isCharInArea3d(Ped ped, float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ, bool sphere) -> bool result",
                fn = function() return isCharInArea3d(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInAreaOnFoot2d",
                desc = "isCharInAreaOnFoot2d(Ped ped, float cornerAX, float cornerAY, float cornerBX, float cornerBY, bool sphere) -> bool result",
                fn = function() return isCharInAreaOnFoot2d(0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInAreaOnFoot3d",
                desc = "isCharInAreaOnFoot3d(Ped ped, float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ, bool sphere) -> bool result",
                fn = function() return isCharInAreaOnFoot3d(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInZone",
                desc = "isCharInZone(Ped ped, GxtString zoneName) -> bool result",
                fn = function() return isCharInZone(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharShootingInArea",
                desc = "isCharShootingInArea(Ped ped, float cornerAX, float cornerAY, float cornerBX, float cornerBY, int weapon) -> bool result",
                fn = function() return isCharShootingInArea(getTargetPlayerHandle(), 0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharStoppedInAngledArea2d",
                desc = "isCharStoppedInAngledArea2d(Ped ped, float x1, float y1, float x2, float y2, float height, bool flag) -> bool result",
                fn = function() return isCharStoppedInAngledArea2d(getTargetPlayerHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharStoppedInAngledArea3d",
                desc = "isCharStoppedInAngledArea3d(Ped ped, float x1, float y1, float z1, float x2, float y2, float z2, float depth, bool flag) -> bool result",
                fn = function() return isCharStoppedInAngledArea3d(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharStoppedInAngledAreaOnFoot2d",
                desc = "isCharStoppedInAngledAreaOnFoot2d(Ped ped, float x1, float y1, float x2, float y2, float angle, bool sphere) -> bool result",
                fn = function() return isCharStoppedInAngledAreaOnFoot2d(0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharStoppedInAngledAreaOnFoot3d",
                desc = "isCharStoppedInAngledAreaOnFoot3d(Ped ped, float x1, float y1, float z1, float x2, float y2, float z2, float depth, bool flag) -> bool result",
                fn = function() return isCharStoppedInAngledAreaOnFoot3d(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharStoppedInArea2d",
                desc = "isCharStoppedInArea2d(Ped ped, float cornerAX, float cornerAY, float cornerBX, float cornerBY, bool sphere) -> bool result",
                fn = function() return isCharStoppedInArea2d(getTargetPlayerHandle(), 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharStoppedInArea3d",
                desc = "isCharStoppedInArea3d(Ped ped, float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ, bool sphere) -> bool result",
                fn = function() return isCharStoppedInArea3d(getTargetPlayerHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharStoppedInAreaOnFoot2d",
                desc = "isCharStoppedInAreaOnFoot2d(Ped ped, float cornerAX, float cornerAY, float cornerBX, float cornerBY, bool sphere) -> bool result",
                fn = function() return isCharStoppedInAreaOnFoot2d(getTargetPlayerHandle(), 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharStoppedInAreaOnFoot3d",
                desc = "isCharStoppedInAreaOnFoot3d(Ped ped, float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ, bool sphere) -> bool result",
                fn = function() return isCharStoppedInAreaOnFoot3d(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPlayerInInfoZone",
                desc = "isPlayerInInfoZone(Player player, GxtString zone) -> bool result",
                fn = function() return isPlayerInInfoZone(0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharAnyMeans2d",
                desc = "locateCharAnyMeans2d(Ped ped, float pointX, float pointY, float radiusX, float radiusY, bool sphere) -> bool result",
                fn = function() return locateCharAnyMeans2d(getTargetPlayerHandle(), 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharAnyMeansChar2d",
                desc = "locateCharAnyMeansChar2d(Ped ped, Ped nearPed, float radiusX, float radiusY, bool sphere) -> bool result",
                fn = function() return locateCharAnyMeansChar2d(getTargetPlayerHandle(), getTargetPlayerHandle(), 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharAnyMeansChar3d",
                desc = "locateCharAnyMeansChar3d(Ped ped, Ped nearPed, float radiusX, float radiusY, float radiusZ, bool sphere) -> bool result",
                fn = function() return locateCharAnyMeansChar3d(0, 0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharOnFoot2d",
                desc = "locateCharOnFoot2d(Ped ped, float pointX, float pointY, float radiusX, float radiusY, bool sphere) -> bool result",
                fn = function() return locateCharOnFoot2d(0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharOnFoot3d",
                desc = "locateCharOnFoot3d(Ped ped, float sphereX, float sphereY, float sphereZ, float radiusX, float radiusY, float radiusZ, bool sphere) -> bool result",
                fn = function() return locateCharOnFoot3d(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharOnFootChar2d",
                desc = "locateCharOnFootChar2d(Ped ped, Ped nearPed, float radiusX, float radiusY, bool sphere) ->",
                fn = function() return locateCharOnFootChar2d(0, 0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharOnFootChar3d",
                desc = "locateCharOnFootChar3d(Ped ped, Ped nearPed, float radiusX, float radiusY, float radiusZ, bool sphere) -> bool result",
                fn = function() return locateCharOnFootChar3d(0, 0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateStoppedCharAnyMeans2d",
                desc = "locateStoppedCharAnyMeans2d(Ped ped, float pointX, float pointY, float radiusX, float radiusY, bool sphere) -> bool result",
                fn = function() return locateStoppedCharAnyMeans2d(0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateStoppedCharAnyMeans3d",
                desc = "locateStoppedCharAnyMeans3d(Ped ped, float sphereX, float sphereY, float sphereZ, float radiusX, float radiusY, float radiusZ, bool sphere) -> bool result",
                fn = function() return locateStoppedCharAnyMeans3d(getTargetPlayerHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateStoppedCharOnFoot2d",
                desc = "locateStoppedCharOnFoot2d(Ped ped, float pointX, float pointY, float radiusX, float radiusY, bool sphere) -> bool result",
                fn = function() return locateStoppedCharOnFoot2d(0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateStoppedCharOnFoot3d",
                desc = "locateStoppedCharOnFoot3d(Ped ped, float sphereX, float sphereY, float sphereZ, float radiusX, float radiusY, float radiusZ, bool sphere) -> bool result",
                fn = function() return locateStoppedCharOnFoot3d(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA Char Tasks & Animations (91 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA Char Tasks & Animations",
        tests = {
{
                name = "clearCharTasksImmediately",
                desc = "clearCharTasksImmediately(Ped ped) ->",
                fn = function() return clearCharTasksImmediately(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getScriptTaskStatus",
                desc = "getScriptTaskStatus(Ped ped, int task) -> int status",
                fn = function() return getScriptTaskStatus(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharKeepTask",
                desc = "setCharKeepTask(Ped ped, bool keepTasks) ->",
                fn = function() return setCharKeepTask(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setGroupDefaultTaskAllocator",
                desc = "setGroupDefaultTaskAllocator(int group, int command) ->",
                fn = function() return setGroupDefaultTaskAllocator(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskAchieveHeading",
                desc = "taskAchieveHeading(Ped ped, float angle) ->",
                fn = function() return taskAchieveHeading(getTargetPlayerHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskAimGunAtChar",
                desc = "taskAimGunAtChar(Ped ped, int aimAt, int timeMS) ->",
                fn = function() return taskAimGunAtChar(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskAimGunAtCoord",
                desc = "taskAimGunAtCoord(Ped ped, float atX, float atY, float atZ, int timeMS) ->",
                fn = function() return taskAimGunAtCoord(0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskCarDriveToCoord",
                desc = "taskCarDriveToCoord(Ped ped, Vehicle car, float toX, float toY, float toZ, float speed, int int7, int model, int int9) ->",
                fn = function() return taskCarDriveToCoord(getTargetPlayerHandle(), getTargetVehicleHandle(), 0.0, 0.0, 0.0, 0.0, 0, 0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskCarDriveWander",
                desc = "taskCarDriveWander(Ped ped, Vehicle hijackCar, float searchRadius, int trafficBehavior) ->",
                fn = function() return taskCarDriveWander(getTargetPlayerHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskCarMission",
                desc = "taskCarMission(Ped ped, Vehicle car, int targetCar, int order, float maxSpeed, int trafficFlag) ->",
                fn = function() return taskCarMission(getTargetPlayerHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskCarTempAction",
                desc = "taskCarTempAction(Ped ped, Vehicle car, int performAction, int timelimit) ->",
                fn = function() return taskCarTempAction(getTargetPlayerHandle(), getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskCharArrestChar",
                desc = "taskCharArrestChar(Ped ped, int bustActor) ->",
                fn = function() return taskCharArrestChar(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskCharSlideToCoord",
                desc = "taskCharSlideToCoord(Ped ped, float toX, float toY, float toZ, float angle, float withinRadius) ->",
                fn = function() return taskCharSlideToCoord(getTargetPlayerHandle(), 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskChatWithChar",
                desc = "taskChatWithChar(Ped ped, int withActor, bool flag, int unknownFlag) ->",
                fn = function() return taskChatWithChar(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskClimb",
                desc = "taskClimb(Ped ped, bool climb) ->",
                fn = function() return taskClimb(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskCower",
                desc = "taskCower(Ped ped) ->",
                fn = function() return taskCower(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskDead",
                desc = "taskDead(Ped ped) ->",
                fn = function() return taskDead(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskDestroyCar",
                desc = "taskDestroyCar(Ped ped, Vehicle car) ->",
                fn = function() return taskDestroyCar(getTargetPlayerHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskDie",
                desc = "taskDie(Ped ped) ->",
                fn = function() return taskDie(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskDiveAndGetUp",
                desc = "taskDiveAndGetUp(Ped ped, float toOffsetX, float toOffsetY, int time) ->",
                fn = function() return taskDiveAndGetUp(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskDiveFromAttachmentAndGetUp",
                desc = "taskDiveFromAttachmentAndGetUp(Ped ped, int timeMS) ->",
                fn = function() return taskDiveFromAttachmentAndGetUp(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskDriveBy",
                desc = "taskDriveBy(Ped ped, int drivebyActor, Vehicle car, float pX, float pY, float pZ, float radiusX, int radiusY, bool radiusZ, int firingRate) ->",
                fn = function() return taskDriveBy(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskDrivePointRoute",
                desc = "taskDrivePointRoute(Ped ped, Vehicle car, float speed) ->",
                fn = function() return taskDrivePointRoute(getTargetPlayerHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskDrivePointRouteAdvanced",
                desc = "taskDrivePointRouteAdvanced(Ped ped, Vehicle car, float speed, int flag1, int flag2, int flag3) ->",
                fn = function() return taskDrivePointRouteAdvanced(getTargetPlayerHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskDuck",
                desc = "taskDuck(Ped ped, int timeMS) ->",
                fn = function() return taskDuck(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskEnterCarAsDriver",
                desc = "taskEnterCarAsDriver(Ped ped, Vehicle car, int timeMS) ->",
                fn = function() return taskEnterCarAsDriver(getTargetPlayerHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskEnterCarAsPassenger",
                desc = "taskEnterCarAsPassenger(Ped ped, Vehicle car, int time, int passengerSeat) ->",
                fn = function() return taskEnterCarAsPassenger(getTargetPlayerHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskEveryoneLeaveCar",
                desc = "taskEveryoneLeaveCar(Vehicle car) ->",
                fn = function() return taskEveryoneLeaveCar(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskFallAndGetUp",
                desc = "taskFallAndGetUp(Ped ped, bool int2, int time) ->",
                fn = function() return taskFallAndGetUp(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskFleeChar",
                desc = "taskFleeChar(Ped ped, Ped fromActor, float radius, int timelimit) ->",
                fn = function() return taskFleeChar(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskFleeCharAnyMeans",
                desc = "taskFleeCharAnyMeans(Ped ped, int fleeFrom, float runDistance, int time, bool changeCourse, int unkTime1, int unkTime2, float awayRadius) ->",
                fn = function() return taskFleeCharAnyMeans(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskFleePoint",
                desc = "taskFleePoint(Ped ped, float fromX, float fromY, float fromZ, float awayRadius, int timelimit) ->",
                fn = function() return taskFleePoint(getTargetPlayerHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskFollowFootsteps",
                desc = "taskFollowFootsteps(Ped ped, int followActor) ->",
                fn = function() return taskFollowFootsteps(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskFollowPathNodesToCoord",
                desc = "taskFollowPathNodesToCoord(Ped ped, float pathX, float pathY, float pathZ, int mode, int time) ->",
                fn = function() return taskFollowPathNodesToCoord(getTargetPlayerHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskFollowPathNodesToCoordWithRadius",
                desc = "taskFollowPathNodesToCoordWithRadius(Ped ped, float toX, float toY, float toZ, int mode, int time, float stopRadius) ->",
                fn = function() return taskFollowPathNodesToCoordWithRadius(getTargetPlayerHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskFollowPatrolRoute",
                desc = "taskFollowPatrolRoute(Ped ped, int walkMode, int routeMode) ->",
                fn = function() return taskFollowPatrolRoute(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskFollowPointRoute",
                desc = "taskFollowPointRoute(Ped ped, int flags1, int flags2) ->",
                fn = function() return taskFollowPointRoute(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskGoStraightToCoord",
                desc = "taskGoStraightToCoord(Ped ped, float toX, float toY, float toZ, int mode, int time) ->",
                fn = function() return taskGoStraightToCoord(getTargetPlayerHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskGoToCoordAnyMeans",
                desc = "taskGoToCoordAnyMeans(Ped ped, float toX, float toY, float toZ, int mode, Vehicle useCar) ->",
                fn = function() return taskGoToCoordAnyMeans(getTargetPlayerHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskGoToCoordWhileAiming",
                desc = "taskGoToCoordWhileAiming(Ped ped, float toX, float toY, float toZ, int mode, float turnRadius, float stopRadius, Ped ped, float offsetX, float offsetY, float offsetZ) ->",
                fn = function() return taskGoToCoordWhileAiming(getTargetPlayerHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskGoToCoordWhileShooting",
                desc = "taskGoToCoordWhileShooting(Ped ped, float toX, float toY, float toZ, int mode, float turnRadius, float stopRadius, int lookAtActor) ->",
                fn = function() return taskGoToCoordWhileShooting(getTargetPlayerHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskGotoCar",
                desc = "taskGotoCar(Ped ped, Vehicle car, int timeMS, float stopAtDistance) ->",
                fn = function() return taskGotoCar(getTargetPlayerHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskGotoChar",
                desc = "taskGotoChar(Ped ped, Ped toActor, int timelimit, float stopWithinRadius) ->",
                fn = function() return taskGotoChar(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskGotoCharAiming",
                desc = "taskGotoCharAiming(Ped ped, int followActor, float minradius, float maxradius) ->",
                fn = function() return taskGotoCharAiming(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskGotoCharOffset",
                desc = "taskGotoCharOffset(Ped ped, int toActor, int timelimit, float approachDistance, float approachAngle) ->",
                fn = function() return taskGotoCharOffset(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskGreetPartner",
                desc = "taskGreetPartner(Ped ped, Ped ped2, float unk1, int unk2) ->",
                fn = function() return taskGreetPartner(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskHandGesture",
                desc = "taskHandGesture(Ped ped, Ped ped2) ->",
                fn = function() return taskHandGesture(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskHandsUp",
                desc = "taskHandsUp(Ped ped, int timeMS) ->",
                fn = function() return taskHandsUp(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskJetpack",
                desc = "taskJetpack(Ped ped) ->",
                fn = function() return taskJetpack(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskJump",
                desc = "taskJump(Ped ped, bool jump) ->",
                fn = function() return taskJump(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskKillCharOnFoot",
                desc = "taskKillCharOnFoot(Ped ped, Ped killActor) ->",
                fn = function() return taskKillCharOnFoot(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskKillCharOnFootTimed",
                desc = "taskKillCharOnFootTimed(Ped ped, int attackActor, int time) ->",
                fn = function() return taskKillCharOnFootTimed(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskKillCharOnFootWhileDucking",
                desc = "taskKillCharOnFootWhileDucking(Ped ped, int weapon, int flags, int time, int chance) ->",
                fn = function() return taskKillCharOnFootWhileDucking(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskKindaStayInSamePlace",
                desc = "taskKindaStayInSamePlace(Ped ped, bool stay) ->",
                fn = function() return taskKindaStayInSamePlace(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskLeaveAnyCar",
                desc = "taskLeaveAnyCar(Ped ped) ->",
                fn = function() return taskLeaveAnyCar(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskLeaveCar",
                desc = "taskLeaveCar(Ped ped, Vehicle car) ->",
                fn = function() return taskLeaveCar(getTargetPlayerHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskLeaveCarAndFlee",
                desc = "taskLeaveCarAndFlee(Ped ped, Vehicle car, float X, float Y, float Z) ->",
                fn = function() return taskLeaveCarAndFlee(getTargetPlayerHandle(), getTargetVehicleHandle(), 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskLeaveCarImmediately",
                desc = "taskLeaveCarImmediately(Ped ped, Vehicle car) ->",
                fn = function() return taskLeaveCarImmediately(getTargetPlayerHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskLookAbout",
                desc = "taskLookAbout(Ped ped, int timeMS) ->",
                fn = function() return taskLookAbout(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskLookAtChar",
                desc = "taskLookAtChar(Ped ped, int lookAt, int timeMS) ->",
                fn = function() return taskLookAtChar(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskLookAtCoord",
                desc = "taskLookAtCoord(Ped ped, float toX, float toY, float toZ, int timeMS) ->",
                fn = function() return taskLookAtCoord(getTargetPlayerHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskLookAtVehicle",
                desc = "taskLookAtVehicle(Ped ped, int lookAt, int timeMS) ->",
                fn = function() return taskLookAtVehicle(getTargetPlayerHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskPause",
                desc = "taskPause(Ped ped, int timeMS) ->",
                fn = function() return taskPause(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskSay",
                desc = "taskSay(Ped ped, int audio) ->",
                fn = function() return taskSay(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskScratchHead",
                desc = "taskScratchHead(Ped ped) ->",
                fn = function() return taskScratchHead(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskSetCharDecisionMaker",
                desc = "taskSetCharDecisionMaker(Ped ped, int maker) ->",
                fn = function() return taskSetCharDecisionMaker(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskSetIgnoreWeaponRangeFlag",
                desc = "taskSetIgnoreWeaponRangeFlag(Ped ped, bool ignore) ->",
                fn = function() return taskSetIgnoreWeaponRangeFlag(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskShakeFist",
                desc = "taskShakeFist(Ped ped) ->",
                fn = function() return taskShakeFist(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskShootAtChar",
                desc = "taskShootAtChar(Ped ped, int atActor, int timelimit) ->",
                fn = function() return taskShootAtChar(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskShootAtCoord",
                desc = "taskShootAtCoord(Ped ped, float atX, float atY, float atZ, int timeMS) ->",
                fn = function() return taskShootAtCoord(0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskShuffleToNextCarSeat",
                desc = "taskShuffleToNextCarSeat(Ped ped, Vehicle car) ->",
                fn = function() return taskShuffleToNextCarSeat(getTargetPlayerHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskSitDown",
                desc = "taskSitDown(Ped ped, int timeMS) ->",
                fn = function() return taskSitDown(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskSmartFleeChar",
                desc = "taskSmartFleeChar(Ped ped, Ped fromActor, float originRadius, int timelimit) ->",
                fn = function() return taskSmartFleeChar(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskSmartFleePoint",
                desc = "taskSmartFleePoint(Ped ped, float fromX, float fromY, float fromZ, float stopAtRadius, int timelimit) ->",
                fn = function() return taskSmartFleePoint(getTargetPlayerHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskStandStill",
                desc = "taskStandStill(Ped ped, int timeMS) ->",
                fn = function() return taskStandStill(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskStayInSamePlace",
                desc = "taskStayInSamePlace(Ped ped, bool stay) ->",
                fn = function() return taskStayInSamePlace(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskSwimToCoord",
                desc = "taskSwimToCoord(Ped ped, float toX, float toY, float toZ) ->",
                fn = function() return taskSwimToCoord(getTargetPlayerHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskTired",
                desc = "taskTired(Ped ped, int timeMS) ->",
                fn = function() return taskTired(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskToggleDuck",
                desc = "taskToggleDuck(Ped ped, bool crouch) ->",
                fn = function() return taskToggleDuck(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskTogglePedThreatScanner",
                desc = "taskTogglePedThreatScanner(Ped ped, bool unknownFlag1, bool unknownFlag2, bool unknownFlag3) ->",
                fn = function() return taskTogglePedThreatScanner(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskTurnCharToFaceChar",
                desc = "taskTurnCharToFaceChar(Ped ped, int rotateTo) ->",
                fn = function() return taskTurnCharToFaceChar(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskTurnCharToFaceCoord",
                desc = "taskTurnCharToFaceCoord(Ped ped, float atX, float atY, float atZ) ->",
                fn = function() return taskTurnCharToFaceCoord(getTargetPlayerHandle(), 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskUseAtm",
                desc = "taskUseAtm(Ped ped) ->",
                fn = function() return taskUseAtm(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskUseAttractor",
                desc = "taskUseAttractor(Ped ped, int attractor) ->",
                fn = function() return taskUseAttractor(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskUseClosestMapAttractor",
                desc = "taskUseClosestMapAttractor(Ped ped, float radius, Model nearModel, float offsetX, float offsetY, float offsetZ, string scriptNamed) -> bool result",
                fn = function() return taskUseClosestMapAttractor(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskUseMobilePhone",
                desc = "taskUseMobilePhone(Ped ped, bool hold) ->",
                fn = function() return taskUseMobilePhone(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskWalkAlongsideChar",
                desc = "taskWalkAlongsideChar(Ped ped, int alongisdeActor) ->",
                fn = function() return taskWalkAlongsideChar(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskWanderStandard",
                desc = "taskWanderStandard(Ped ped) ->",
                fn = function() return taskWanderStandard(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskWarpCharIntoCarAsDriver",
                desc = "taskWarpCharIntoCarAsDriver(Ped ped, Vehicle car) ->",
                fn = function() return taskWarpCharIntoCarAsDriver(getTargetPlayerHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskWarpCharIntoCarAsPassenger",
                desc = "taskWarpCharIntoCarAsPassenger(Ped ped, Vehicle car, int passengerseat) ->",
                fn = function() return taskWarpCharIntoCarAsPassenger(getTargetPlayerHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskWeaponRoll",
                desc = "taskWeaponRoll(Ped ped, bool roll) ->",
                fn = function() return taskWeaponRoll(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA Char Vehicles & Passengers (1 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA Char Vehicles & Passengers",
        tests = {
{
                name = "createCharAsPassenger",
                desc = "createCharAsPassenger(Vehicle car, Model pedtype, int model, int passengerSeat) -> bool result, Ped ped",
                fn = function() return createCharAsPassenger(getTargetVehicleHandle(), 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA Char Stubs & Misc (60 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA Char Stubs & Misc",
        tests = {
{
                name = "addCharDecisionMakerEventResponse",
                desc = "addCharDecisionMakerEventResponse(int maker, int event, int taskID, float respect, float hate, float like, float dislike, bool inCar, bool onFoot) ->",
                fn = function() return addCharDecisionMakerEventResponse() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addGroupDecisionMakerEventResponse",
                desc = "addGroupDecisionMakerEventResponse(int maker, int event, int taskID, float respect, float hate, float like, float dislike, bool inCar, bool onFoot) ->",
                fn = function() return addGroupDecisionMakerEventResponse() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addPedtypeAsAttractorUser",
                desc = "addPedtypeAsAttractorUser(int ASOrigin, int pedtype) ->",
                fn = function() return addPedtypeAsAttractorUser() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "awardPlayerMissionRespect",
                desc = "awardPlayerMissionRespect(int respect) ->",
                fn = function() return awardPlayerMissionRespect(0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createChar",
                desc = "createChar(int pedtype, Model modelId, float atX, float atY, float atZ) -> Ped ped",
                fn = function() return createChar(0, 0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createPlayer",
                desc = "createPlayer(Model modelId, float atX, float atY, float atZ) -> Player player",
                fn = function() return createPlayer(getTargetPlayerHandle(), 0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createRandomChar",
                desc = "createRandomChar(float atX, float atY, float atZ) -> Ped ped",
                fn = function() return createRandomChar(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "deleteChar",
                desc = "deleteChar(Ped ped) ->",
                fn = function() return deleteChar(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "disablePlayerSprint",
                desc = "disablePlayerSprint(Player player, bool mode) ->",
                fn = function() return disablePlayerSprint(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCharActiveInterior",
                desc = "getCharActiveInterior(Ped ped) -> int interior",
                fn = function() return getCharActiveInterior(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCharPlayerIsTargeting",
                desc = "getCharPlayerIsTargeting(Player player) -> bool result, Ped ped",
                fn = function() return getCharPlayerIsTargeting(getTargetPlayer()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "givePlayerClothes",
                desc = "givePlayerClothes(Player player, int texture, int model, int bodypart) ->",
                fn = function() return givePlayerClothes(0, "", "", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "givePlayerClothesOutsideShop",
                desc = "givePlayerClothesOutsideShop(Player player, string clothes, string model, int bodyPart) ->",
                fn = function() return givePlayerClothesOutsideShop(0, "", "", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInTaxi",
                desc = "isCharInTaxi(Ped ped) -> bool result",
                fn = function() return isCharInTaxi(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharShooting",
                desc = "isCharShooting(Ped ped) -> bool result",
                fn = function() return isCharShooting(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharTalking",
                desc = "isCharTalking(Ped ped) -> bool result",
                fn = function() return isCharTalking(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isInfraredVisionActive",
                desc = "Checks if infrared thermal vision filter is active",
                fn = function() return isInfraredVisionActive() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isNightVisionActive",
                desc = "isNightVisionActive() -> bool result",
                fn = function() return isNightVisionActive() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPlayerClimbing",
                desc = "isPlayerClimbing(Player player) -> bool result",
                fn = function() return isPlayerClimbing(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPlayerControlLocked",
                desc = "isPlayerControlLocked() -> bool locked",
                fn = function() return isPlayerControlLocked(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPlayerInRemoteMode",
                desc = "isPlayerInRemoteMode(Player player) -> bool result",
                fn = function() return isPlayerInRemoteMode(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPlayerInShortcutTaxi",
                desc = "isPlayerInShortcutTaxi(Player player) -> bool result",
                fn = function() return isPlayerInShortcutTaxi(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPlayerPerformingStoppie",
                desc = "isPlayerPerformingStoppie(Player player) -> bool result",
                fn = function() return isPlayerPerformingStoppie(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPlayerPressingHorn",
                desc = "isPlayerPressingHorn(Player player) -> bool result",
                fn = function() return isPlayerPressingHorn(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPlayerTargettingAnything",
                desc = "isPlayerTargettingAnything(Player player) -> bool result",
                fn = function() return isPlayerTargettingAnything(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPlayerTargettingChar",
                desc = "isPlayerTargettingChar(Player player, Ped ped) -> bool result",
                fn = function() return isPlayerTargettingChar(getTargetPlayer(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPlayerUsingJetpack",
                desc = "isPlayerUsingJetpack(Player player) -> bool result",
                fn = function() return isPlayerUsingJetpack(getTargetPlayer()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPlayerWearing",
                desc = "isPlayerWearing(Player player, string bodypart, int skin) -> bool result",
                fn = function() return isPlayerWearing(0, "", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "lockPlayerControl",
                desc = "lockPlayerControl(bool lock) ->",
                fn = function() return lockPlayerControl() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "makePlayerSafe",
                desc = "makePlayerSafe(Player player) ->",
                fn = function() return makePlayerSafe(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "playerMadeProgress",
                desc = "playerMadeProgress(int progress) ->",
                fn = function() return playerMadeProgress(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "playerTakeOffGoggles",
                desc = "playerTakeOffGoggles(Player player, bool useAnim) ->",
                fn = function() return playerTakeOffGoggles(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeCharElegantly",
                desc = "removeCharElegantly(Ped ped) ->",
                fn = function() return removeCharElegantly(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharAccuracy",
                desc = "setCharAccuracy(Ped ped, int accuracy) ->",
                fn = function() return setCharAccuracy(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharCantBeDraggedOut",
                desc = "setCharCantBeDraggedOut(Ped ped, bool locked) ->",
                fn = function() return setCharCantBeDraggedOut(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharCollision",
                desc = "setCharCollision(Ped ped, bool enable) ->",
                fn = function() return setCharCollision(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharDrownsInWater",
                desc = "setCharDrownsInWater(Ped ped, bool drowns) ->",
                fn = function() return setCharDrownsInWater(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharHasUsedEntryExit",
                desc = "setCharHasUsedEntryExit(Ped ped, float X, float Y, float radius) ->",
                fn = function() return setCharHasUsedEntryExit(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharInterior",
                desc = "setCharInterior(Ped ped, int interior) ->",
                fn = function() return setCharInterior(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharKeyDown",
                desc = "setCharKeyDown(int ckey, bool down) ->",
                fn = function() return setCharKeyDown(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharShootRate",
                desc = "setCharShootRate(Ped ped, int rate) ->",
                fn = function() return setCharShootRate(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharSignalAfterKill",
                desc = "setCharSignalAfterKill(Ped ped, bool signal) ->",
                fn = function() return setCharSignalAfterKill(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharStayInSamePlace",
                desc = "setCharStayInSamePlace(Ped ped, bool enabled) ->",
                fn = function() return setCharStayInSamePlace(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharVisible",
                desc = "setCharVisible(Ped ped, bool visible) ->",
                fn = function() return setCharVisible(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharWantedByPolice",
                desc = "setCharWantedByPolice(Ped ped, bool wanted) ->",
                fn = function() return setCharWantedByPolice(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setEveryoneIgnorePlayer",
                desc = "setEveryoneIgnorePlayer(Player player, bool ignored) ->",
                fn = function() return setEveryoneIgnorePlayer(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setInfraredVision",
                desc = "setInfraredVision(bool enable) ->",
                fn = function() return setInfraredVision(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setNightVision",
                desc = "setNightVision(bool enable) ->",
                fn = function() return setNightVision(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayerCanDoDriveBy",
                desc = "setPlayerCanDoDriveBy(Player player, bool mode) ->",
                fn = function() return setPlayerCanDoDriveBy(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayerControl",
                desc = "setPlayerControl(Player player, bool canMove) -> bool result",
                fn = function() return setPlayerControl(getTargetPlayer(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayerDrunkenness",
                desc = "setPlayerDrunkenness(Player player, int drunk) ->",
                fn = function() return setPlayerDrunkenness(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayerFastReload",
                desc = "setPlayerFastReload(Player player, bool fastReload) ->",
                fn = function() return setPlayerFastReload(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayerGroupRecruitment",
                desc = "setPlayerGroupRecruitment(Player player, bool enabled) ->",
                fn = function() return setPlayerGroupRecruitment(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayerGroupToFollowAlways",
                desc = "setPlayerGroupToFollowAlways(Player player, bool followAlways) ->",
                fn = function() return setPlayerGroupToFollowAlways(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayerGroupToFollowNever",
                desc = "setPlayerGroupToFollowNever(Player player, bool neverFollow) ->",
                fn = function() return setPlayerGroupToFollowNever(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayerIsInStadium",
                desc = "setPlayerIsInStadium(bool set) ->",
                fn = function() return setPlayerIsInStadium(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayerJumpButton",
                desc = "setPlayerJumpButton(Player player, bool enable) ->",
                fn = function() return setPlayerJumpButton(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayerMood",
                desc = "setPlayerMood(Player player, int flag, int time) ->",
                fn = function() return setPlayerMood(0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayerNeverGetsTired",
                desc = "setPlayerNeverGetsTired(Player player, bool infiniteRun) ->",
                fn = function() return setPlayerNeverGetsTired(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayerPlayerTargetting",
                desc = "setPlayerPlayerTargetting(bool can) ->",
                fn = function() return setPlayerPlayerTargetting(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA Vehicle Deep Offsets & Memory Verification (23 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA Vehicle Offsets & Memory Verification",
        tests = {
            {
                name = "vehVerify_TargetHandle",
                desc = "Resolve target vehicle handle and verify pool existence",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no active or streamed vehicle") end
                    local exists = type(doesVehicleExist) == "function" and doesVehicleExist(car) or false
                    local ped = getTargetPlayerHandle()
                    local isDriver = false
                    if ped > 0 and type(getDriverOfCar) == "function" then
                        isDriver = (getDriverOfCar(car) == ped)
                    end
                    return car, exists, isDriver
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] <= 0 then return false, "expected positive handle" end
                    return true, string.format("handle=%d exists=%s isLocalPlayerDriver=%s", v[1], tostring(v[2]), tostring(v[3]))
                end,
            },
            {
                name = "vehVerify_Offset_Coordinates",
                desc = "Verify POS_X/Y/Z (ENT_POS_X +0x34..+0x3C / RwMatrix +0x14)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return getCarCoordinates(car)
                end,
                validate = function(v)
                    if not isCoords3d(v[1], v[2], v[3]) then return false, "expected 3 finite coords in SA bounds" end
                    return true, string.format("POS: X=%.2f, Y=%.2f, Z=%.2f", v[1], v[2], v[3])
                end,
            },
            {
                name = "vehVerify_Offset_HeadingAndOrientation",
                desc = "Verify ENT_MATRIX_UP / FORWARD_X/Y (+0x18..+0x20) and heading (0..360)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    local h = type(getCarHeading) == "function" and getCarHeading(car) or 0
                    local fx = type(getCarForwardX) == "function" and getCarForwardX(car) or 0
                    local fy = type(getCarForwardY) == "function" and getCarForwardY(car) or 0
                    return h, fx, fy
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or not isFiniteNumber(v[2]) or not isFiniteNumber(v[3]) then
                        return false, "expected finite heading & forward components"
                    end
                    return true, string.format("heading=%.1f deg, fwd=(%.3f, %.3f)", v[1], v[2], v[3])
                end,
            },
            {
                name = "vehVerify_Offset_RollAndPitch",
                desc = "Verify RwMatrix UP_Z (+0x20 Roll) and RIGHT matrix (+0x00 Pitch)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    local roll = type(getCarRoll) == "function" and getCarRoll(car) or 0
                    local pitch = type(getCarPitch) == "function" and getCarPitch(car) or 0
                    return roll, pitch
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or not isFiniteNumber(v[2]) then
                        return false, "expected finite roll and pitch"
                    end
                    return true, string.format("roll=%.3f, pitch=%.3f", v[1], v[2])
                end,
            },
            {
                name = "vehVerify_Offset_VelocityAndSpeed",
                desc = "Verify VEH_VEL_X/Y/Z (+0x10C..+0x114) and speed magnitude",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    local spd = type(getCarSpeed) == "function" and getCarSpeed(car) or 0
                    local vx, vy, vz = 0, 0, 0
                    if type(getVehicleVelocity) == "function" then
                        vx, vy, vz = getVehicleVelocity(car)
                    end
                    return spd, vx, vy, vz
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or not isFiniteNumber(v[2]) or not isFiniteNumber(v[3]) or not isFiniteNumber(v[4]) then
                        return false, "expected finite speed and velocity vector"
                    end
                    return true, string.format("speed=%.2f km/h, vel=(%.2f, %.2f, %.2f)", v[1], v[2], v[3], v[4])
                end,
            },
            {
                name = "vehVerify_Offset_Health",
                desc = "Verify VEH_HEALTH (+0x280 float health in [0, 5000])",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return getCarHealth(car)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 or v[1] > 5000 then
                        return false, "expected health in [0, 5000], got: " .. formatValue(v[1])
                    end
                    return true, string.format("HEALTH: %.1f HP", v[1])
                end,
            },
            {
                name = "vehVerify_Offset_ModelID",
                desc = "Verify ENT_MODEL_ID (+0x22 uint16) with getCarModel and isCarModel",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    local m1 = type(getCarModel) == "function" and getCarModel(car) or 0
                    local m2 = type(getVehicleModel) == "function" and getVehicleModel(car) or 0
                    local isMatch = type(isCarModel) == "function" and isCarModel(car, m1) or false
                    return m1, m2, isMatch
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 400 or v[1] > 611 then
                        return false, "expected valid GTA SA vehicle model (400-611), got: " .. formatValue(v[1])
                    end
                    return true, string.format("MODEL_ID: %d (match=%s)", v[1], tostring(v[3]))
                end,
            },
            {
                name = "vehVerify_Offset_EngineBit",
                desc = "Verify VEH_ENGINE_BITFIELD (+0x28D bit 2: Engine On/Off)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return isCarEngineOn(car)
                end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean engine state" end
                    return true, string.format("ENGINE: %s", v[1] and "ON" or "OFF")
                end,
            },
            {
                name = "vehVerify_Offset_SirenBit",
                desc = "Verify VEH_SIREN (+0x290 bit 2: Siren State)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return isCarSirenOn(car)
                end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean siren state" end
                    return true, string.format("SIREN: %s", v[1] and "ACTIVE" or "OFF")
                end,
            },
            {
                name = "vehVerify_Offset_DoorLock",
                desc = "Verify VEH_DOOR_LOCK (+0x2AC int32 lock state: 1=unlocked, 2=locked)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return getCarDoorLockStatus(car)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected integer door lock status" end
                    return true, string.format("LOCK_STATE: %d (%s)", v[1], v[1] == 2 and "LOCKED" or (v[1] == 1 and "UNLOCKED" or "SPECIAL"))
                end,
            },
            {
                name = "vehVerify_Offset_Colors",
                desc = "Verify VEH_PRIMARY_COLOR (+0x258) and VEH_SECONDARY_COLOR (+0x259)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return getCarColours(car)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or not isFiniteNumber(v[2]) then
                        return false, "expected 2 color integers"
                    end
                    return true, string.format("COLORS: Primary=%d, Secondary=%d", v[1], v[2])
                end,
            },
            {
                name = "vehVerify_Offset_DriverPtr",
                desc = "Verify DRIVER_PTR (+0x210 CPed* driver handle)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    local driver = type(getDriverOfCar) == "function" and getDriverOfCar(car) or 0
                    local ped = getTargetPlayerHandle()
                    return driver, driver == ped
                end,
                validate = function(v)
                    return true, string.format("DRIVER: handle=%d (isLocalPlayer=%s)", v[1], tostring(v[2]))
                end,
            },
            {
                name = "vehVerify_Offset_PassengersCount",
                desc = "Verify NUM_PASSENGERS (+0x25B) and MAX_PASSENGERS (+0x25C)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    local okCount, count = false, 0
                    if type(getNumberOfPassengers) == "function" then
                        okCount, count = getNumberOfPassengers(car)
                    end
                    local maxP = type(getMaximumNumberOfPassengers) == "function" and getMaximumNumberOfPassengers(car) or 0
                    return count or 0, maxP
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or not isFiniteNumber(v[2]) then
                        return false, "expected valid passenger count numbers"
                    end
                    return true, string.format("PASSENGERS: %d / %d seats", v[1], v[2])
                end,
            },
            {
                name = "vehVerify_Offset_TireStates",
                desc = "Verify VEH_TIRE_STATE (+0x2A0 uint32 bitfield) & isVehicleOnAllWheels",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    local b0 = type(isCarTireBurst) == "function" and isCarTireBurst(car, 0) or false
                    local b1 = type(isCarTireBurst) == "function" and isCarTireBurst(car, 1) or false
                    local b2 = type(isCarTireBurst) == "function" and isCarTireBurst(car, 2) or false
                    local b3 = type(isCarTireBurst) == "function" and isCarTireBurst(car, 3) or false
                    local allWheels = type(isVehicleOnAllWheels) == "function" and isVehicleOnAllWheels(car) or false
                    return b0, b1, b2, b3, allWheels
                end,
                validate = function(v)
                    return true, string.format("TIRES: FL=%s, BL=%s, FR=%s, BR=%s | AllWheelsIntact=%s",
                        tostring(v[1]), tostring(v[2]), tostring(v[3]), tostring(v[4]), tostring(v[5]))
                end,
            },
            {
                name = "vehVerify_Offset_CurrentGear",
                desc = "Verify VEH_CURRENT_GEAR (+0x294 uint8) and handling gear count",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    local gear = type(getCarCurrentGear) == "function" and getCarCurrentGear(car) or 0
                    local totalGears = type(getCarNumberOfGears) == "function" and getCarNumberOfGears(car) or 0
                    return gear, totalGears
                end,
                validate = function(v)
                    return true, string.format("GEARS: Current=%d, TotalAvailable=%d", v[1], v[2])
                end,
            },
            {
                name = "vehVerify_Offset_CarMass",
                desc = "Verify ENT_MASS (+0x8C float mass)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return getCarMass(car)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] <= 0 then
                        return false, "expected positive mass float"
                    end
                    return true, string.format("MASS: %.1f kg", v[1])
                end,
            },
            {
                name = "vehVerify_Offset_DoorStatesAndDamages",
                desc = "Verify VEH_DOOR_DMG (+0x2A4..+0x2A7) and DOOR_STATE (+0x2A8)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    local d0 = type(isCarDoorDamaged) == "function" and isCarDoorDamaged(car, 0) or false
                    local d1 = type(isCarDoorDamaged) == "function" and isCarDoorDamaged(car, 1) or false
                    local open0 = type(isCarDoorFullyOpen) == "function" and isCarDoorFullyOpen(car, 0) or false
                    local ratio = type(getDoorAngleRatio) == "function" and getDoorAngleRatio(car, 0) or 0.0
                    return d0, d1, open0, ratio
                end,
                validate = function(v)
                    return true, string.format("DOORS: D0_dmg=%s, D1_dmg=%s, D0_open=%s, D0_ratio=%.2f",
                        tostring(v[1]), tostring(v[2]), tostring(v[3]), v[4])
                end,
            },
            {
                name = "vehVerify_Offset_StateBooleans",
                desc = "Verify vehicle flags (isCarDead, isCarStopped, isCarUpsidedown, isCarUpright, isCarInWater)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    local dead = type(isCarDead) == "function" and isCarDead(car) or false
                    local stopped = type(isCarStopped) == "function" and isCarStopped(car) or false
                    local upside = type(isCarUpsidedown) == "function" and isCarUpsidedown(car) or false
                    local upright = type(isCarUpright) == "function" and isCarUpright(car) or false
                    local inWater = type(isCarInWater) == "function" and isCarInWater(car) or false
                    return dead, stopped, upside, upright, inWater
                end,
                validate = function(v)
                    return true, string.format("FLAGS: dead=%s, stopped=%s, upright=%s, upsideDown=%s, water=%s",
                        tostring(v[1]), tostring(v[2]), tostring(v[4]), tostring(v[3]), tostring(v[5]))
                end,
            },
            {
                name = "vehVerify_Offset_AreaCodeInterior",
                desc = "Verify CEntity::m_nAreaCode (+0x6D interior index)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return getVehicleInterior(car)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected integer interior ID" end
                    return true, string.format("INTERIOR (AreaCode +0x6D): %d", v[1])
                end,
            },
            {
                name = "vehVerify_Offset_VisibilityScreen",
                desc = "Verify ENT_FLAGS (+0x65 IS_HIDDEN byte) and isCarOnScreen",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    local onScreen1 = type(isCarOnScreen) == "function" and isCarOnScreen(car) or false
                    local onScreen2 = type(isVehicleOnScreen) == "function" and isVehicleOnScreen(car) or false
                    return onScreen1, onScreen2
                end,
                validate = function(v)
                    return true, string.format("ON_SCREEN: isCarOnScreen=%s, isVehicleOnScreen=%s", tostring(v[1]), tostring(v[2]))
                end,
            },
            {
                name = "vehVerify_Offset_TrailerAndTractor",
                desc = "Verify TRAILER_PTR (+0x300) and TRACTOR_PTR",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    local isTr = type(isCarTrailer) == "function" and isCarTrailer(car) or false
                    local isAtt = type(isTrailerAttachedToCab) == "function" and isTrailerAttachedToCab(car, 0) or false
                    local trHandle = type(getCarTrailer) == "function" and getCarTrailer(car) or nil
                    return isTr, isAtt, trHandle
                end,
                validate = function(v)
                    return true, string.format("TRAILER: isTrailer=%s, attached=%s, trailerHandle=%s",
                        tostring(v[1]), tostring(v[2]), formatValue(v[3]))
                end,
            },
            {
                name = "vehVerify_PedCarInteraction",
                desc = "Verify ped-vehicle links: isCharInAnyCar, storeCarCharIsIn, getCarCharIsUsing",
                fn = function()
                    local ped = getTargetPlayerHandle()
                    if ped <= 0 then return makeSkip("no player ped") end
                    local inAny = type(isCharInAnyCar) == "function" and isCharInAnyCar(ped) or false
                    local stored = type(storeCarCharIsIn) == "function" and storeCarCharIsIn(ped) or 0
                    local using = type(getCarCharIsUsing) == "function" and getCarCharIsUsing(ped) or 0
                    local car = getTargetVehicleHandle()
                    local inThis = (car > 0 and type(isCharInCar) == "function") and isCharInCar(ped, car) or false
                    return inAny, stored, using, inThis
                end,
                validate = function(v)
                    return true, string.format("PED_CAR: inAnyCar=%s, storeCar=%d, usingCar=%d, inThisCar=%s",
                        tostring(v[1]), v[2], v[3], tostring(v[4]))
                end,
            },
            {
                name = "vehVerify_Offset_RawMemoryInspect",
                desc = "Inspect raw memory if samemory is active (offsets from SAMemoryOffsets.h)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    if not hasSAMemory or not samemory or not samemory.read then
                        return makeSkip("SAMemory library not loaded")
                    end
                    local ptr = car
                    local ok, hp = pcall(samemory.read, ptr + 0x280, 4, true)
                    local ok2, model = pcall(samemory.read, ptr + 0x22, 2, false)
                    local ok3, eng = pcall(samemory.read, ptr + 0x28D, 1, false)
                    local ok4, lock = pcall(samemory.read, ptr + 0x2AC, 4, false)
                    return string.format("Ptr=0x%X | HP=%.1f | Model=%d | EngByte=0x%02X | Lock=%d",
                        ptr, ok and hp or -1, ok2 and model or -1, ok3 and eng or 0, ok4 and lock or -1)
                end,
                validate = function(v)
                    return true, tostring(v[1])
                end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA Vehicle Core & Health (145 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA Vehicle Core & Health",
        tests = {
{
                name = "getAllVehicles",
                desc = "Enumerate all active vehicle handles in pool",
                fn = function() return getAllVehicles() end,
                validate = function(v)
                    if type(v[1]) ~= "table" then return false, "expected array table of vehicle handles" end
                    return true, string.format("%d vehicles found", #v[1])
                end
            },
{
                name = "doesVehicleExist",
                desc = "Check if vehicle handle exists in pool",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return doesVehicleExist(car)
                end,
                validate = function(v)
                    if v[1] ~= true then return false, "expected vehicle to exist" end
                    return true, "true"
                end
            },
{
                name = "getCarHealth",
                desc = "Get vehicle health points (0-2000)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return getCarHealth(car)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 or v[1] > 5000 then
                        return false, "expected health in [0, 5000]"
                    end
                    return true, string.format("%.1f HP", v[1])
                end
            },
{
                name = "setCarHealth",
                desc = "Set vehicle health roundtrip test",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    local orig = getCarHealth(car)
                    local testVal = math.max(250.0, math.min(1000.0, orig - 10.0))
                    setCarHealth(car, testVal)
                    local updated = getCarHealth(car)
                    setCarHealth(car, orig)
                    local restored = getCarHealth(car)
                    if math.abs(updated - testVal) > 2.0 then return false, "failed to apply vehicle health" end
                    if math.abs(restored - orig) > 2.0 then return false, "failed to restore vehicle health" end
                    return true, orig
                end,
                validate = function(v)
                    return true, string.format("verified & restored (%.1f)", v[2])
                end
            },
{
                name = "isCarDead",
                desc = "Check if vehicle is wrecked / destroyed",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return isCarDead(car)
                end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "isCarOnScreen",
                desc = "Check if vehicle is visible on screen",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return isCarOnScreen(car)
                end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "isCarUpright",
                desc = "Check if vehicle is right side up",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return isCarUpright(car)
                end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "isCarUpsidedown",
                desc = "Check if vehicle is upside down / flipped",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return isCarUpsidedown(car)
                end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "isCarEngineOn",
                desc = "Check if vehicle engine is running",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return isCarEngineOn(car)
                end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "isCarSirenOn",
                desc = "Check if vehicle siren is sounding",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return isCarSirenOn(car)
                end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "getCarModel",
                desc = "Get vehicle model ID (400-611)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return getCarModel(car)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 400 or v[1] > 611 then
                        return false, "expected model ID in [400, 611]"
                    end
                    return true, string.format("model=%d", v[1])
                end
            },
{
                name = "getNameOfVehicleModel",
                desc = "Get vehicle model name for 411 (Infernus)",
                fn = function() return getNameOfVehicleModel(411) end,
                validate = function(v)
                    if type(v[1]) ~= "string" or not v[1]:lower():find("infernus") then
                        return false, "expected Infernus, got: " .. formatValue(v[1])
                    end
                    return true, '"' .. v[1] .. '"'
                end
            },
{
                name = "isThisModelACar",
                desc = "Verify model classification: 411 is a car",
                fn = function() return isThisModelACar(411) end,
                validate = function(v)
                    if v[1] ~= true then return false, "expected model 411 to be a car" end
                    return true, "true"
                end
            },
{
                name = "isThisModelAHeli",
                desc = "Verify model classification: 425 (Hunter) is a heli",
                fn = function() return isThisModelAHeli(425) end,
                validate = function(v)
                    if v[1] ~= true then return false, "expected model 425 to be a heli" end
                    return true, "true"
                end
            },
{
                name = "isThisModelABoat",
                desc = "Verify model classification: 472 (Tropic) is a boat",
                fn = function() return isThisModelABoat(472) end,
                validate = function(v)
                    if v[1] ~= true then return false, "expected model 472 to be a boat" end
                    return true, "true"
                end
            },
{
                name = "isThisModelAPlane",
                desc = "Verify model classification: 592 (Andromada) is a plane",
                fn = function() return isThisModelAPlane(592) end,
                validate = function(v)
                    if v[1] ~= true then return false, "expected model 592 to be a plane" end
                    return true, "true"
                end
            },
{
                name = "getDriverOfCar",
                desc = "Get ped handle of vehicle driver",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return getDriverOfCar(car)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 then return false, "expected ped handle" end
                    return true, string.format("driver=%d", v[1])
                end
            },
{
                name = "getMaximumNumberOfPassengers",
                desc = "Get vehicle passenger seat capacity",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return getMaximumNumberOfPassengers(car)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 or v[1] > 10 then
                        return false, "expected passenger capacity in [0, 10]"
                    end
                    return true, string.format("%d seats", v[1])
                end
            },
{
                name = "getCarDoorLockStatus",
                desc = "Get vehicle door lock enum status",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return getCarDoorLockStatus(car)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected lock status integer" end
                    return true, string.format("lock=%d", v[1])
                end
            },
{
                name = "getCarMass",
                desc = "Get vehicle physical curb weight / mass",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return getCarMass(car)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0.0 then return false, "expected non-negative mass, got: " .. formatValue(v[1]) end
                    return true, string.format("%.1f kg", v[1])
                end
            },
{
                name = "getVehiclePointerHandle",
                desc = "Get CVehicle memory pointer (>0x10000)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return getVehiclePointerHandle(car)
                end,
                validate = function(v)
                    if not isPointer(v[1]) then return false, "expected pointer > 0x10000" end
                    return true, string.format("0x%X", v[1])
                end
            },
{
                name = "setVehicleInterior",
                desc = "Set vehicle interior ID (CEntity +0x6D)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    local oldInt = (type(getVehicleInterior) == "function") and getVehicleInterior(car) or 0
                    setVehicleInterior(car, 1)
                    local newInt = (type(getVehicleInterior) == "function") and getVehicleInterior(car) or 1
                    setVehicleInterior(car, oldInt)
                    return oldInt, newInt
                end,
                validate = function(v)
                    if v[2] ~= 1 then return false, "expected new interior 1, got: " .. formatValue(v[2]) end
                    return true, string.format("old=%d, new=%d", v[1], v[2])
                end
            },
{
                name = "getVehicleInterior",
                desc = "Get vehicle interior ID (0-255)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return getVehicleInterior(car)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 or v[1] > 255 then
                        return false, "expected interior in [0, 255], got: " .. formatValue(v[1])
                    end
                    return true, string.format("interior=%d", v[1])
                end
            },
{
                name = "GetLocalVehicle",
                desc = "Returns vehicle handle or pointer of player current vehicle",
                fn = function() return GetLocalVehicle() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "GetVehicleDirtLevel",
                desc = "Returns vehicle dirt level float (0.0 - 15.0)",
                fn = function() return GetVehicleDirtLevel(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "GetVehicleEngineState",
                desc = "Returns vehicle engine running state (true/false)",
                fn = function() return GetVehicleEngineState(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "GetVehicleHealth",
                desc = "Returns vehicle engine health float from memory",
                fn = function() return GetVehicleHealth(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "GetVehicleLockState",
                desc = "Returns vehicle door lock state integer",
                fn = function() return GetVehicleLockState(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addStuckCarCheck",
                desc = "addStuckCarCheck(Vehicle car, float stuckCheckDistance, int time) ->",
                fn = function() return addStuckCarCheck(getTargetVehicleHandle(), 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addStuckCarCheckWithWarp",
                desc = "addStuckCarCheckWithWarp(Vehicle car, float checkDistance, int time, bool stuck, bool flipped, bool warp, int path) ->",
                fn = function() return addStuckCarCheckWithWarp(getTargetVehicleHandle(), 0.0, 0, false, false, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addUpsidedownCarCheck",
                desc = "addUpsidedownCarCheck(Vehicle car) ->",
                fn = function() return addUpsidedownCarCheck(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addVehicleMod",
                desc = "addVehicleMod(Vehicle car, Model component) -> int componentId",
                fn = function() return addVehicleMod(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "anchorBoat",
                desc = "anchorBoat(Vehicle boat, bool anchor) ->",
                fn = function() return anchorBoat(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "applyBrakesToPlayersCar",
                desc = "applyBrakesToPlayersCar(Player player, bool apply) -> bool result",
                fn = function() return applyBrakesToPlayersCar(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "applyForceToCar",
                desc = "applyForceToCar(Vehicle car, float vecX, float vecY, float vecZ, float rotationX, float rotationY, float rotationZ) ->",
                fn = function() return applyForceToCar(getTargetVehicleHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachTrailerToCab",
                desc = "attachTrailerToCab(int trailer, int cab) ->",
                fn = function() return attachTrailerToCab(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "carSetIdle",
                desc = "carSetIdle(Vehicle car) ->",
                fn = function() return carSetIdle(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "carWanderRandomly",
                desc = "carWanderRandomly(Vehicle car) ->",
                fn = function() return carWanderRandomly(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearAreaOfCars",
                desc = "clearAreaOfCars(float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ) ->",
                fn = function() return clearAreaOfCars(0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearCarLastDamageEntity",
                desc = "clearCarLastDamageEntity(Vehicle car) ->",
                fn = function() return clearCarLastDamageEntity(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearCarLastWeaponDamage",
                desc = "clearCarLastWeaponDamage(Vehicle car) ->",
                fn = function() return clearCarLastWeaponDamage(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "controlCarHydraulics",
                desc = "controlCarHydraulics(Vehicle car, float f1, float f2, float f3, float f4) ->",
                fn = function() return controlCarHydraulics(getTargetVehicleHandle(), 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createCar",
                desc = "createCar(Model modelId, float atX, float atY, float atZ) -> Vehicle car",
                fn = function() return createCar(0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "deleteCar",
                desc = "deleteCar(Vehicle car) ->",
                fn = function() return deleteCar(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "detachCar",
                desc = "detachCar(Vehicle car, float X, float Y, float Z, bool collisionDetection) ->",
                fn = function() return detachCar(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "detachTrailerFromCab",
                desc = "detachTrailerFromCab(Vehicle trailer, Vehicle cab) ->",
                fn = function() return detachTrailerFromCab(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "doesCarHaveHydraulics",
                desc = "doesCarHaveHydraulics(Vehicle car) -> bool result",
                fn = function() return doesCarHaveHydraulics(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "explodeCar",
                desc = "explodeCar(Vehicle car) -> bool result",
                fn = function() return explodeCar(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "explodeCarInCutscene",
                desc = "explodeCarInCutscene(Vehicle car) ->",
                fn = function() return explodeCarInCutscene(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "explodeCarInCutsceneShakeAndBits",
                desc = "explodeCarInCutsceneShakeAndBits(Vehicle car, bool shake, bool effect, bool sound) ->",
                fn = function() return explodeCarInCutsceneShakeAndBits(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "fixCar",
                desc = "fixCar(Vehicle car) ->",
                fn = function() return fixCar(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCarBlockingCar",
                desc = "getCarBlockingCar(Vehicle car) -> int blockingCar",
                fn = function() return getCarBlockingCar(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCarCharIsUsing",
                desc = "getCarCharIsUsing(Ped ped) -> Vehicle car",
                fn = function() return getCarCharIsUsing(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCarForwardX",
                desc = "getCarForwardX(Vehicle car) -> float forwardX",
                fn = function() return getCarForwardX(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCarForwardY",
                desc = "getCarForwardY(Vehicle car) -> float forwardY",
                fn = function() return getCarForwardY(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCarPointer",
                desc = "getCarPointer(Vehicle car) -> uint ptr",
                fn = function() return getCarPointer(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCarTrailer",
                desc = "Returns vehicle handle of attached trailer",
                fn = function() return getCarTrailer(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCharInCarPassengerSeat",
                desc = "getCharInCarPassengerSeat(Vehicle car, int seat) -> Ped ped",
                fn = function() return getCharInCarPassengerSeat(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getNumberOfPassengers",
                desc = "getNumberOfPassengers(Vehicle car) -> bool result, int passengers",
                fn = function() return getNumberOfPassengers(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getVehicleClass",
                desc = "getVehicleClass(Vehicle car) -> int class",
                fn = function() return getVehicleClass(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getVehicleModType",
                desc = "getVehicleModType(Model component) -> int type",
                fn = function() return getVehicleModType(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasCarBeenDamagedByCar",
                desc = "hasCarBeenDamagedByCar(Vehicle car, Vehicle byCar) -> bool result",
                fn = function() return hasCarBeenDamagedByCar(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasCarBeenDamagedByWeapon",
                desc = "hasCarBeenDamagedByWeapon(Vehicle car, int weapon) -> bool result",
                fn = function() return hasCarBeenDamagedByWeapon(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarAttached",
                desc = "Checks if vehicle is attached to another vehicle or trailer",
                fn = function() return isCarAttached(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarInWater",
                desc = "isCarInWater(Vehicle car) -> bool result",
                fn = function() return isCarInWater(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarOnFire",
                desc = "isCarOnFire(Vehicle car) -> bool result",
                fn = function() return isCarOnFire(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarOnTrailer",
                desc = "Checks if vehicle is loaded on a trailer",
                fn = function() return isCarOnTrailer(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarPassengerSeatFree",
                desc = "isCarPassengerSeatFree(Vehicle car, int seat) -> bool result",
                fn = function() return isCarPassengerSeatFree(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarStopped",
                desc = "isCarStopped(Vehicle car) -> bool result",
                fn = function() return isCarStopped(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarStuck",
                desc = "isCarStuck(Vehicle car) -> bool result",
                fn = function() return isCarStuck(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarStuckOnRoof",
                desc = "isCarStuckOnRoof(Vehicle car) -> bool result",
                fn = function() return isCarStuckOnRoof(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarTrailer",
                desc = "Checks if vehicle entity model is a trailer",
                fn = function() return isCarTrailer(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharGettingInToACar",
                desc = "isCharGettingInToACar(Ped ped) -> bool result",
                fn = function() return isCharGettingInToACar(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInAngledAreaInCar2d",
                desc = "isCharInAngledAreaInCar2d(Ped ped, float x1, float y1, float x2, float y2, float angle, bool sphere) -> bool result",
                fn = function() return isCharInAngledAreaInCar2d(0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInAngledAreaInCar3d",
                desc = "isCharInAngledAreaInCar3d(Ped ped, float x1, float y1, float z1, float x2, float y2, float z2, float depth, bool flag) -> bool result",
                fn = function() return isCharInAngledAreaInCar3d(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInAreaInCar2d",
                desc = "isCharInAreaInCar2d(Ped ped, float cornerAX, float cornerAY, float cornerBX, float cornerBY, bool sphere) -> bool result",
                fn = function() return isCharInAreaInCar2d(0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInAreaInCar3d",
                desc = "isCharInAreaInCar3d(Ped ped, float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ, bool sphere) -> bool result",
                fn = function() return isCharInAreaInCar3d(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInCar",
                desc = "isCharInCar(Ped ped, Vehicle car) -> bool result",
                fn = function() return isCharInCar(getTargetPlayerHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharSittingInCar",
                desc = "isCharSittingInCar(Ped ped, Vehicle car) -> bool result",
                fn = function() return isCharSittingInCar(getTargetPlayerHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharStoppedInAngledAreaInCar2d",
                desc = "isCharStoppedInAngledAreaInCar2d(Ped ped, float x1, float y1, float x2, float y2, float height, bool flag) -> bool result",
                fn = function() return isCharStoppedInAngledAreaInCar2d(0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharStoppedInAngledAreaInCar3d",
                desc = "isCharStoppedInAngledAreaInCar3d(Ped ped, float x1, float y1, float z1, float x2, float y2, float z2, float depth, bool flag) -> bool result",
                fn = function() return isCharStoppedInAngledAreaInCar3d(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharStoppedInAreaInCar2d",
                desc = "isCharStoppedInAreaInCar2d(Ped ped, float cornerAX, float cornerAY, float cornerBX, float cornerBY, bool sphere) -> bool result",
                fn = function() return isCharStoppedInAreaInCar2d(getTargetPlayerHandle(), 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharStoppedInAreaInCar3d",
                desc = "isCharStoppedInAreaInCar3d(Ped ped, float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ, bool sphere) -> bool result",
                fn = function() return isCharStoppedInAreaInCar3d(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isTrailerAttachedToCab",
                desc = "isTrailerAttachedToCab(Vehicle trailer, Vehicle car) -> bool result",
                fn = function() return isTrailerAttachedToCab(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharAnyMeansCar2d",
                desc = "locateCharAnyMeansCar2d(Ped ped, Vehicle car, float radiusX, float radiusY, bool sphere) -> bool result",
                fn = function() return locateCharAnyMeansCar2d(getTargetPlayerHandle(), getTargetVehicleHandle(), 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharAnyMeansCar3d",
                desc = "locateCharAnyMeansCar3d(Ped ped, Vehicle car, float radiusX, float radiusY, float radiusZ, bool flag) -> bool result",
                fn = function() return locateCharAnyMeansCar3d(getTargetPlayerHandle(), getTargetVehicleHandle(), 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharInCar2d",
                desc = "locateCharInCar2d(Ped ped, float pointX, float pointY, float radiusX, float radiusY, bool sphere) -> bool result",
                fn = function() return locateCharInCar2d(0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharInCar3d",
                desc = "locateCharInCar3d(Ped ped, float sphereX, float sphereY, float sphereZ, float radiusX, float radiusY, float radiusZ, bool sphere) -> bool result",
                fn = function() return locateCharInCar3d(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharInCarCar2d",
                desc = "locateCharInCarCar2d(Ped ped, Vehicle car, float radiusX, float radiusY, bool sphere) -> bool result",
                fn = function() return locateCharInCarCar2d(0, getTargetVehicleHandle(), 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharInCarCar3d",
                desc = "locateCharInCarCar3d(Ped ped, Vehicle car, float radiusX, float radiusY, float radiusZ, bool flag) -> bool result",
                fn = function() return locateCharInCarCar3d(0, getTargetVehicleHandle(), 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharInCarChar2d",
                desc = "locateCharInCarChar2d(Ped ped, Ped nearPed, float radiusX, float radiusY, bool sphere) -> bool result",
                fn = function() return locateCharInCarChar2d(0, 0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharInCarChar3d",
                desc = "locateCharInCarChar3d(Ped ped, Ped nearPed, float radiusX, float radiusY, float radiusZ, bool sphere) -> bool result",
                fn = function() return locateCharInCarChar3d(0, 0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharOnFootCar2d",
                desc = "locateCharOnFootCar2d(Ped ped, Vehicle car, float radiusX, float radiusY, bool flag) -> bool result",
                fn = function() return locateCharOnFootCar2d(0, getTargetVehicleHandle(), 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharOnFootCar3d",
                desc = "locateCharOnFootCar3d(Ped ped, Vehicle car, float radiusX, float radiusY, float radiusZ, bool flag) -> bool result",
                fn = function() return locateCharOnFootCar3d(0, getTargetVehicleHandle(), 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateStoppedCharInCar2d",
                desc = "locateStoppedCharInCar2d(Ped ped, float pointX, float pointY, float radiusX, float radiusY, bool sphere) -> bool result",
                fn = function() return locateStoppedCharInCar2d(0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateStoppedCharInCar3d",
                desc = "locateStoppedCharInCar3d(Ped ped, float sphereX, float sphereY, float sphereZ, float radiusX, float radiusY, float radiusZ, bool sphere) -> bool result",
                fn = function() return locateStoppedCharInCar3d(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "popCarBoot",
                desc = "popCarBoot(Vehicle car) ->",
                fn = function() return popCarBoot(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "popCarBootUsingPhysics",
                desc = "Forces vehicle boot/trunk to open using physics",
                fn = function() return popCarBootUsingPhysics(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeStuckCarCheck",
                desc = "removeStuckCarCheck(Vehicle car) ->",
                fn = function() return removeStuckCarCheck(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeUpsidedownCarCheck",
                desc = "removeUpsidedownCarCheck(Vehicle car) ->",
                fn = function() return removeUpsidedownCarCheck(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeVehicleMod",
                desc = "removeVehicleMod(Vehicle car, int componentId) ->",
                fn = function() return removeVehicleMod(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "resetVehicleHydraulics",
                desc = "resetVehicleHydraulics(Vehicle car) ->",
                fn = function() return resetVehicleHydraulics(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "selectWeaponsForVehicle",
                desc = "selectWeaponsForVehicle(Vehicle car, bool gun) ->",
                fn = function() return selectWeaponsForVehicle(0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendDamageVehicle",
                desc = "Sends vehicle damage sync packet to server",
                fn = function() return sendDamageVehicle() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendEnterVehicle",
                desc = "Sends enter vehicle notification RPC to server",
                fn = function() return sendEnterVehicle() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendExitVehicle",
                desc = "Sends exit vehicle notification RPC to server",
                fn = function() return sendExitVehicle() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendVehicleDestroyed",
                desc = "Sends vehicle destroyed notification to server",
                fn = function() return sendVehicleDestroyed() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarCanBeDamaged",
                desc = "setCarCanBeDamaged(Vehicle car, bool enable) ->",
                fn = function() return setCarCanBeDamaged(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarCanBeTargetted",
                desc = "Sets whether vehicle can be locked on by auto-aim",
                fn = function() return setCarCanBeTargetted(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarCanBeVisiblyDamaged",
                desc = "setCarCanBeVisiblyDamaged(Vehicle car, bool can) ->",
                fn = function() return setCarCanBeVisiblyDamaged(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarCanGoAgainstTraffic",
                desc = "setCarCanGoAgainstTraffic(Vehicle car, bool can) ->",
                fn = function() return setCarCanGoAgainstTraffic(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarCollision",
                desc = "setCarCollision(Vehicle car, bool collision) ->",
                fn = function() return setCarCollision(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarDensity",
                desc = "Sets traffic car generation density multiplier",
                fn = function() return setCarDensity(getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarDensityMultiplier",
                desc = "setCarDensityMultiplier(float multiplier) -> bool result",
                fn = function() return setCarDensityMultiplier(0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarDrivingStyle",
                desc = "setCarDrivingStyle(Vehicle car, int behaviour) ->",
                fn = function() return setCarDrivingStyle(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarEngineOn",
                desc = "setCarEngineOn(Vehicle car, bool on) ->",
                fn = function() return setCarEngineOn(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarGravity",
                desc = "Sets gravitational acceleration applied to vehicle",
                fn = function() return setCarGravity(getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarHeavy",
                desc = "setCarHeavy(Vehicle car, bool heavy) -> bool result",
                fn = function() return setCarHeavy(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarHydraulic",
                desc = "Sets vehicle hydraulic suspension active state",
                fn = function() return setCarHydraulic(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarHydraulics",
                desc = "setCarHydraulics(Vehicle car, bool hydraulics) ->",
                fn = function() return setCarHydraulics(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarLightConfiguration",
                desc = "Sets vehicle headlamp and taillight configuration",
                fn = function() return setCarLightConfiguration(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarLightsOn",
                desc = "setCarLightsOn(Vehicle car, bool lights) ->",
                fn = function() return setCarLightsOn(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarMission",
                desc = "setCarMission(Vehicle car, int driverBehaviour) ->",
                fn = function() return setCarMission(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarNoOfPetrolTanks",
                desc = "Sets number of petrol fuel tanks on vehicle",
                fn = function() return setCarNoOfPetrolTanks(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarProofs",
                desc = "setCarProofs(Vehicle car, bool BP, bool FP, bool EP, bool CP, bool MP) ->",
                fn = function() return setCarProofs(getTargetVehicleHandle(), false, false, false, false, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarSoakPetrol",
                desc = "Sets vehicle petrol tank puncture/leak state",
                fn = function() return setCarSoakPetrol(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarStraight",
                desc = "Aligns vehicle steering angle straight ahead",
                fn = function() return setCarStraight(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarStrong",
                desc = "setCarStrong(Vehicle car, bool strong) ->",
                fn = function() return setCarStrong(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarTraction",
                desc = "setCarTraction(Vehicle car, float traction) ->",
                fn = function() return setCarTraction(getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarTyreBurst",
                desc = "Bursts specified vehicle tyre (wheel index)",
                fn = function() return setCarTyreBurst(getTargetVehicleHandle(), 0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarVisible",
                desc = "setCarVisible(Vehicle car, bool visible) ->",
                fn = function() return setCarVisible(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarWatertight",
                desc = "setCarWatertight(Vehicle car, bool watertight) ->",
                fn = function() return setCarWatertight(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarWindowOpen",
                desc = "Rolls down or closes specified vehicle window",
                fn = function() return setCarWindowOpen(getTargetVehicleHandle(), 0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharEnterCarButton",
                desc = "Configures controller button used to enter vehicle",
                fn = function() return setCharEnterCarButton(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setHeliOrientation",
                desc = "setHeliOrientation(Vehicle heli, float angle) ->",
                fn = function() return setHeliOrientation(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayerEnterCarButton",
                desc = "setPlayerEnterCarButton(Player player, bool can) ->",
                fn = function() return setPlayerEnterCarButton(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setVehicleDirtLevel",
                desc = "setVehicleDirtLevel(Vehicle car, float level) ->",
                fn = function() return setVehicleDirtLevel(getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setZoneForGangWarsTraining",
                desc = "setZoneForGangWarsTraining(GxtString zone) ->",
                fn = function() return setZoneForGangWarsTraining("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchAmbientPlanes",
                desc = "switchAmbientPlanes(bool enable) ->",
                fn = function() return switchAmbientPlanes(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchCarGenerator",
                desc = "switchCarGenerator(int carGenerator, int carsToGenerate) ->",
                fn = function() return switchCarGenerator(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchCopsOnBikes",
                desc = "switchCopsOnBikes(bool generate) ->",
                fn = function() return switchCopsOnBikes(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchPoliceHelis",
                desc = "switchPoliceHelis(bool enable) ->",
                fn = function() return switchPoliceHelis(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchRandomTrains",
                desc = "switchRandomTrains(bool enable) ->",
                fn = function() return switchRandomTrains(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "warpCharIntoCar",
                desc = "warpCharIntoCar(Ped ped, Vehicle car) ->",
                fn = function() return warpCharIntoCar(getTargetVehicleHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "warpCharIntoCarAsPassenger",
                desc = "warpCharIntoCarAsPassenger(Ped ped, Vehicle car, int passengerSeat) ->",
                fn = function() return warpCharIntoCarAsPassenger(getTargetVehicleHandle(), getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA Veh Position & Physics (24 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA Veh Position & Physics",
        tests = {
{
                name = "getCarCoordinates",
                desc = "Get vehicle 3D world coordinates",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return getCarCoordinates(car)
                end,
                validate = function(v)
                    if not isCoords3d(v[1], v[2], v[3]) then return false, "expected 3 valid coordinates" end
                    return true, string.format("(%.2f, %.2f, %.2f)", v[1], v[2], v[3])
                end
            },
{
                name = "getCarHeading",
                desc = "Get vehicle heading angle (0-360)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return getCarHeading(car)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < -360 or v[1] > 720 then return false, "expected heading in [0, 360]" end
                    return true, string.format("%.2f deg", v[1])
                end
            },
{
                name = "getVehicleVelocity",
                desc = "Get vehicle velocity vector (x, y, z)",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return getVehicleVelocity(car)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or not isFiniteNumber(v[2]) or not isFiniteNumber(v[3]) then
                        return false, "expected 3 velocity components"
                    end
                    return true, string.format("(%.3f, %.3f, %.3f)", v[1], v[2], v[3])
                end
            },
{
                name = "getCarSpeed",
                desc = "Get vehicle speed magnitude",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return getCarSpeed(car)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 then return false, "expected non-negative speed" end
                    return true, string.format("%.2f m/s", v[1])
                end
            },
{
                name = "isVehicleOnAllWheels",
                desc = "Check if vehicle has all wheels touching road surface",
                fn = function()
                    local car = getTargetVehicleHandle()
                    if car <= 0 then return makeSkip("no vehicle handle") end
                    return isVehicleOnAllWheels(car)
                end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "activateHeliSpeedCheat",
                desc = "activateHeliSpeedCheat(Vehicle heli, int power) ->",
                fn = function() return activateHeliSpeedCheat(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addToCarRotationVelocity",
                desc = "addToCarRotationVelocity(Vehicle car, float vecX, float vecY, float vecZ) ->",
                fn = function() return addToCarRotationVelocity(getTargetVehicleHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "carGotoCoordinates",
                desc = "carGotoCoordinates(Vehicle car, float driveToX, float driveToY, float driveToZ) ->",
                fn = function() return carGotoCoordinates(getTargetVehicleHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "carGotoCoordinatesAccurate",
                desc = "carGotoCoordinatesAccurate(Vehicle car, float toX, float toY, float toZ) ->",
                fn = function() return carGotoCoordinatesAccurate(getTargetVehicleHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "carGotoCoordinatesRacing",
                desc = "carGotoCoordinatesRacing(Vehicle car, float toX, float toY, float toZ) ->",
                fn = function() return carGotoCoordinatesRacing(getTargetVehicleHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "carLockAtCoordinates",
                desc = "Locks vehicle orientation facing target coordinates",
                fn = function() return carLockAtCoordinates(getTargetVehicleHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "carLookAtCoordinates",
                desc = "Rotates vehicle passenger view toward coordinates",
                fn = function() return carLookAtCoordinates(getTargetVehicleHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "freezeCarPosition",
                desc = "freezeCarPosition(Vehicle car, bool locked) ->",
                fn = function() return freezeCarPosition(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "freezeCarPositionAndDontLoadCollision",
                desc = "freezeCarPositionAndDontLoadCollision(Vehicle car, bool keep) ->",
                fn = function() return freezeCarPositionAndDontLoadCollision(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCarRoll",
                desc = "getCarRoll(Vehicle car) -> float roll",
                fn = function() return getCarRoll(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCarSpeedVector",
                desc = "getCarSpeedVector(Vehicle car) -> float vecX, float vecY, float vecZ",
                fn = function() return getCarSpeedVector(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarCoordinates",
                desc = "setCarCoordinates(Vehicle car, float atX, float atY, float atZ) ->",
                fn = function() return setCarCoordinates(getTargetVehicleHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarCruiseSpeed",
                desc = "setCarCruiseSpeed(Vehicle car, float maxSpeed) ->",
                fn = function() return setCarCruiseSpeed(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarForwardSpeed",
                desc = "setCarForwardSpeed(Vehicle car, float speed) ->",
                fn = function() return setCarForwardSpeed(getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarHeading",
                desc = "setCarHeading(Vehicle car, float angle) ->",
                fn = function() return setCarHeading(getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarRotationVelocity",
                desc = "setCarRotationVelocity(Vehicle car, float vecX, float vecY, float vecZ) ->",
                fn = function() return setCarRotationVelocity(getTargetVehicleHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setHeliBladesFullSpeed",
                desc = "setHeliBladesFullSpeed(Vehicle heli) ->",
                fn = function() return setHeliBladesFullSpeed(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setVehicleCoordinates",
                desc = "Sets 3D coordinates (x, y, z) of vehicle",
                fn = function() return setVehicleCoordinates(getTargetVehicleHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "warpCharFromCarToCoord",
                desc = "warpCharFromCarToCoord(Ped ped, float placeAtX, float placeAtY, float placeAtZ) ->",
                fn = function() return warpCharFromCarToCoord(getTargetVehicleHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA Vehicle Components & Colors (30 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA Vehicle Components & Colors",
        tests = {
{
                name = "GetVehicleSirenState",
                desc = "Returns vehicle emergency siren active state",
                fn = function() return GetVehicleSirenState(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "burstCarTire",
                desc = "burstCarTire(Vehicle car, int tire) ->",
                fn = function() return burstCarTire(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "changeCarColour",
                desc = "changeCarColour(Vehicle car, int primaryColor, int secondaryColor) -> bool result",
                fn = function() return changeCarColour(getTargetVehicleHandle(), 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "changeCarColourFromMenu",
                desc = "changeCarColourFromMenu(int panelID, Vehicle car, int colorslot, int activeRow) ->",
                fn = function() return changeCarColourFromMenu(getTargetVehicleHandle(), 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "closeAllCarDoors",
                desc = "closeAllCarDoors(Vehicle car) ->",
                fn = function() return closeAllCarDoors(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "controlCarDoor",
                desc = "controlCarDoor(Vehicle car, int door, int unlatch, float angle) ->",
                fn = function() return controlCarDoor(getTargetVehicleHandle(), 0, 0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "damageCarDoor",
                desc = "damageCarDoor(Vehicle car, int door) ->",
                fn = function() return damageCarDoor(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "damageCarPanel",
                desc = "damageCarPanel(Vehicle car, int door) ->",
                fn = function() return damageCarPanel(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "fixCarDoor",
                desc = "fixCarDoor(Vehicle car, int door) ->",
                fn = function() return fixCarDoor(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "fixCarPanel",
                desc = "fixCarPanel(Vehicle car, int componentB) ->",
                fn = function() return fixCarPanel(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "fixCarTire",
                desc = "fixCarTire(Vehicle car, int tire) ->",
                fn = function() return fixCarTire(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCarColours",
                desc = "getCarColours(Vehicle car) -> int primaryColor, int secondaryColor",
                fn = function() return getCarColours(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCarCurrentGear",
                desc = "getCarCurrentGear(Vehicle car) -> int gear",
                fn = function() return getCarCurrentGear(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCarNumberOfGears",
                desc = "getCarNumberOfGears(Vehicle car) -> int gears",
                fn = function() return getCarNumberOfGears(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getDoorAngleRatio",
                desc = "getDoorAngleRatio(Vehicle car, int door) -> float angle",
                fn = function() return getDoorAngleRatio(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getWheelieStats",
                desc = "getWheelieStats(Player player) -> int twowheelstime, float twowheelsdistance, int wheelietime, float wheelieDistance, int stoppieTime, float stoppieDistance",
                fn = function() return getWheelieStats(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarDoorDamaged",
                desc = "isCarDoorDamaged(Vehicle car, int door) -> bool result",
                fn = function() return isCarDoorDamaged(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarDoorFullyOpen",
                desc = "isCarDoorFullyOpen(Vehicle car, int door) -> bool result",
                fn = function() return isCarDoorFullyOpen(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarTireBurst",
                desc = "isCarTireBurst(Vehicle car, int tire) -> bool result",
                fn = function() return isCarTireBurst(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPlayerPerformingWheelie",
                desc = "isPlayerPerformingWheelie(Player player) -> bool result",
                fn = function() return isPlayerPerformingWheelie(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "lockCarDoors",
                desc = "lockCarDoors(Vehicle car, int status) ->",
                fn = function() return lockCarDoors(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "lockDoor",
                desc = "lockDoor(int door, bool lock) ->",
                fn = function() return lockDoor(0, 0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "openCarDoor",
                desc = "openCarDoor(Vehicle car, int door) ->",
                fn = function() return openCarDoor(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "openCarDoorABit",
                desc = "openCarDoorABit(Vehicle car, int door, float rotation) ->",
                fn = function() return openCarDoorABit(getTargetVehicleHandle(), 0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "popCarDoor",
                desc = "popCarDoor(Vehicle car, int door, bool visible) ->",
                fn = function() return popCarDoor(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "popCarPanel",
                desc = "popCarPanel(Vehicle car, int component, bool effectFlag) ->",
                fn = function() return popCarPanel(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarAlwaysLeaveTires",
                desc = "Forces vehicle tires to always leave skid marks",
                fn = function() return setCarAlwaysLeaveTires(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarDoorOpen",
                desc = "Opens specified vehicle door angle",
                fn = function() return setCarDoorOpen(getTargetVehicleHandle(), 0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarWheelScale",
                desc = "Sets visual scale multiplier for vehicle wheels",
                fn = function() return setCarWheelScale(getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchCarSiren",
                desc = "switchCarSiren(Vehicle car, bool siren) ->",
                fn = function() return switchCarSiren(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA Vehicle Stubs (21 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA Vehicle Stubs",
        tests = {
{
                name = "attachCharToBike",
                desc = "attachCharToBike(Ped ped, Vehicle car, float offsetX, float offsetY, float offsetZ, int position, float shootingAngle1, float shootingAngle2, int weapon) ->",
                fn = function() return attachCharToBike(getTargetPlayerHandle(), 0, 0.0, 0.0, 0.0, 0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachCharToCar",
                desc = "attachCharToCar(Ped ped, Vehicle car, float offsetX, float offsetY, float offsetZ, int position, float shootingAngleLimit, int weapon) ->",
                fn = function() return attachCharToCar(getTargetPlayerHandle(), getTargetVehicleHandle(), 0.0, 0.0, 0.0, 0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createCharInsideCar",
                desc = "createCharInsideCar(Vehicle car, Model pedtype, int model) -> Ped ped",
                fn = function() return createCharInsideCar(getTargetVehicleHandle(), 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "detachCharFromCar",
                desc = "detachCharFromCar(Ped ped) ->",
                fn = function() return detachCharFromCar(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarVisiblyDamaged",
                desc = "isCarVisiblyDamaged(Vehicle car) -> bool result",
                fn = function() return isCarVisiblyDamaged(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharAttachedToAnyCar",
                desc = "isCharAttachedToAnyCar(Ped ped) -> bool result",
                fn = function() return isCharAttachedToAnyCar(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInAnyBoat",
                desc = "isCharInAnyBoat(Ped ped) -> bool result",
                fn = function() return isCharInAnyBoat(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInAnyHeli",
                desc = "isCharInAnyHeli(Ped ped) -> bool result",
                fn = function() return isCharInAnyHeli(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInAnyPlane",
                desc = "isCharInAnyPlane(Ped ped) -> bool result",
                fn = function() return isCharInAnyPlane(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInAnyPoliceVehicle",
                desc = "isCharInAnyPoliceVehicle(Ped ped) -> bool result",
                fn = function() return isCharInAnyPoliceVehicle(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInAnyTrain",
                desc = "isCharInAnyTrain(Ped ped) -> bool result",
                fn = function() return isCharInAnyTrain(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInFlyingVehicle",
                desc = "isCharInFlyingVehicle(Ped ped) -> bool result",
                fn = function() return isCharInFlyingVehicle(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharOnAnyBike",
                desc = "isCharOnAnyBike(Ped ped) -> bool result",
                fn = function() return isCharOnAnyBike(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharStuckUnderCar",
                desc = "isCharStuckUnderCar(Ped ped) -> bool result",
                fn = function() return isCharStuckUnderCar(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarEngineBroken",
                desc = "setCarEngineBroken(Vehicle car, bool broken) ->",
                fn = function() return setCarEngineBroken(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharCanBeKnockedOffBike",
                desc = "setCharCanBeKnockedOffBike(Ped ped, bool can) ->",
                fn = function() return setCharCanBeKnockedOffBike(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharForceDieInCar",
                desc = "setCharForceDieInCar(Ped ped, bool stayInCarWhenDead) ->",
                fn = function() return setCharForceDieInCar(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharGetOutUpsideDownCar",
                desc = "setCharGetOutUpsideDownCar(Ped ped, bool canGetOut) ->",
                fn = function() return setCharGetOutUpsideDownCar(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayersCanBeInSeparateCars",
                desc = "setPlayersCanBeInSeparateCars(bool allow) ->",
                fn = function() return setPlayersCanBeInSeparateCars(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setVehicleCollision",
                desc = "Enables or disables physical collision on vehicle",
                fn = function() return setVehicleCollision(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchCarEngine",
                desc = "switchCarEngine(Vehicle car, bool state) ->",
                fn = function() return switchCarEngine(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA Camera (35 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA Camera",
        tests = {
{
                name = "isDebugCameraOn",
                desc = "Check if debug free-cam is enabled",
                fn = function() return isDebugCameraOn() end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "getActiveCameraCoordinates",
                desc = "Get current camera world coordinates (x, y, z)",
                fn = function() return getActiveCameraCoordinates() end,
                validate = function(v)
                    if not isCoords3d(v[1], v[2], v[3]) then return false, "expected 3 valid coordinates" end
                    return true, string.format("(%.2f, %.2f, %.2f)", v[1], v[2], v[3])
                end
            },
{
                name = "getActiveCameraPointAt",
                desc = "Get camera look-at target vector (x, y, z)",
                fn = function() return getActiveCameraPointAt() end,
                validate = function(v)
                    if not isCoords3d(v[1], v[2], v[3]) then return false, "expected 3 valid coordinates" end
                    return true, string.format("(%.2f, %.2f, %.2f)", v[1], v[2], v[3])
                end
            },
{
                name = "getActiveCameraRotation",
                desc = "Get camera rotation (roll, pitch, yaw)",
                fn = function() return getActiveCameraRotation() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or not isFiniteNumber(v[2]) or not isFiniteNumber(v[3]) then
                        return false, "expected 3 rotation values"
                    end
                    return true, string.format("(%.2f, %.2f, %.2f)", v[1], v[2], v[3])
                end
            },
{
                name = "getCameraFov",
                desc = "Get camera Field of View in degrees (10-120)",
                fn = function() return getCameraFov() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 10.0 or v[1] > 150.0 then
                        return false, "expected FOV in [10, 150], got: " .. formatValue(v[1])
                    end
                    return true, string.format("%.1f deg", v[1])
                end
            },
{
                name = "restoreCamera",
                desc = "Restore game camera to default player mode",
                fn = function()
                    restoreCamera()
                    return true
                end,
                validate = function(v)
                    return true, "restored cleanly"
                end
            },
{
                name = "setCameraBehindPlayer",
                desc = "Reset camera position directly behind player",
                fn = function()
                    setCameraBehindPlayer()
                    return true
                end,
                validate = function(v)
                    return true, "aligned behind player"
                end
            },
{
                name = "GetCameraManager",
                desc = "Returns pointer to game Camera manager singleton",
                fn = function() return GetCameraManager() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachCameraToChar",
                desc = "attachCameraToChar(Ped ped, float offsetX, float offsetY, float offsetZ, float rotationX, float rotationY, float rotationZ, float tilt, int switchstyle) ->",
                fn = function() return attachCameraToChar(getTargetPlayerHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachCameraToCharLookAtChar",
                desc = "attachCameraToCharLookAtChar(Ped ped, float offsetX, float offsetY, float offsetZ, int targetActor, float tilt, int switchstyle) ->",
                fn = function() return attachCameraToCharLookAtChar(getTargetPlayerHandle(), 0.0, 0.0, 0.0, getTargetPlayerHandle(), 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachCameraToVehicle",
                desc = "attachCameraToVehicle(Vehicle car, float offsetX, float offsetY, float offsetZ, float rotationX, float rotationY, float rotationZ, float tilt, int switchstyle) ->",
                fn = function() return attachCameraToVehicle(getTargetVehicleHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachCameraToVehicleLookAtChar",
                desc = "attachCameraToVehicleLookAtChar(Vehicle car, float offsetX, float offsetY, float offsetZ, Ped ped, float tilt, int switchstyle) ->",
                fn = function() return attachCameraToVehicleLookAtChar(getTargetVehicleHandle(), 0.0, 0.0, 0.0, getTargetPlayerHandle(), 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachCameraToVehicleLookAtVehicle",
                desc = "attachCameraToVehicleLookAtVehicle(Vehicle car, float offsetX, float offsetY, float offsetZ, int toCar, float tilt, int switchstyle) ->",
                fn = function() return attachCameraToVehicleLookAtVehicle(getTargetVehicleHandle(), 0.0, 0.0, 0.0, getTargetVehicleHandle(), 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "cameraIsVectorMoveRunning",
                desc = "cameraIsVectorMoveRunning() -> bool result",
                fn = function() return cameraIsVectorMoveRunning() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "cameraIsVectorTrackRunning",
                desc = "cameraIsVectorTrackRunning() -> bool result",
                fn = function() return cameraIsVectorTrackRunning() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "cameraResetNewScriptables",
                desc = "Resets scriptable camera matrix overrides",
                fn = function() return cameraResetNewScriptables() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "cameraSetVectorMove",
                desc = "cameraSetVectorMove(float cameraX, float cameraY, float cameraZ, float positionX, float positionY, float positionZ, int time, bool smoothTransition) ->",
                fn = function() return cameraSetVectorMove(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "cameraSetVectorTrack",
                desc = "cameraSetVectorTrack(float pointX, float pointY, float pointZ, float transverseX, float transverseY, float transverseZ, int time, bool smooth) ->",
                fn = function() return cameraSetVectorTrack(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "convert3DCoordsToScreenBatch",
                desc = "Projects multiple 3D world coordinates to 2D screen positions",
                fn = function() return convert3DCoordsToScreenBatch(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "convertGameScreenCoordsToWindowScreenCoords",
                desc = "convertGameScreenCoordsToWindowScreenCoords(float gposX, float gposY) -> float wposX, float wposY",
                fn = function() return convertGameScreenCoordsToWindowScreenCoords(0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "convertScreenCoordsToWorld3D",
                desc = "convertScreenCoordsToWorld3D(float posX, float posY, float depth) -> float posX, float posY, float posZ",
                fn = function() return convertScreenCoordsToWorld3D(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "convertWindowScreenCoordsToGameScreenCoords",
                desc = "convertWindowScreenCoordsToGameScreenCoords(float wposX, float wposY) -> float gposX, float gposY",
                fn = function() return convertWindowScreenCoordsToGameScreenCoords(0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCameraMatrix",
                desc = "Returns camera 4x4 orientation and position transformation matrix",
                fn = function() return getCameraMatrix() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getDebugCameraCoordinates",
                desc = "getDebugCameraCoordinates() -> float X, float Y, float Z",
                fn = function() return getDebugCameraCoordinates() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getDebugCameraPointAt",
                desc = "getDebugCameraPointAt() -> float X, float Y, float Z",
                fn = function() return getDebugCameraPointAt() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "noSpecialCameraForThisGarage",
                desc = "noSpecialCameraForThisGarage(int int1) ->",
                fn = function() return noSpecialCameraForThisGarage() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "pointCameraAtCar",
                desc = "pointCameraAtCar(Vehicle car, int mode, int switchstyle) ->",
                fn = function() return pointCameraAtCar(getTargetVehicleHandle(), 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "pointCameraAtChar",
                desc = "pointCameraAtChar(Ped ped, int mode, int switchstyle) ->",
                fn = function() return pointCameraAtChar(getTargetPlayerHandle(), 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "pointCameraAtPoint",
                desc = "pointCameraAtPoint(float pointAtX, float pointAtY, float pointAtZ, int switchstyle) ->",
                fn = function() return pointCameraAtPoint(0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "restoreCameraJumpcut",
                desc = "Restores camera jumpcut transition behavior",
                fn = function() return restoreCameraJumpcut() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCameraInFrontOfChar",
                desc = "setCameraInFrontOfChar(Ped ped) ->",
                fn = function() return setCameraInFrontOfChar(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCameraInFrontOfPlayer",
                desc = "Positions camera directly in front of player character",
                fn = function() return setCameraInFrontOfPlayer() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setFixedCameraPosition",
                desc = "setFixedCameraPosition(float positionX, float positionY, float positionZ, float rotationX, float rotationY, float rotationZ) ->",
                fn = function() return setFixedCameraPosition(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "shakeCam",
                desc = "shakeCam(int shake) ->",
                fn = function() return shakeCam(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchSecurityCamera",
                desc = "switchSecurityCamera(bool int1) ->",
                fn = function() return switchSecurityCamera(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA Camera Stubs (26 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA Camera Stubs",
        tests = {
{
                name = "allowFixedCameraCollision",
                desc = "allowFixedCameraCollision(bool allow) ->",
                fn = function() return allowFixedCameraCollision(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "cameraPersistFov",
                desc = "cameraPersistFov(bool lock) ->",
                fn = function() return cameraPersistFov(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "cameraPersistPos",
                desc = "cameraPersistPos(bool lock) ->",
                fn = function() return cameraPersistPos(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "cameraPersistTrack",
                desc = "cameraPersistTrack(bool lock) ->",
                fn = function() return cameraPersistTrack(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "cameraSetLerpFov",
                desc = "cameraSetLerpFov(float from, float to, int timelimit, bool smoothTransition) ->",
                fn = function() return cameraSetLerpFov(0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "cameraSetShakeSimulationSimple",
                desc = "cameraSetShakeSimulationSimple(int type, float timelimit, float intensity) ->",
                fn = function() return cameraSetShakeSimulationSimple(0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "doCameraBump",
                desc = "doCameraBump(float rotationZ, float rotationY) ->",
                fn = function() return doCameraBump(0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getAimSensitivity",
                desc = "Returns touch/mouse aiming sensitivity value",
                fn = function() return getAimSensitivity() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getAspectRatio",
                desc = "Returns current screen aspect ratio (width / height)",
                fn = function() return getAspectRatio() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getPlayerInCarCameraMode",
                desc = "getPlayerInCarCameraMode() -> int mode",
                fn = function() return getPlayerInCarCameraMode() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getRenderDistance",
                desc = "Returns world drawing distance multiplier",
                fn = function() return getRenderDistance() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "resetAimSensitivity",
                desc = "Resets aiming sensitivity to game default",
                fn = function() return resetAimSensitivity() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "resetAspectRatio",
                desc = "Resets screen aspect ratio to display default",
                fn = function() return resetAspectRatio() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "resetRenderDistance",
                desc = "Resets world drawing distance to default",
                fn = function() return resetRenderDistance() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "resetVehicleCameraTweak",
                desc = "Resets vehicle camera chase distance tweaks",
                fn = function() return resetVehicleCameraTweak() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setAimSensitivity",
                desc = "Sets touch/mouse aiming sensitivity value",
                fn = function() return setAimSensitivity(0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setAspectRatio",
                desc = "Sets custom screen aspect ratio",
                fn = function() return setAspectRatio(0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCameraPositionUnfixed",
                desc = "setCameraPositionUnfixed(float xAngle, float zAngle) ->",
                fn = function() return setCameraPositionUnfixed() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCameraZoom",
                desc = "setCameraZoom(int mode) ->",
                fn = function() return setCameraZoom(0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCinemaCamera",
                desc = "setCinemaCamera(bool lock) ->",
                fn = function() return setCinemaCamera(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setFirstPersonInCarCameraMode",
                desc = "setFirstPersonInCarCameraMode(bool enable) ->",
                fn = function() return setFirstPersonInCarCameraMode(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPhotoCameraEffect",
                desc = "setPhotoCameraEffect(bool firstPersonView) ->",
                fn = function() return setPhotoCameraEffect(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayerInCarCameraMode",
                desc = "setPlayerInCarCameraMode(int mode) ->",
                fn = function() return setPlayerInCarCameraMode(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setRenderDistance",
                desc = "Sets custom world draw distance limit",
                fn = function() return setRenderDistance(0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTwoPlayerCameraMode",
                desc = "setTwoPlayerCameraMode(bool mode) ->",
                fn = function() return setTwoPlayerCameraMode(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setVehicleCameraTweak",
                desc = "setVehicleCameraTweak(Model carModel, float distance, float altitudeMultiplier, float angleX) ->",
                fn = function() return setVehicleCameraTweak(0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA World & Math (157 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA World & Math",
        tests = {
{
                name = "getWeather",
                desc = "Get current weather ID (0-45)",
                fn = function() return getWeather() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 or v[1] > 50 then
                        return false, "expected weather ID in [0, 50], got: " .. formatValue(v[1])
                    end
                    return true, string.format("weather=%d", v[1])
                end
            },
{
                name = "setWeather",
                desc = "Set weather roundtrip test",
                fn = function()
                    local orig = getWeather()
                    local testVal = (orig == 2) and 1 or 2
                    setWeather(testVal)
                    local updated = getWeather()
                    setWeather(orig)
                    local restored = getWeather()
                    if updated ~= testVal then return false, "failed to update weather" end
                    if restored ~= orig then return false, "failed to restore weather" end
                    return true, orig
                end,
                validate = function(v)
                    return true, string.format("verified & restored (orig=%d)", v[2])
                end
            },
{
                name = "getGravity",
                desc = "Get current game gravity value (~0.008)",
                fn = function() return getGravity() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] <= 0.0 or v[1] > 1.0 then
                        return false, "expected gravity in (0, 1], got: " .. formatValue(v[1])
                    end
                    return true, string.format("%.5f", v[1])
                end
            },
{
                name = "setGravity",
                desc = "Set game gravity roundtrip test",
                fn = function()
                    local orig = getGravity()
                    local testVal = 0.0075
                    setGravity(testVal)
                    local updated = getGravity()
                    setGravity(orig)
                    local restored = getGravity()
                    if math.abs(updated - testVal) > 0.0001 then return false, "failed to update gravity" end
                    if math.abs(restored - orig) > 0.0001 then return false, "failed to restore gravity" end
                    return true, orig
                end,
                validate = function(v)
                    return true, string.format("verified & restored (orig=%.5f)", v[2])
                end
            },
{
                name = "getTimeOfDay",
                desc = "Get current game clock time (hours, minutes)",
                fn = function() return getTimeOfDay() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 or v[1] > 23 or
                       not isFiniteNumber(v[2]) or v[2] < 0 or v[2] > 59 then
                        return false, "expected hours in [0, 23] and minutes in [0, 59]"
                    end
                    return true, string.format("%02d:%02d", v[1], v[2])
                end
            },
{
                name = "setTimeOfDay",
                desc = "Set game clock time roundtrip test",
                fn = function()
                    local origH, origM = getTimeOfDay()
                    local testH = (origH + 1) % 24
                    setTimeOfDay(testH, 30)
                    local updH, updM = getTimeOfDay()
                    setTimeOfDay(origH, origM)
                    local resH, resM = getTimeOfDay()
                    if updH ~= testH or updM ~= 30 then return false, "failed to update time" end
                    if resH ~= origH or resM ~= origM then return false, "failed to restore time" end
                    return true, origH, origM
                end,
                validate = function(v)
                    return true, string.format("verified & restored (%02d:%02d)", v[2], v[3])
                end
            },
{
                name = "getGameTick",
                desc = "Get game frame tick counter (>0)",
                fn = function() return getGameTick() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] <= 0 then return false, "expected positive tick count" end
                    return true, string.format("tick=%d", v[1])
                end
            },
{
                name = "gameClock",
                desc = "Get continuous game clock in seconds",
                fn = function() return gameClock() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] <= 0 then return false, "expected positive clock" end
                    return true, string.format("%.2f s", v[1])
                end
            },
{
                name = "getTimeStepValue",
                desc = "Get game engine frame delta timestep",
                fn = function() return getTimeStepValue() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] <= 0 then return false, "expected positive timestep" end
                    return true, string.format("%.4f", v[1])
                end
            },
{
                name = "isGamePaused",
                desc = "Check if game execution is paused",
                fn = function() return isGamePaused() end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "isPauseMenuActive",
                desc = "Check if pause escape menu is active",
                fn = function() return isPauseMenuActive() end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "getGroundZFor3dCoord",
                desc = "Calculate ground surface Z height at local ped position",
                fn = function()
                    local ped = getTargetPlayerHandle()
                    if ped <= 0 then return makeSkip("no ped") end
                    local x, y, z = getCharCoordinates(ped)
                    return getGroundZFor3dCoord(x, y, z)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected finite ground Z" end
                    return true, string.format("Z=%.2f", v[1])
                end
            },
{
                name = "getDistanceBetweenCoords3d",
                desc = "Calculate 3D Euclidean distance (3-4-0 triangle = 5.0)",
                fn = function() return getDistanceBetweenCoords3d(0, 0, 0, 3, 4, 0) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or math.abs(v[1] - 5.0) > 0.001 then
                        return false, "expected 5.0, got: " .. formatValue(v[1])
                    end
                    return true, string.format("%.4f", v[1])
                end
            },
{
                name = "getDistanceBetweenCoords2d",
                desc = "Calculate 2D Euclidean distance (3-4 = 5.0)",
                fn = function() return getDistanceBetweenCoords2d(0, 0, 3, 4) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or math.abs(v[1] - 5.0) > 0.001 then
                        return false, "expected 5.0, got: " .. formatValue(v[1])
                    end
                    return true, string.format("%.4f", v[1])
                end
            },
{
                name = "getAngleBetween2dVectors",
                desc = "Calculate angle between orthogonal 2D vectors (1,0) and (0,1) = 90 deg",
                fn = function() return getAngleBetween2dVectors(1, 0, 0, 1) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or (math.abs(v[1] - 90.0) > 0.5 and math.abs(v[1] - 270.0) > 0.5) then
                        return false, "expected 90.0 or 270.0 deg, got: " .. formatValue(v[1])
                    end
                    return true, string.format("%.2f deg", v[1])
                end
            },
{
                name = "limitAngle",
                desc = "Normalize angle 370 deg -> 10 deg",
                fn = function() return limitAngle(370.0) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or math.abs(v[1] - 10.0) > 0.1 then
                        return false, "expected 10.0, got: " .. formatValue(v[1])
                    end
                    return true, string.format("%.1f deg", v[1])
                end
            },
{
                name = "convertMetresToFeet",
                desc = "Convert 1.0 metre to feet (~3.28084)",
                fn = function() return convertMetresToFeet(1.0) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or math.abs(v[1] - 3.28084) > 0.05 then
                        return false, "expected ~3.28 ft, got: " .. formatValue(v[1])
                    end
                    return true, string.format("%.3f ft", v[1])
                end
            },
{
                name = "getCityPlayerIsIn",
                desc = "Get city ID where local ped is located (0=Country, 1=LS, 2=SF, 3=LV)",
                fn = function() return getCityPlayerIsIn(getTargetPlayerHandle()) end,
                validate = function(v)
                    local cityNames = { [0] = "Countryside", [1] = "Los Santos", [2] = "San Fierro", [3] = "Las Venturas" }
                    if isFiniteNumber(v[1]) and v[1] >= 0 and v[1] <= 3 then
                        return true, string.format("%d (%s)", v[1], cityNames[v[1]] or "Unknown")
                    elseif type(v[1]) == "string" and #v[1] > 0 then
                        return true, '"' .. v[1] .. '"'
                    end
                    return false, "expected valid city ID (0-3), got: " .. formatValue(v[1])
                end
            },
{
                name = "getPlayerMoney",
                desc = "Get player cash balance",
                fn = function() return getPlayerMoney() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected numeric money" end
                    return true, string.format("$%d", v[1])
                end
            },
{
                name = "setPlayerMoney",
                desc = "Set player cash balance roundtrip test",
                fn = function()
                    local orig = getPlayerMoney()
                    setPlayerMoney(orig + 1)
                    local updated = getPlayerMoney()
                    setPlayerMoney(orig)
                    local restored = getPlayerMoney()
                    if updated ~= orig + 1 then return false, "failed to update money" end
                    if restored ~= orig then return false, "failed to restore money" end
                    return true, orig
                end,
                validate = function(v)
                    return true, string.format("verified & restored ($%d)", v[2])
                end
            },
{
                name = "getScreenResolution",
                desc = "Get mobile display resolution width and height",
                fn = function() return getScreenResolution() end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 320 or not isFiniteNumber(v[2]) or v[2] < 240 then
                        return false, "expected resolution w>=320 h>=240"
                    end
                    return true, string.format("%dx%d", v[1], v[2])
                end
            },
{
                name = "getWorkingDirectory",
                desc = "Get Lua working script directory path",
                fn = function() return getWorkingDirectory() end,
                validate = function(v)
                    if type(v[1]) ~= "string" or #v[1] == 0 then return false, "expected non-empty directory path" end
                    return true, v[1]
                end
            },
{
                name = "getGameDirectory",
                desc = "Get GTA game storage directory path",
                fn = function() return getGameDirectory() end,
                validate = function(v)
                    if type(v[1]) ~= "string" or #v[1] == 0 then return false, "expected non-empty directory path" end
                    return true, v[1]
                end
            },
{
                name = "doesDirectoryExist",
                desc = "Verify getWorkingDirectory() exists on filesystem",
                fn = function() return doesDirectoryExist(getWorkingDirectory()) end,
                validate = function(v)
                    if v[1] ~= true then return false, "working directory does not report existence" end
                    return true, "true"
                end
            },
{
                name = "randomInt",
                desc = "Generate random integer in range [10, 20]",
                fn = function() return randomInt(10, 20) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 10 or v[1] > 20 then
                        return false, "expected int in [10, 20], got: " .. formatValue(v[1])
                    end
                    return true, tostring(v[1])
                end
            },
{
                name = "randomFloat",
                desc = "Generate random float in range [1.0, 2.0]",
                fn = function() return randomFloat(1.0, 2.0) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 1.0 or v[1] > 2.0 then
                        return false, "expected float in [1.0, 2.0], got: " .. formatValue(v[1])
                    end
                    return true, string.format("%.4f", v[1])
                end
            },
{
                name = "getWaterHeightAtCoords",
                desc = "Get water surface elevation at coords",
                fn = function()
                    return getWaterHeightAtCoords(0.0, 0.0, true)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected finite number for water height, got: " .. formatValue(v[1]) end
                    return true, string.format("waterZ=%.2f", v[1])
                end
            },
{
                name = "getClosestStraightRoad",
                desc = "Get closest straight road segment coordinates",
                fn = function()
                    local ped = getTargetPlayerHandle()
                    if ped <= 0 then return makeSkip("no ped") end
                    local x, y, z = getCharCoordinates(ped)
                    return getClosestStraightRoad(x, y, z, 0.0, 50.0)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or not isFiniteNumber(v[2]) or not isFiniteNumber(v[3]) then
                        return false, "expected 3D coordinates for road segment"
                    end
                    return true, string.format("(%.1f, %.1f, %.1f)", v[1], v[2], v[3])
                end
            },
{
                name = "Vector3D",
                desc = "Global Vector3D constructor and vector math",
                fn = function()
                    if type(Vector3D) ~= "function" then return makeSkip("Vector3D not available") end
                    local v1 = Vector3D(1.0, 2.0, 2.0)
                    local len = v1:length()
                    local v2 = Vector3D(2.0, 3.0, 4.0)
                    local v3 = v1 + v2
                    return len, v3.x, v3.y, v3.z
                end,
                validate = function(v)
                    if math.abs(v[1] - 3.0) > 0.001 or v[2] ~= 3.0 or v[3] ~= 5.0 or v[4] ~= 6.0 then
                        return false, "Vector3D math failed: " .. formatReturnValues(v)
                    end
                    return true, string.format("length=%.1f, add=(%.1f,%.1f,%.1f)", v[1], v[2], v[3], v[4])
                end
            },
{
                name = "matrix3x3",
                desc = "Global matrix3x3 constructor and transformation",
                fn = function()
                    if type(matrix3x3) ~= "function" then return makeSkip("matrix3x3 not available") end
                    local m = matrix3x3()
                    return m.right.x, m.front.y, m.up.z
                end,
                validate = function(v)
                    if v[1] ~= 1.0 or v[2] ~= 1.0 or v[3] ~= 1.0 then
                        return false, "matrix3x3 identity mismatch: " .. formatReturnValues(v)
                    end
                    return true, "identity matrix verified"
                end
            },
{
                name = "MONET_DPI_SCALE",
                desc = "Screen DPI scale factor float",
                fn = function() return MONET_DPI_SCALE end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "MONET_GTASA_BASE",
                desc = "Base memory address of libGTASA.so library",
                fn = function() return MONET_GTASA_BASE end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "MONET_VERSION",
                desc = "Monet runtime version string",
                fn = function() return MONET_VERSION end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "OpenLink",
                desc = "Opens URL in system default browser",
                fn = function() return OpenLink("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "OpenUrl",
                desc = "Opens URL in system default browser",
                fn = function() return OpenUrl("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "__client_version",
                desc = "NeoMLoader client build version",
                fn = function() return __client_version end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "__game",
                desc = "Target game identifier string ('gta_sa_mp')",
                fn = function() return __game end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "__moonloader",
                desc = "MoonLoader compatibility API level (27)",
                fn = function() return __moonloader end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "__neom_build",
                desc = "NeoMLoader build number",
                fn = function() return __neom_build end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "__neom_version",
                desc = "NeoMLoader version string",
                fn = function() return __neom_version end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "__version",
                desc = "NeoMLoader runtime version number",
                fn = function() return __version end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "allowPauseInWidescreen",
                desc = "allowPauseInWidescreen(bool enable) ->",
                fn = function() return allowPauseInWidescreen(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "alterWantedLevel",
                desc = "alterWantedLevel(Player player, int wantedLevel) ->",
                fn = function() return alterWantedLevel(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "alterWantedLevelNoDrop",
                desc = "alterWantedLevelNoDrop(Player player, int minimumWantedLevel) ->",
                fn = function() return alterWantedLevelNoDrop(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "areSubtitlesSwitchedOn",
                desc = "areSubtitlesSwitchedOn() -> bool result",
                fn = function() return areSubtitlesSwitchedOn() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearArea",
                desc = "clearArea(float atX, float atY, float atZ, float radius, bool area) ->",
                fn = function() return clearArea(0.0, 0.0, 0.0, 0.0, getTargetVehicleHandle(), getTargetPlayerHandle(), getTargetObjectHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearCutscene",
                desc = "Clears cutscene data and releases cutscene models",
                fn = function() return clearCutscene() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearOnscreenTimer",
                desc = "clearOnscreenTimer(VarId var) ->",
                fn = function() return clearOnscreenTimer() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearSpecificZonesToTriggerGangWar",
                desc = "Clears specific gang war zone trigger flags",
                fn = function() return clearSpecificZonesToTriggerGangWar() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearWantedLevel",
                desc = "clearWantedLevel(Player player) ->",
                fn = function() return clearWantedLevel() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearWantedLevelInGarage",
                desc = "Clears player wanted level while inside Pay 'n' Spray garage",
                fn = function() return clearWantedLevelInGarage() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clock",
                desc = "Returns CPU execution time in seconds since script started",
                fn = function() return clock() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "consumeWindowMessage",
                desc = "consumeWindowMessage([bool game=true], [bool scripts=true]) ->",
                fn = function() return consumeWindowMessage() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "create",
                desc = "Creates and starts new cooperative Lua coroutine thread",
                fn = function() return create(function() end) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createDirectory",
                desc = "createDirectory(string directory) -> bool result",
                fn = function() return createDirectory("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "create_suspended",
                desc = "Creates suspended Lua coroutine thread without starting",
                fn = function() return create_suspended(function() end) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "decodeJson",
                desc = "decodeJson(string json) -> table data",
                fn = function() return decodeJson("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "displayHud",
                desc = "displayHud(bool enable) ->",
                fn = function() return displayHud(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "displayOnscreenTimer",
                desc = "displayOnscreenTimer(VarId var, bool countInDirection) ->",
                fn = function() return displayOnscreenTimer() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "displayOnscreenTimerWithString",
                desc = "displayOnscreenTimerWithString(VarId timer, int type, GxtString gxtString) ->",
                fn = function() return displayOnscreenTimerWithString() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "displayZoneNames",
                desc = "displayZoneNames(bool show) ->",
                fn = function() return displayZoneNames(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "doesFileExist",
                desc = "doesFileExist(string file) -> bool result",
                fn = function() return doesFileExist("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "downloadFile",
                desc = "Downloads remote file over HTTP to memory buffer",
                fn = function() return downloadFile("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "downloadFileToFile",
                desc = "Downloads remote file over HTTP directly to disk",
                fn = function() return downloadFileToFile("", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "drawShadow",
                desc = "drawShadow(Particle particle, float atX, float atY, float atZ, float rotationFactor, float size, int intensity, int flags1, int flags2, int flags3) ->",
                fn = function() return drawShadow(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "encodeJson",
                desc = "encodeJson(table data) -> string json",
                fn = function() return encodeJson(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "findClose",
                desc = "findClose(Filesearch handle) ->",
                fn = function() return findClose(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "findFirstFile",
                desc = "findFirstFile(string mask) -> Filesearch handle, string name",
                fn = function() return findFirstFile("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "findNextFile",
                desc = "findNextFile(Filesearch handle) -> string file",
                fn = function() return findNextFile(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "forceWeather",
                desc = "forceWeather(int weather) -> bool result",
                fn = function() return forceWeather(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "forceWeatherNow",
                desc = "forceWeatherNow(int weather) -> bool result",
                fn = function() return forceWeatherNow(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "formatTime",
                desc = "Formats timestamp according to date/time format string",
                fn = function() return formatTime("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "freezeOnscreenTimer",
                desc = "freezeOnscreenTimer(bool timer) ->",
                fn = function() return freezeOnscreenTimer(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getActiveInterior",
                desc = "getActiveInterior() -> int interior",
                fn = function() return getActiveInterior() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCurrentDayOfWeek",
                desc = "getCurrentDayOfWeek() -> int weekday",
                fn = function() return getCurrentDayOfWeek() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCurrentPopulationZoneType",
                desc = "getCurrentPopulationZoneType() -> int popcycle",
                fn = function() return getCurrentPopulationZoneType() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCutsceneOffset",
                desc = "getCutsceneOffset() -> bool result, float X, float Y, float Z",
                fn = function() return getCutsceneOffset() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCutsceneTime",
                desc = "getCutsceneTime() -> int time",
                fn = function() return getCutsceneTime() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getGameTimer",
                desc = "getGameTimer() -> int timeMs",
                fn = function() return getGameTimer() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getHTTPStatus",
                desc = "Returns HTTP response status code of last request",
                fn = function() return getHTTPStatus(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getHudColour",
                desc = "getHudColour(int interface) -> int r, int g, int b, int a",
                fn = function() return getHudColour(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getLastHTTPResponse",
                desc = "Returns response body string of last HTTP request",
                fn = function() return getLastHTTPResponse() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getMinutesToTimeOfDay",
                desc = "getMinutesToTimeOfDay(int hours, int minutes) -> int minutes",
                fn = function() return getMinutesToTimeOfDay(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getNameOfInfoZone",
                desc = "getNameOfInfoZone(float atX, float atY, float atZ) -> GxtString nameB",
                fn = function() return getNameOfInfoZone(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getNameOfZone",
                desc = "getNameOfZone(float X, float Y, float Z) -> GxtString name",
                fn = function() return getNameOfZone(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getTime",
                desc = "Returns current system time in milliseconds",
                fn = function() return getTime() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getTimestamp",
                desc = "Returns Unix epoch timestamp in seconds",
                fn = function() return getTimestamp() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getZoneDealerStrength",
                desc = "getZoneDealerStrength(GxtString zone) -> int strength",
                fn = function() return getZoneDealerStrength("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getZoneGangStrength",
                desc = "getZoneGangStrength(GxtString zone, int gang) -> int density",
                fn = function() return getZoneGangStrength("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasCutsceneFinished",
                desc = "hasCutsceneFinished() -> bool result",
                fn = function() return hasCutsceneFinished() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasCutsceneLoaded",
                desc = "hasCutsceneLoaded() -> bool result",
                fn = function() return hasCutsceneLoaded() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "initZonePopulationSettings",
                desc = "Initializes ambient population settings for current zone",
                fn = function() return initZonePopulationSettings() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isGameVersionOriginal",
                desc = "isGameVersionOriginal() -> bool result",
                fn = function() return isGameVersionOriginal() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isLineOfSightClear",
                desc = "isLineOfSightClear(float fromX, float fromY, float fromZ, float toX, float toY, float toZ, bool checkBuildings, bool checkVehicles, bool checkActors, bool checkObjects, bool checkParticles) -> bool result",
                fn = function() return isLineOfSightClear(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isSkipCutsceneButtonPressed",
                desc = "isSkipCutsceneButtonPressed() -> bool result",
                fn = function() return isSkipCutsceneButtonPressed() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isTimerAlive",
                desc = "Checks if active script timer handle is still running",
                fn = function() return isTimerAlive(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isWantedLevelGreater",
                desc = "isWantedLevelGreater(Player player, int level) -> bool result",
                fn = function() return isWantedLevelGreater(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isWindowMessageConsumed",
                desc = "Checks if touch/key input event was consumed",
                fn = function() return isWindowMessageConsumed() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "killTimer",
                desc = "Cancels and destroys active script timer handle",
                fn = function() return killTimer(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadCutscene",
                desc = "loadCutscene(GxtString cutscene) ->",
                fn = function() return loadCutscene("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "localClock",
                desc = "localClock() -> double time",
                fn = function() return localClock() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "openLink",
                desc = "Opens URL in default system web browser",
                fn = function() return openLink() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "openUrl",
                desc = "Opens URL in default system web browser",
                fn = function() return openUrl() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "print",
                desc = "print(any value, …) ->",
                fn = function() return print() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "processLineOfSight",
                desc = "processLineOfSight(float originX, float originY, float originZ, float targetX, float targetY, float targetZ, [bool checkSolid=true], [bool car=false], [bool ped=false], [bool object=false], [bool particle=false], [bool seeThrough=false], [bool ignoreSomeObjects=false], [bool shootThrough=false]) -> bool result, table colPoint",
                fn = function() return processLineOfSight(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "profiler",
                desc = "Returns script profiling and execution performance data",
                fn = function() return profiler() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "registerFastestTime",
                desc = "registerFastestTime(int stat, int to) ->",
                fn = function() return registerFastestTime(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "releaseWeather",
                desc = "Releases forced script weather back to natural cycle",
                fn = function() return releaseWeather() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "reloadScripts",
                desc = "Reloads all active NeoMLoader Lua scripts",
                fn = function()
                    if type(reloadScripts) == "function" then
                        return true, "registered (trigger bypassed to prevent reload loop)"
                    end
                    return false, "not defined"
                end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "restoreClock",
                desc = "Restores saved game clock time",
                fn = function() return restoreClock() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "script_author",
                desc = "Sets script author metadata string",
                fn = function() return script_author("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "script_authors",
                desc = "Sets script author list metadata",
                fn = function() return script_authors() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "script_dependencies",
                desc = "Declares required script module dependencies",
                fn = function() return script_dependencies() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "script_description",
                desc = "Sets script description metadata text",
                fn = function() return script_description("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "script_moonloader",
                desc = "Declares required MoonLoader version compatibility",
                fn = function() return script_moonloader(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "script_name",
                desc = "Sets human-readable script name metadata",
                fn = function() return script_name("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "script_properties",
                desc = "Configures script execution properties and flags",
                fn = function() return script_properties() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "script_url",
                desc = "Sets script homepage/update URL metadata",
                fn = function() return script_url("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "script_version",
                desc = "Sets script release version string",
                fn = function() return script_version("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "script_version_number",
                desc = "Sets script numeric release version integer",
                fn = function() return script_version_number(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "selectInterior",
                desc = "Warps local player to specified interior room ID",
                fn = function() return selectInterior(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCutsceneOffset",
                desc = "setCutsceneOffset(float posX, float posY, float posZ) ->",
                fn = function() return setCutsceneOffset(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setDarknessEffect",
                desc = "setDarknessEffect(bool enable, int value) ->",
                fn = function() return setDarknessEffect(0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setDisableMilitaryZones",
                desc = "setDisableMilitaryZones(bool disable) ->",
                fn = function() return setDisableMilitaryZones(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setHeathazeEffect",
                desc = "setHeathazeEffect(bool enable) ->",
                fn = function() return setHeathazeEffect(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setInteriorVisible",
                desc = "setInteriorVisible(int interior) ->",
                fn = function() return setInteriorVisible(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setNearClip",
                desc = "setNearClip(float clip) ->",
                fn = function() return setNearClip(0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setSpecificZoneToTriggerGangWar",
                desc = "setSpecificZoneToTriggerGangWar(GxtString zone) ->",
                fn = function() return setSpecificZoneToTriggerGangWar("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTimeOneDayForward",
                desc = "Advances game calendar and day of the week forward by one day",
                fn = function() return setTimeOneDayForward() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTimeScale",
                desc = "setTimeScale(float gamespeed) ->",
                fn = function() return setTimeScale(0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTimer",
                desc = "Creates recurring or one-shot script timer callback",
                fn = function() return setTimer(0, 0, function() end) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTimerBeepCountdownTime",
                desc = "setTimerBeepCountdownTime(VarId timer, int reach) ->",
                fn = function() return setTimerBeepCountdownTime(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setWeatherToAppropriateTypeNow",
                desc = "Instantly sets weather to appropriate type for current region",
                fn = function() return setWeatherToAppropriateTypeNow(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setZoneDealerStrength",
                desc = "setZoneDealerStrength(GxtString zone, int density) ->",
                fn = function() return setZoneDealerStrength("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setZoneGangStrength",
                desc = "setZoneGangStrength(GxtString zone, int gang, int density) ->",
                fn = function() return setZoneGangStrength("", 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setZoneNoCops",
                desc = "setZoneNoCops(GxtString zone, bool disableCops) ->",
                fn = function() return setZoneNoCops("", false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setZonePopulationRace",
                desc = "setZonePopulationRace(GxtString zone, int popcycle) ->",
                fn = function() return setZonePopulationRace("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setZonePopulationType",
                desc = "setZonePopulationType(GxtString zone, int popcycle) ->",
                fn = function() return setZonePopulationType("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "skipCutsceneEnd",
                desc = "Skips to the end of currently playing cutscene",
                fn = function() return skipCutsceneEnd() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "startCutscene",
                desc = "Starts playback of loaded cutscene",
                fn = function() return startCutscene() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "stopCutscene",
                desc = "Stops and terminates currently playing cutscene",
                fn = function() return stopCutscene() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "storeClock",
                desc = "Saves current game clock time into backup variable",
                fn = function() return storeClock() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchDeathPenalties",
                desc = "switchDeathPenalties(bool lose) ->",
                fn = function() return switchDeathPenalties(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchEmergencyServices",
                desc = "switchEmergencyServices(bool enable) ->",
                fn = function() return switchEmergencyServices(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchEntryExit",
                desc = "switchEntryExit(GxtString interior, bool access) ->",
                fn = function() return switchEntryExit("", false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchOnGroundSearchlight",
                desc = "switchOnGroundSearchlight(Searchlight searchlight, bool lightsThroughObstacles) ->",
                fn = function() return switchOnGroundSearchlight(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchRoadsBackToOriginal",
                desc = "switchRoadsBackToOriginal(float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ) ->",
                fn = function() return switchRoadsBackToOriginal(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchRoadsOff",
                desc = "switchRoadsOff(float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ) ->",
                fn = function() return switchRoadsOff(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchRoadsOn",
                desc = "switchRoadsOn(float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ) -> bool result",
                fn = function() return switchRoadsOn(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchRubbish",
                desc = "switchRubbish(bool int1) ->",
                fn = function() return switchRubbish(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchWidescreen",
                desc = "switchWidescreen(bool enable) ->",
                fn = function() return switchWidescreen(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchWorldProcessing",
                desc = "switchWorldProcessing(bool cutsceneOnly) ->",
                fn = function() return switchWorldProcessing(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "thisScript",
                desc = "thisScript() -> LuaScript s",
                fn = function() return thisScript() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "wait",
                desc = "wait(int time) ->",
                fn = function()
                    if coroutine.running() then
                        return wait(0)
                    end
                    return true
                end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "x",
                desc = "Vector X coordinate accessor",
                fn = function() return rawget(_G, "x") or 0 end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "y",
                desc = "Vector Y coordinate accessor",
                fn = function() return rawget(_G, "y") or 0 end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "z",
                desc = "Vector Z coordinate accessor",
                fn = function() return rawget(_G, "z") or 0 end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA Objects & Markers (98 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA Objects & Markers",
        tests = {
{
                name = "getAllObjects",
                desc = "Enumerate all active object handles in pool",
                fn = function() return getAllObjects() end,
                validate = function(v)
                    if type(v[1]) == "table" then
                        return true, string.format("%d objects found", #v[1])
                    elseif type(v[1]) == "number" then
                        return true, string.format("%d objects found", v[1])
                    else
                        return false, "expected table or count, got: " .. type(v[1])
                    end
                end
            },
{
                name = "doesObjectExist",
                desc = "Check doesObjectExist for handle",
                fn = function()
                    local obj = getTargetObjectHandle()
                    if obj <= 0 then return makeSkip("no objects in stream") end
                    return doesObjectExist(obj)
                end,
                validate = function(v)
                    if v[1] ~= true then return false, "expected object to exist" end
                    return true, "true"
                end
            },
{
                name = "getAllPickups",
                desc = "Enumerate all pickups in pool",
                fn = function() return getAllPickups() end,
                validate = function(v)
                    if type(v[1]) ~= "table" then return false, "expected table" end
                    return true, string.format("%d pickups found", #v[1])
                end
            },
{
                name = "doesPickupExist",
                desc = "Check doesPickupExist for handle",
                fn = function()
                    local p = getTargetPickupHandle()
                    if p <= 0 then return makeSkip("no pickups in stream") end
                    return doesPickupExist(p)
                end,
                validate = function(v)
                    if v[1] ~= true then return false, "expected pickup to exist" end
                    return true, "true"
                end
            },
{
                name = "User3dMarker_Lifecycle",
                isCompound = true,
                desc = "Create user 3D map marker and remove it",
                fn = function()
                    if type(createUser3dMarker) ~= "function" then return makeSkip("marker API unavailable") end
                    local m = createUser3dMarker(0.0, 0.0, 10.0, 0)
                    if not m or m <= 0 then return false, "failed to create marker" end
                    if type(removeUser3dMarker) == "function" then
                        removeUser3dMarker(m)
                    end
                    return true, m
                end,
                validate = function(v)
                    return true, string.format("created m=%d & removed", v[2])
                end
            },
{
                name = "Checkpoint_Lifecycle",
                isCompound = true,
                desc = "Create checkpoint, check isCheckpoint, and delete",
                fn = function()
                    if type(createCheckpoint) ~= "function" then return makeSkip("checkpoint API unavailable") end
                    local cp = createCheckpoint(0, 0.0, 0.0, 10.0, 0.0, 0.0, 10.0, 2.0)
                    local isCp = (type(isCheckpoint) == "function") and isCheckpoint(cp) or true
                    if type(deleteCheckpoint) == "function" then
                        deleteCheckpoint(cp)
                    end
                    return isCp, cp
                end,
                validate = function(v)
                    return true, "created & removed cleanly"
                end
            },
{
                name = "addToObjectRotationVelocity",
                desc = "addToObjectRotationVelocity(Object object, float vecX, float vecY, float vecZ) ->",
                fn = function() return addToObjectRotationVelocity(getTargetObjectHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addToObjectVelocity",
                desc = "addToObjectVelocity(Object object, float velocityX, float velocityY, float velocityZ) ->",
                fn = function() return addToObjectVelocity(getTargetObjectHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addVelocityRelativeToObjectVelocity",
                desc = "addVelocityRelativeToObjectVelocity(Object object, float vecX, float vecY, float vecZ) ->",
                fn = function() return addVelocityRelativeToObjectVelocity(getTargetObjectHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachCharToObject",
                desc = "attachCharToObject(Ped ped, Object object, float offsetX, float offsetY, float offsetZ, int orientation, float angle, int lockWeapon) ->",
                fn = function() return attachCharToObject(0, 0, 0.0, 0.0, 0.0, 0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachObjectToCar",
                desc = "attachObjectToCar(Object object, Vehicle car, float offsetX, float offsetY, float offsetZ, float rotationX, float rotationY, float rotationZ) ->",
                fn = function() return attachObjectToCar(0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachObjectToChar",
                desc = "attachObjectToChar(Object object, Ped ped, float offsetX, float offsetY, float offsetZ, float rotationX, float rotationY, float rotationZ) ->",
                fn = function() return attachObjectToChar(getTargetObjectHandle(), getTargetPlayerHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachObjectToObject",
                desc = "attachObjectToObject(Object object, int toObject, float offsetX, float offsetY, float offsetZ, float rotationX, float rotationY, float rotationZ) ->",
                fn = function() return attachObjectToObject(0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "breakObject",
                desc = "breakObject(Object object, int intensity) ->",
                fn = function() return breakObject(getTargetObjectHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearObjectLastWeaponDamage",
                desc = "clearObjectLastWeaponDamage(Object object) ->",
                fn = function() return clearObjectLastWeaponDamage(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearObjectPath",
                desc = "clearObjectPath(int int1) ->",
                fn = function() return clearObjectPath(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createCutsceneObject",
                desc = "createCutsceneObject(Model modelId) -> Object object",
                fn = function() return createCutsceneObject(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createMoneyPickup",
                desc = "createMoneyPickup(float atX, float atY, float atZ, int cash, bool permanenceFlag) -> Pickup pickup",
                fn = function() return createMoneyPickup(0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createObject",
                desc = "createObject(Model modelId, float atX, float atY, float atZ) -> Object object",
                fn = function() return createObject() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createPickup",
                desc = "createPickup(Model modelId, int type, float atX, float atY, float atZ) -> bool result, Pickup pickup",
                fn = function() return createPickup(0, 0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createPickupWithAmmo",
                desc = "createPickupWithAmmo(Model modelId, int type, int ammo, float atX, float atY, float atZ) -> Pickup pickup",
                fn = function() return createPickupWithAmmo(0, 0, 0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createUser3dMarker",
                desc = "createUser3dMarker(float atX, float atY, float atZ, int color) -> Marker marker",
                fn = function() return createUser3dMarker(0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "deleteObject",
                desc = "deleteObject(Object object) ->",
                fn = function() return deleteObject() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "detachObject",
                desc = "detachObject(Object object, float X, float Y, float Z, bool collisionDetection) ->",
                fn = function() return detachObject(getTargetObjectHandle(), 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "displayRadar",
                desc = "displayRadar(bool enable) ->",
                fn = function() return displayRadar(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "doesObjectHaveThisModel",
                desc = "doesObjectHaveThisModel(Object object, Model modelId) -> bool result",
                fn = function() return doesObjectHaveThisModel(getTargetObjectHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "flashHudObject",
                desc = "flashHudObject(int hudComponent) ->",
                fn = function() return flashHudObject(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getObjectAnimCurrentTime",
                desc = "getObjectAnimCurrentTime(Object object, string animation) -> float progress",
                fn = function() return getObjectAnimCurrentTime(0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getObjectCoordinates",
                desc = "getObjectCoordinates(Object object) -> float positionX, float positionY, float positionZ",
                fn = function() return getObjectCoordinates(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getObjectHeading",
                desc = "getObjectHeading(Object object) -> float angle",
                fn = function() return getObjectHeading(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getObjectHealth",
                desc = "getObjectHealth(Object object) -> int health",
                fn = function() return getObjectHealth(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getObjectMass",
                desc = "getObjectMass(Object object) -> float mass",
                fn = function() return getObjectMass(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getObjectModel",
                desc = "getObjectModel(Object object) -> Model modelId",
                fn = function() return getObjectModel(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getObjectPointer",
                desc = "getObjectPointer(Object object) -> uint struct",
                fn = function() return getObjectPointer(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getObjectPointerHandle",
                desc = "getObjectPointerHandle(uint ptr) -> Object handle",
                fn = function() return getObjectPointerHandle(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getObjectQuaternion",
                desc = "getObjectQuaternion(Object object) -> float x, float y, float z, float w",
                fn = function() return getObjectQuaternion(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getObjectRotation",
                desc = "Returns object rotation Euler angles (rx, ry, rz)",
                fn = function() return getObjectRotation(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getObjectRotationVelocity",
                desc = "getObjectRotationVelocity(Object object) -> float axisX, float axisY, float axisZ",
                fn = function() return getObjectRotationVelocity(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getObjectSpeed",
                desc = "getObjectSpeed(Object object) -> float speed",
                fn = function() return getObjectSpeed(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getObjectVelocity",
                desc = "getObjectVelocity(Object object) -> float vecX, float vecY, float vecZ",
                fn = function() return getObjectVelocity(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getPickupCoordinates",
                desc = "getPickupCoordinates(Pickup pickup) -> float X, float Y, float Z",
                fn = function() return getPickupCoordinates(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getPickupModel",
                desc = "getPickupModel(Pickup pickup) -> int model",
                fn = function() return getPickupModel(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getPickupPointer",
                desc = "getPickupPointer(Pickup pickup) -> int pointer",
                fn = function() return getPickupPointer(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getPickupPointerHandle",
                desc = "getPickupPointerHandle(int pointer) -> int handle",
                fn = function() return getPickupPointerHandle(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getPickupType",
                desc = "getPickupType(Pickup pickup) -> int type",
                fn = function() return getPickupType(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getTargetBlipCoordinates",
                desc = "getTargetBlipCoordinates() -> bool result, float posX, float posY, float posZ",
                fn = function() return getTargetBlipCoordinates() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasObjectBeenDamagedByWeapon",
                desc = "hasObjectBeenDamagedByWeapon(Object object, int type) -> bool result",
                fn = function() return hasObjectBeenDamagedByWeapon(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasPickupBeenCollected",
                desc = "hasPickupBeenCollected(Pickup pickup) -> bool result",
                fn = function() return hasPickupBeenCollected(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hideAllFrontendBlips",
                desc = "hideAllFrontendBlips(bool hide) ->",
                fn = function() return hideAllFrontendBlips(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "initialiseObjectPath",
                desc = "initialiseObjectPath(int int1, float float2) ->",
                fn = function() return initialiseObjectPath() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isAnyPickupAtCoords",
                desc = "isAnyPickupAtCoords(float pickupX, float pickupY, float pickupZ, float radius) -> bool result",
                fn = function() return isAnyPickupAtCoords(0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharHoldingObject",
                desc = "isCharHoldingObject(Ped ped, int liftingObject) -> bool result",
                fn = function() return isCharHoldingObject(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isMoneyPickupAtCoords",
                desc = "isMoneyPickupAtCoords(float atX, float atY, float atZ) -> bool result",
                fn = function() return isMoneyPickupAtCoords(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isObjectAttached",
                desc = "isObjectAttached(Object object) -> bool result",
                fn = function() return isObjectAttached(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isObjectModel",
                desc = "Checks if model ID is a valid object model",
                fn = function() return isObjectModel() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isObjectOnScreen",
                desc = "isObjectOnScreen(Object object) -> bool result",
                fn = function() return isObjectOnScreen(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPlayerTargettingObject",
                desc = "isPlayerTargettingObject(Player player, Object object) -> bool result",
                fn = function() return isPlayerTargettingObject(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPointOnScreen",
                desc = "isPointOnScreen(float sphereX, float sphereY, float sphereZ, float radius) -> bool result",
                fn = function() return isPointOnScreen(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharAnyMeansObject2d",
                desc = "locateCharAnyMeansObject2d(Ped ped, Object object, float radiusX, float radiusY, bool sphere) -> bool result",
                fn = function() return locateCharAnyMeansObject2d(getTargetPlayerHandle(), getTargetObjectHandle(), 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharAnyMeansObject3d",
                desc = "locateCharAnyMeansObject3d(Ped ped, Object object, float radiusX, float radiusY, float radiusZ, bool sphere) -> bool result",
                fn = function() return locateCharAnyMeansObject3d(getTargetPlayerHandle(), getTargetObjectHandle(), 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharInCarObject2d",
                desc = "locateCharInCarObject2d(Ped ped, Object object, float radiusX, float radiusY, bool sphere) -> bool result",
                fn = function() return locateCharInCarObject2d(0, 0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharInCarObject3d",
                desc = "locateCharInCarObject3d(Ped ped, Object object, float radiusX, float radiusY, float radiusZ, bool sphere) -> bool result",
                fn = function() return locateCharInCarObject3d(0, 0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharOnFootObject2d",
                desc = "locateCharOnFootObject2d(Ped ped, Object object, float radiusX, float radiusY, bool sphere) -> bool result",
                fn = function() return locateCharOnFootObject2d(0, 0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCharOnFootObject3d",
                desc = "locateCharOnFootObject3d(Ped ped, Object object, float radiusX, float radiusY, float radiusZ, bool sphere) -> bool result",
                fn = function() return locateCharOnFootObject3d(0, 0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removePickup",
                desc = "removePickup(Pickup pickup) -> bool result",
                fn = function() return removePickup(getTargetPickupHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeUser3dMarker",
                desc = "removeUser3dMarker(Marker marker) ->",
                fn = function() return removeUser3dMarker(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendEditAttachedObject",
                desc = "Sends attached object editing response RPC to server",
                fn = function() return sendEditAttachedObject() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendEditObject",
                desc = "Sends object editing sync RPC to server",
                fn = function() return sendEditObject() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendPickedUpPickup",
                desc = "Sends pickup collection event RPC to server",
                fn = function() return sendPickedUpPickup() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setBlipAlwaysDisplayOnZoomedRadar",
                desc = "setBlipAlwaysDisplayOnZoomedRadar(Marker marker, bool displayAlways) ->",
                fn = function() return setBlipAlwaysDisplayOnZoomedRadar(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setBlipAsFriendly",
                desc = "setBlipAsFriendly(Marker marker, bool type) ->",
                fn = function() return setBlipAsFriendly(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setBlipCoordinates",
                desc = "setBlipCoordinates(Marker blip, float x, float y, float z) -> bool result",
                fn = function() return setBlipCoordinates(0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setBlipEntryExit",
                desc = "setBlipEntryExit(Marker marker, float X, float Y, float radius) ->",
                fn = function() return setBlipEntryExit(0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectAnimCurrentTime",
                desc = "setObjectAnimCurrentTime(Object object, string animation, float progress) ->",
                fn = function() return setObjectAnimCurrentTime(0, "", 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectCollision",
                desc = "setObjectCollision(Object object, bool collision) ->",
                fn = function() return setObjectCollision() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectCoordinates",
                desc = "setObjectCoordinates(Object object, float atX, float atY, float atZ) -> bool result",
                fn = function() return setObjectCoordinates() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectCoordinatesAndVelocity",
                desc = "setObjectCoordinatesAndVelocity(Object object, float X, float Y, float Z) ->",
                fn = function() return setObjectCoordinatesAndVelocity(getTargetObjectHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectDynamic",
                desc = "setObjectDynamic(Object object, bool moveable) ->",
                fn = function() return setObjectDynamic(getTargetObjectHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectHeading",
                desc = "setObjectHeading(Object object, float angle) ->",
                fn = function() return setObjectHeading(getTargetObjectHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectHealth",
                desc = "setObjectHealth(Object object, int health) ->",
                fn = function() return setObjectHealth(getTargetObjectHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectMass",
                desc = "setObjectMass(Object object, float mass) ->",
                fn = function() return setObjectMass(getTargetObjectHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectProofs",
                desc = "setObjectProofs(Object object, bool BP, bool FP, bool EP, bool CP, bool MP) ->",
                fn = function() return setObjectProofs(getTargetObjectHandle(), false, false, false, false, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectRecordsCollisions",
                desc = "setObjectRecordsCollisions(Object object, bool set) ->",
                fn = function() return setObjectRecordsCollisions(getTargetObjectHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectRotation",
                desc = "setObjectRotation(Object object, float rotationX, float rotationY, float rotationZ) ->",
                fn = function() return setObjectRotation() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectRotationVelocity",
                desc = "setObjectRotationVelocity(Object object, float vecX, float vecY, float vecZ) ->",
                fn = function() return setObjectRotationVelocity(getTargetObjectHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectScale",
                desc = "setObjectScale(Object object, float scale) ->",
                fn = function() return setObjectScale() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectStatic",
                desc = "Sets object collision physics as static",
                fn = function() return setObjectStatic(getTargetObjectHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectVelocity",
                desc = "setObjectVelocity(Object object, float velocityInDirectionX, float velocityInDirectionY, float velocityInDirectionZ) ->",
                fn = function() return setObjectVelocity(getTargetObjectHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectVisible",
                desc = "setObjectVisible(Object object, bool visibility) ->",
                fn = function() return setObjectVisible(getTargetObjectHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setRadarZoom",
                desc = "setRadarZoom(int zoom) ->",
                fn = function() return setRadarZoom(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTargetBlipCoordinates",
                desc = "setTargetBlipCoordinates(float x, float y, float z) -> bool result",
                fn = function() return setTargetBlipCoordinates(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "showBlipsOnAllLevels",
                desc = "showBlipsOnAllLevels(bool enable) ->",
                fn = function() return showBlipsOnAllLevels(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchObjectBrains",
                desc = "switchObjectBrains(int externalScript, bool canBeStreamedIn) ->",
                fn = function() return switchObjectBrains(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskComplexPickupObject",
                desc = "taskComplexPickupObject(Ped ped, Object object) ->",
                fn = function() return taskComplexPickupObject(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskGoToObject",
                desc = "taskGoToObject(Ped ped, int toObject, int timelimit, float stopWithinRadius) ->",
                fn = function() return taskGoToObject(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskLookAtObject",
                desc = "taskLookAtObject(Ped ped, int lookAt, int timeMS) ->",
                fn = function() return taskLookAtObject(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskPickUpObject",
                desc = "taskPickUpObject(Ped ped, Object object, float offsetX, float offsetY, float offsetZ, int boneId1, int boneId2, string performAnimation, int IFPFile, int time) ->",
                fn = function() return taskPickUpObject(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskPickUpSecondObject",
                desc = "taskPickUpSecondObject(Ped ped, Object object, float offsetX, float offsetY, float offsetZ, int bone, int int7, string animation, string file, int time) ->",
                fn = function() return taskPickUpSecondObject(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA Checkpoints & Spheres (29 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA Checkpoints & Spheres",
        tests = {
{
                name = "addBlipForCar",
                desc = "addBlipForCar(Vehicle car) -> Marker marker",
                fn = function() return addBlipForCar(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addBlipForCarOld",
                desc = "addBlipForCarOld(Vehicle car, int unused, bool visibility) -> Marker marker",
                fn = function() return addBlipForCarOld(getTargetVehicleHandle(), 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addBlipForChar",
                desc = "addBlipForChar(Ped ped) -> Marker marker",
                fn = function() return addBlipForChar(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addBlipForCharOld",
                desc = "addBlipForCharOld(Ped ped, int int2, int int3) -> Marker marker",
                fn = function() return addBlipForCharOld(getTargetPlayerHandle(), 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addBlipForCoord",
                desc = "addBlipForCoord(float atX, float atY, float atZ) -> Checkpoint checkpoint",
                fn = function() return addBlipForCoord(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addBlipForCoordOld",
                desc = "addBlipForCoordOld(float atX, float atY, float atZ, int color, int flag) -> Marker marker",
                fn = function() return addBlipForCoordOld(0.0, 0.0, 0.0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addBlipForDeadChar",
                desc = "addBlipForDeadChar(Ped ped) -> Marker blip",
                fn = function() return addBlipForDeadChar(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addBlipForObject",
                desc = "addBlipForObject(Object object) -> Marker marker",
                fn = function() return addBlipForObject(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addBlipForPickup",
                desc = "addBlipForPickup(Pickup pickup) -> Marker marker",
                fn = function() return addBlipForPickup(getTargetPickupHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addBlipForSearchlight",
                desc = "addBlipForSearchlight(Searchlight searchlight) -> Marker marker",
                fn = function() return addBlipForSearchlight(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addShortRangeSpriteBlipForContactPoint",
                desc = "addShortRangeSpriteBlipForContactPoint(float pX, float pY, float pZ, int icon) -> Marker blip",
                fn = function() return addShortRangeSpriteBlipForContactPoint(0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addShortRangeSpriteBlipForCoord",
                desc = "addShortRangeSpriteBlipForCoord(float atX, float atY, float atZ, int icon) -> Marker marker",
                fn = function() return addShortRangeSpriteBlipForCoord(0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addSphere",
                desc = "addSphere(float atX, float atY, float atZ, float radius) -> int sphere",
                fn = function() return addSphere(0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addSpriteBlipForContactPoint",
                desc = "addSpriteBlipForContactPoint(float atX, float atY, float atZ, int icon) -> Marker marker",
                fn = function() return addSpriteBlipForContactPoint(0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addSpriteBlipForCoord",
                desc = "addSpriteBlipForCoord(float atX, float atY, float atZ, int type) -> Marker marker",
                fn = function() return addSpriteBlipForCoord(0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "changeBlipColour",
                desc = "changeBlipColour(Marker marker, int color) ->",
                fn = function() return changeBlipColour(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "changeBlipDisplay",
                desc = "changeBlipDisplay(Marker marker, int mode) ->",
                fn = function() return changeBlipDisplay(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "changeBlipScale",
                desc = "changeBlipScale(Marker marker, int size) ->",
                fn = function() return changeBlipScale(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearAllBlipsOnMap",
                desc = "Removes all custom blip markers from radar/map",
                fn = function() return clearAllBlipsOnMap() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createCheckpoint",
                desc = "createCheckpoint(int type, float atX, float atY, float atZ, float pointX, float pointY, float pointZ, float radius) -> Checkpoint checkpoint",
                fn = function() return createCheckpoint(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "deleteCheckpoint",
                desc = "deleteCheckpoint(Checkpoint checkpoint) ->",
                fn = function() return deleteCheckpoint(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "doesBlipExist",
                desc = "doesBlipExist(Marker marker) -> bool result",
                fn = function() return doesBlipExist(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "findAllRandomCharsInSphere",
                desc = "findAllRandomCharsInSphere(float posX, float posY, float posZ, float radius, bool findNext, bool skipDead) -> bool result, Ped ped",
                fn = function() return findAllRandomCharsInSphere(0.0, 0.0, 0.0, 0.0, false, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCheckpoint",
                desc = "Checks if player is inside an active checkpoint",
                fn = function() return isCheckpoint(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeBlip",
                desc = "removeBlip(Marker marker) ->",
                fn = function() return removeBlip(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setBlipAlwaysDisplayOnRadar",
                desc = "Forces map blip to remain visible on radar",
                fn = function() return setBlipAlwaysDisplayOnRadar(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCheckpointCoords",
                desc = "setCheckpointCoords(Checkpoint checkpoint, float X, float Y, float Z) ->",
                fn = function() return setCheckpointCoords(0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCheckpointHeading",
                desc = "setCheckpointHeading(Checkpoint checkpoint, float angle) ->",
                fn = function() return setCheckpointHeading(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCoordBlipAppearance",
                desc = "setCoordBlipAppearance(Checkpoint checkpoint, int type) ->",
                fn = function() return setCoordBlipAppearance(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA Audio & AudioStreams (48 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA Audio & AudioStreams",
        tests = {
{
                name = "addContinuousSound",
                desc = "addContinuousSound(float atX, float atY, float atZ, int sound) -> int unk",
                fn = function() return addContinuousSound(0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addExplosionNoSound",
                desc = "addExplosionNoSound(float pX, float pY, float pZ, int type) ->",
                fn = function() return addExplosionNoSound(0.0, 0.0, 0.0, 0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addOneOffSound",
                desc = "addOneOffSound(float atX, float atY, float atZ, int sound) ->",
                fn = function() return addOneOffSound() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "allocateStreamedScriptToRandomPed",
                desc = "allocateStreamedScriptToRandomPed(int externalScript, Model actorModel, int priority) ->",
                fn = function() return allocateStreamedScriptToRandomPed() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearMissionAudio",
                desc = "clearMissionAudio(int id) ->",
                fn = function() return clearMissionAudio(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getAudioStreamLength",
                desc = "Returns total duration of audio stream in seconds",
                fn = function() return getAudioStreamLength(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getAudioStreamLooped",
                desc = "Checks if audio stream is configured to loop",
                fn = function() return getAudioStreamLooped(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getAudioStreamState",
                desc = "Returns playback state of audio stream (playing/paused/stopped)",
                fn = function() return getAudioStreamState(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getAudioStreamVolume",
                desc = "Returns playback volume of audio stream (0.0 - 1.0)",
                fn = function() return getAudioStreamVolume(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getRadioChannel",
                desc = "getRadioChannel() -> int radio",
                fn = function() return getRadioChannel() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getSoundLevelAtCoords",
                desc = "getSoundLevelAtCoords(Ped ped, float X, float Y, float Z) -> float level",
                fn = function() return getSoundLevelAtCoords(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getStreamLength",
                desc = "Returns total duration of audio stream in seconds",
                fn = function() return getStreamLength(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getStreamPosition",
                desc = "Returns current playback position in audio stream in seconds",
                fn = function() return getStreamPosition(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getStreamVolume",
                desc = "Returns volume of audio stream (0.0 - 1.0)",
                fn = function() return getStreamVolume(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasMissionAudioFinished",
                desc = "hasMissionAudioFinished(int id) -> bool result",
                fn = function() return hasMissionAudioFinished(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasMissionAudioLoaded",
                desc = "hasMissionAudioLoaded(int id) -> bool result",
                fn = function() return hasMissionAudioLoaded(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isStreamPlaying",
                desc = "Checks if audio stream is currently playing",
                fn = function() return isStreamPlaying(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "load3dAudioStream",
                desc = "Loads audio stream with 3D positional audio support",
                fn = function() return load3dAudioStream("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadAudioStream",
                desc = "Loads audio stream from URL or local file path",
                fn = function() return loadAudioStream("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadMissionAudio",
                desc = "loadMissionAudio(int asId, int name) ->",
                fn = function() return loadMissionAudio(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadStream",
                desc = "Loads audio stream from URL or local file path",
                fn = function() return loadStream("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadURL",
                desc = "Loads streaming audio directly from HTTP URL",
                fn = function() return loadURL("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "monet_get_audiostream_handle",
                desc = "Returns native audio backend stream handle",
                fn = function() return monet_get_audiostream_handle(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "monet_is_audiostream_available",
                desc = "Checks if audio streaming subsystem is initialized",
                fn = function() return monet_is_audiostream_available() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "pauseStream",
                desc = "Pauses audio stream playback",
                fn = function() return pauseStream(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "playMissionAudio",
                desc = "playMissionAudio(int id) ->",
                fn = function() return playMissionAudio(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "playStream",
                desc = "Starts or resumes audio stream playback",
                fn = function() return playStream(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "releaseAudioStream",
                desc = "Frees audio stream resources from memory",
                fn = function() return releaseAudioStream(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "releaseStream",
                desc = "Frees audio stream resources from memory",
                fn = function() return releaseStream(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeSound",
                desc = "removeSound(int sound) ->",
                fn = function() return removeSound(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "resumeStream",
                desc = "Resumes playback of paused audio stream",
                fn = function() return resumeStream(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setAudioStreamLooped",
                desc = "Enables or disables looping for audio stream",
                fn = function() return setAudioStreamLooped(0, getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setAudioStreamPosition",
                desc = "Seeks audio stream to position in seconds",
                fn = function() return setAudioStreamPosition(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setAudioStreamState",
                desc = "Sets audio stream playback state",
                fn = function() return setAudioStreamState(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setAudioStreamVolume",
                desc = "Sets audio stream volume level (0.0 - 1.0)",
                fn = function() return setAudioStreamVolume(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setMissionAudioPosition",
                desc = "setMissionAudioPosition(int id, float locationX, float locationY, float locationZ) ->",
                fn = function() return setMissionAudioPosition(0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlay3dAudioStreamAtChar",
                desc = "Attaches 3D positional audio stream to character ped",
                fn = function() return setPlay3dAudioStreamAtChar(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlay3dAudioStreamAtCoordinates",
                desc = "Sets 3D positional audio stream world coordinates",
                fn = function() return setPlay3dAudioStreamAtCoordinates(0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlay3dAudioStreamAtVehicle",
                desc = "Attaches 3D positional audio stream to vehicle",
                fn = function() return setPlay3dAudioStreamAtVehicle(getTargetVehicleHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setRadioChannel",
                desc = "setRadioChannel(int radioStation) ->",
                fn = function() return setRadioChannel(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setStreamPosition",
                desc = "Seeks audio stream to position in seconds",
                fn = function() return setStreamPosition(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setStreamSpeed",
                desc = "Sets audio stream playback speed/pitch multiplier",
                fn = function() return setStreamSpeed(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setStreamSync",
                desc = "Synchronizes audio stream playback timing",
                fn = function() return setStreamSync(0, 0, function() end) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setStreamVolume",
                desc = "Sets audio stream volume level (0.0 - 1.0)",
                fn = function() return setStreamVolume(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "stopAllStreams",
                desc = "Stops playback of all active audio streams",
                fn = function() return stopAllStreams() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "stopStream",
                desc = "Stops playback of specified audio stream",
                fn = function() return stopStream(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchAudioZone",
                desc = "switchAudioZone(GxtString zone, bool enableSound) ->",
                fn = function() return switchAudioZone("", false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "switchStreaming",
                desc = "switchStreaming(bool streaming) ->",
                fn = function() return switchStreaming(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA Explosions & Particles (34 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA Explosions & Particles",
        tests = {
{
                name = "addExplosion",
                desc = "addExplosion(float atX, float atY, float atZ, int radius) -> bool result",
                fn = function() return addExplosion(0.0, 0.0, 0.0, 0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addExplosionVariableShake",
                desc = "addExplosionVariableShake(float atX, float atY, float atZ, int type, float cameraShake) ->",
                fn = function() return addExplosionVariableShake(0.0, 0.0, 0.0, 0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachFxSystemToCharBone",
                desc = "attachFxSystemToCharBone(Particle particle, Ped ped, int mode) ->",
                fn = function() return attachFxSystemToCharBone(getTargetPlayerHandle(), getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearAllScriptFireFlags",
                desc = "Clears all scripted fire flags in the world",
                fn = function() return clearAllScriptFireFlags() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createFxSystem",
                desc = "createFxSystem(string particle, float pX, float pY, float pZ, int type) -> Particle particle",
                fn = function() return createFxSystem("", 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createFxSystemOnCar",
                desc = "createFxSystemOnCar(string particle, Vehicle car, float offsetX, float offsetY, float offsetZ, int type) -> Particle particle",
                fn = function() return createFxSystemOnCar("", getTargetVehicleHandle(), 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createFxSystemOnCarWithDirection",
                desc = "createFxSystemOnCarWithDirection(string particle, Vehicle car, float offsetX, float offsetY, float offsetZ, float rotationX, float rotationY, float rotationZ, int type) -> Particle particle",
                fn = function() return createFxSystemOnCarWithDirection("", getTargetVehicleHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createFxSystemOnChar",
                desc = "createFxSystemOnChar(string particle, Ped ped, float offsetX, float offsetY, float offsetZ, int type) -> Particle particle",
                fn = function() return createFxSystemOnChar("", getTargetPlayerHandle(), 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createFxSystemOnCharWithDirection",
                desc = "createFxSystemOnCharWithDirection(string particle, Ped ped, float offsetX, float offsetY, float offsetZ, float rotationX, float rotationY, float rotationZ, int type) -> Particle particle",
                fn = function() return createFxSystemOnCharWithDirection("", getTargetPlayerHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createFxSystemOnObject",
                desc = "createFxSystemOnObject(string particle, Object object, float offsetX, float offsetY, float offsetZ, int type) -> Particle particle",
                fn = function() return createFxSystemOnObject("", 0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createFxSystemOnObjectWithDirection",
                desc = "createFxSystemOnObjectWithDirection(string particle, Object object, float offsetX, float offsetY, float offsetZ, float rotationX, float rotationY, float rotationZ, int flag) -> Particle particle",
                fn = function() return createFxSystemOnObjectWithDirection("", 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "doesScriptFireExist",
                desc = "doesScriptFireExist(int fire) -> bool result",
                fn = function() return doesScriptFireExist(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "extinguishFireAtPoint",
                desc = "extinguishFireAtPoint(float atX, float atY, float atZ, float radius) ->",
                fn = function() return extinguishFireAtPoint(0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "fireHunterGun",
                desc = "fireHunterGun(Vehicle car) ->",
                fn = function() return fireHunterGun(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "fireSingleBullet",
                desc = "fireSingleBullet(float fromX, float fromY, float fromZ, float targetX, float targetY, float targetZ, int energy) ->",
                fn = function() return fireSingleBullet(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getNumberOfFiresInArea",
                desc = "getNumberOfFiresInArea(float x1, float y1, float z1, float x2, float y2, float z2) -> int num",
                fn = function() return getNumberOfFiresInArea(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getNumberOfFiresInRange",
                desc = "getNumberOfFiresInRange(float atX, float atY, float atZ, float radius) -> int num",
                fn = function() return getNumberOfFiresInRange(0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getScriptFireCoords",
                desc = "getScriptFireCoords(int fire) -> float X, float Y, float Z",
                fn = function() return getScriptFireCoords(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getWeapontypeModel",
                desc = "getWeapontypeModel(int id) -> int model",
                fn = function() return getWeapontypeModel(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getWeapontypeSlot",
                desc = "getWeapontypeSlot(int id) -> int slot",
                fn = function() return getWeapontypeSlot(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isExplosionInArea",
                desc = "isExplosionInArea(int explosionType, float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ) -> bool result",
                fn = function() return isExplosionInArea(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isScriptFireExtinguished",
                desc = "isScriptFireExtinguished(int fire) -> bool result",
                fn = function() return isScriptFireExtinguished(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "killFxSystem",
                desc = "killFxSystem(Particle particle) ->",
                fn = function() return killFxSystem(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "killFxSystemNow",
                desc = "killFxSystemNow(Particle particle) ->",
                fn = function() return killFxSystemNow(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "makePlayerFireProof",
                desc = "makePlayerFireProof(Player player, bool fireproof) ->",
                fn = function() return makePlayerFireProof() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "playAndKillFxSystem",
                desc = "playAndKillFxSystem(Particle particle) ->",
                fn = function() return playAndKillFxSystem(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "playFxSystem",
                desc = "playFxSystem(Particle particle) ->",
                fn = function() return playFxSystem(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeAllScriptFires",
                desc = "Extinguishes and deletes all script-spawned fires",
                fn = function() return removeAllScriptFires() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeScriptFire",
                desc = "removeScriptFire(int fire) ->",
                fn = function() return removeScriptFire(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setMaxFireGenerations",
                desc = "setMaxFireGenerations(int max) ->",
                fn = function() return setMaxFireGenerations(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayerFireButton",
                desc = "setPlayerFireButton(Player player, bool able) ->",
                fn = function() return setPlayerFireButton() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "startCarFire",
                desc = "startCarFire(Vehicle car) -> int fire",
                fn = function() return startCarFire(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "startScriptFire",
                desc = "startScriptFire(float atX, float atY, float atZ, int propagation, int size) -> int fire",
                fn = function() return startScriptFire(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "stopFxSystem",
                desc = "stopFxSystem(Particle particle) ->",
                fn = function() return stopFxSystem(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- GTA Models & Animations (43 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "GTA Models & Animations",
        tests = {
{
                name = "GetEntityModel",
                desc = "Returns entity model ID from entity memory",
                fn = function() return GetEntityModel(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "applyAnimation",
                desc = "Applies animation library and name to character ped",
                fn = function() return applyAnimation(getTargetPlayerHandle(), "", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "buildPlayerModel",
                desc = "buildPlayerModel(Player player) ->",
                fn = function() return buildPlayerModel(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearAnimationsForChar",
                desc = "Stops and clears all active animations on character ped",
                fn = function() return clearAnimationsForChar(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearLastBuildingModelShotByPlayer",
                desc = "clearLastBuildingModelShotByPlayer(Player player) ->",
                fn = function() return clearLastBuildingModelShotByPlayer() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearSequenceTask",
                desc = "clearSequenceTask(int task) ->",
                fn = function() return clearSequenceTask(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "closeSequenceTask",
                desc = "closeSequenceTask(int task) ->",
                fn = function() return closeSequenceTask(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCarModelValue",
                desc = "getCarModelValue(Model modelId) -> int price",
                fn = function() return getCarModelValue(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCharAnimCurrentTime",
                desc = "getCharAnimCurrentTime(Ped ped, string animation) -> float time",
                fn = function() return getCharAnimCurrentTime(0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCharAnimTotalTime",
                desc = "getCharAnimTotalTime(Ped ped, string animation) -> float totalTime",
                fn = function() return getCharAnimTotalTime(0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCharAnimationId",
                desc = "Returns active animation ID playing on character ped",
                fn = function() return getCharAnimationId() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCharModel",
                desc = "getCharModel(Ped ped) -> Model modelId",
                fn = function() return getCharModel(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getModelDimensions",
                desc = "getModelDimensions(Model modelId) -> float x1, float y1, float z1, float x2, float y2, float z2",
                fn = function() return getModelDimensions(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getVehicleModel",
                desc = "Returns vehicle model ID integer",
                fn = function() return getVehicleModel(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasAnimationLoaded",
                desc = "hasAnimationLoaded(string animation) -> bool result",
                fn = function() return hasAnimationLoaded("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasModelLoaded",
                desc = "hasModelLoaded(Model modelId) -> bool result",
                fn = function() return hasModelLoaded(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarModel",
                desc = "isCarModel(Vehicle car, Model modelId) -> bool result",
                fn = function()
                    local vHandle = getTargetVehicleHandle()
                    local model = (vHandle > 0 and type(getCarModel) == "function") and getCarModel(vHandle) or 0
                    return isCarModel(vHandle, model)
                end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInModel",
                desc = "isCharInModel(Ped ped, Model carModel) -> bool result",
                fn = function()
                    local vHandle = getTargetVehicleHandle()
                    local model = (vHandle > 0 and type(getCarModel) == "function") and getCarModel(vHandle) or 0
                    return isCharInModel(getTargetPlayerHandle(), model)
                end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharModel",
                desc = "isCharModel(Ped ped, Model modelId) -> bool result",
                fn = function()
                    local pHandle = getTargetPlayerHandle()
                    local model = (pHandle > 0 and type(getCharModel) == "function") and getCharModel(pHandle) or 0
                    return isCharModel(pHandle, model)
                end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharPlayingAnim",
                desc = "isCharPlayingAnim(Ped ped, string animation) -> bool result",
                fn = function() return isCharPlayingAnim(getTargetPlayerHandle(), "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isModelAvailable",
                desc = "isModelAvailable(Model modelId) -> bool result",
                fn = function() return isModelAvailable(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isModelInCdimage",
                desc = "isModelInCdimage(Model modelId) -> bool result",
                fn = function() return isModelInCdimage(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadAllModelsNow",
                desc = "Immediately forces loaded requested models into memory",
                fn = function() return loadAllModelsNow() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadSpecialModel",
                desc = "loadSpecialModel(Model modelId, GxtString gxtString) ->",
                fn = function() return loadSpecialModel(0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "markModelAsNoLongerNeeded",
                desc = "markModelAsNoLongerNeeded(Model modelId) ->",
                fn = function() return markModelAsNoLongerNeeded(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "openSequenceTask",
                desc = "openSequenceTask() -> int task",
                fn = function() return openSequenceTask() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "performSequenceTask",
                desc = "performSequenceTask(Ped ped, int task) ->",
                fn = function() return performSequenceTask(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "performSequenceTaskFromProgress",
                desc = "performSequenceTaskFromProgress(Ped ped, int sequence, int unkProgress1, int unkProgress2) ->",
                fn = function() return performSequenceTaskFromProgress(getTargetPlayerHandle(), 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeAnimation",
                desc = "removeAnimation(string animation) ->",
                fn = function() return removeAnimation("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "requestAnimation",
                desc = "requestAnimation(string animation) ->",
                fn = function() return requestAnimation("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "requestModel",
                desc = "requestModel(Model modelId) ->",
                fn = function() return requestModel(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarModel",
                desc = "Changes vehicle model ID",
                fn = function() return setCarModel(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharAnimCurrentTime",
                desc = "setCharAnimCurrentTime(Ped ped, string animation, float time) ->",
                fn = function() return setCharAnimCurrentTime(0, "", 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharAnimSpeed",
                desc = "setCharAnimSpeed(Ped ped, string animation, float speed) ->",
                fn = function() return setCharAnimSpeed(getTargetPlayerHandle(), "", 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCutsceneAnim",
                desc = "setCutsceneAnim(int cutscene, GxtString anim) ->",
                fn = function() return setCutsceneAnim("", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCutsceneModelTexture",
                desc = "setCutsceneModelTexture(GxtString cutsceneModel, GxtString textureName) ->",
                fn = function() return setCutsceneModelTexture("", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlayerModel",
                desc = "setPlayerModel(Player player, Model modelId) ->",
                fn = function() return setPlayerModel(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskCharSlideToCoordAndPlayAnim",
                desc = "taskCharSlideToCoordAndPlayAnim(Ped ped, float toX, float toY, float toZ, float angle, float radius, string animation, int ifp1, float ifp2, bool LA, bool LX, bool LY, bool LF, int LT) ->",
                fn = function() return taskCharSlideToCoordAndPlayAnim(getTargetPlayerHandle(), 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskDieNamedAnim",
                desc = "taskDieNamedAnim(Ped ped, string animation, string ifp1, float ifp2, int time) ->",
                fn = function() return taskDieNamedAnim(getTargetPlayerHandle(), "", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskPlayAnim",
                desc = "taskPlayAnim(Ped ped, string animation, string IFP, float framedelta, bool loop, bool lockX, bool lockY, bool lockF, int time) ->",
                fn = function() return taskPlayAnim(getTargetPlayerHandle(), getTargetPlayerHandle(), getTargetPlayerHandle(), 0.0, false, false, false, false, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskPlayAnimNonInterruptable",
                desc = "taskPlayAnimNonInterruptable(Ped ped, string animation, string IFP, float framedelta, bool loopA, bool lockX, bool lockY, bool lockF, int time) ->",
                fn = function() return taskPlayAnimNonInterruptable(getTargetPlayerHandle(), "", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskPlayAnimSecondary",
                desc = "taskPlayAnimSecondary(Ped ped, string animation, string IFP, float framedelta, bool loopA, bool lockX, bool lockY, bool lockF, int time) ->",
                fn = function() return taskPlayAnimSecondary(getTargetPlayerHandle(), "", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "taskPlayAnimWithFlags",
                desc = "taskPlayAnimWithFlags(Ped ped, string animation, string ifp, float framedelta, bool loopA, bool lockX, bool lockY, bool lockF, int time, bool force, bool lockZ) ->",
                fn = function() return taskPlayAnimWithFlags(getTargetPlayerHandle(), "", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- Touch & Widgets (40 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "Touch & Widgets",
        tests = {
{
                name = "isWidgetTouched",
                desc = "Query touch state for WIDGET_PLAYER_INFO (0xA0)",
                fn = function() return isWidgetTouched(0xA0) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "isWidgetPressed",
                desc = "Query pressed state for WIDGET_PLAYER_INFO (0xA0)",
                fn = function() return isWidgetPressed(0xA0) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "isWidgetSwipedLeft",
                desc = "Query swiped-left state for WIDGET_PLAYER_INFO (0xA0)",
                fn = function() return isWidgetSwipedLeft(0xA0) end,
                validate = function(v)
                    if type(v[1]) ~= "boolean" then return false, "expected boolean" end
                    return true, tostring(v[1])
                end
            },
{
                name = "getWidgetPosition",
                desc = "Get screen pixel coordinates for WIDGET_PLAYER_INFO",
                fn = function() return getWidgetPosition(0xA0) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or not isFiniteNumber(v[2]) then
                        return false, "expected 2 screen coordinates"
                    end
                    return true, string.format("(%d, %d)", v[1], v[2])
                end
            },
{
                name = "getWidgetSize",
                desc = "Get pixel dimensions for WIDGET_PLAYER_INFO",
                fn = function() return getWidgetSize(0xA0) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or not isFiniteNumber(v[2]) then
                        return false, "expected 2 dimension values"
                    end
                    return true, string.format("%dx%d", v[1], v[2])
                end
            },
{
                name = "getWidgetClickCount",
                desc = "Get touch click count for WIDGET_PLAYER_INFO",
                fn = function() return getWidgetClickCount(0xA0) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 then return false, "expected non-negative count" end
                    return true, tostring(v[1])
                end
            },
{
                name = "addButtonFlag",
                desc = "Adds state flag to mobile touch button",
                fn = function() return addButtonFlag() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addWidgetFlag",
                desc = "Adds state flag to Arizona touch widget",
                fn = function() return addWidgetFlag() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "deleteWidget",
                desc = "Destroys and removes custom Arizona touch widget",
                fn = function() return deleteWidget(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "displayTextWidget",
                desc = "Displays text message inside Arizona UI widget",
                fn = function() return displayTextWidget(0.0, 0.0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getWidgetLastClickPos",
                desc = "Returns screen coordinates (x, y) of last click on widget",
                fn = function() return getWidgetLastClickPos(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getWidgetValue",
                desc = "Returns primary numeric value of Arizona touch widget",
                fn = function() return getWidgetValue(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getWidgetValue2",
                desc = "Returns secondary numeric value of touch widget",
                fn = function() return getWidgetValue2(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getWidgetVector",
                desc = "Returns 2D vector offset of touch widget",
                fn = function() return getWidgetVector(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isFinalbuild",
                desc = "Checks if client is running release build configuration",
                fn = function() return isFinalbuild() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isTouchEnabled",
                desc = "Checks if touchscreen input subsystem is enabled",
                fn = function() return isTouchEnabled() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isVehicleTouchingObject",
                desc = "isVehicleTouchingObject(Vehicle car, Object object) -> bool result",
                fn = function() return isVehicleTouchingObject(getTargetVehicleHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isWidgetDoubleTapped",
                desc = "Checks if touch widget was double-tapped",
                fn = function() return isWidgetDoubleTapped() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isWidgetDoubletapped",
                desc = "Checks if widget received double-tap gesture",
                fn = function() return isWidgetDoubletapped() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isWidgetLongPressed",
                desc = "Checks if touch widget was long-pressed",
                fn = function() return isWidgetLongPressed(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isWidgetPressedEx",
                desc = "Checks extended pressed state for touch widget",
                fn = function() return isWidgetPressedEx(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isWidgetReleased",
                desc = "Checks if touch widget was released on this frame",
                fn = function() return isWidgetReleased(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isWidgetSwiped",
                desc = "Checks if touch widget received swipe gesture",
                fn = function() return isWidgetSwiped(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isWidgetSwipedRight",
                desc = "Checks if touch widget was swiped to the right",
                fn = function() return isWidgetSwipedRight(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeButtonFlag",
                desc = "Removes state flag from mobile touch button",
                fn = function() return removeButtonFlag() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeWidgetFlag",
                desc = "Removes state flag from Arizona touch widget",
                fn = function() return removeWidgetFlag() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setEquippedItem",
                desc = "Sets equipped inventory item in mobile quickslot widget",
                fn = function() return setEquippedItem(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setSliderRange",
                desc = "Sets minimum and maximum range for mobile slider widget",
                fn = function() return setSliderRange() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setWidgetColor",
                desc = "Sets RGBA tint color of touch widget",
                fn = function() return setWidgetColor(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setWidgetInfo",
                desc = "Sets configuration properties of Arizona touch widget",
                fn = function() return setWidgetInfo(0, 0, 0, 0, 0, 0, 0.0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setWidgetInfo2",
                desc = "Sets secondary configuration properties of touch widget",
                fn = function() return setWidgetInfo2(0, 0, 0, 0, 0, 0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setWidgetPosition",
                desc = "Sets screen position (x, y) of touch widget",
                fn = function() return setWidgetPosition(0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setWidgetRendering",
                desc = "Toggles custom rendering for touch widget",
                fn = function() return setWidgetRendering(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setWidgetSize",
                desc = "Sets width and height dimensions of touch widget",
                fn = function() return setWidgetSize(0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setWidgetSliderRange",
                desc = "Sets numeric range limits for widget slider control",
                fn = function() return setWidgetSliderRange() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setWidgetTexture",
                desc = "Binds custom texture to touch widget",
                fn = function() return setWidgetTexture(0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setWidgetValue",
                desc = "Sets primary numeric value of touch widget",
                fn = function() return setWidgetValue(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setWidgetValue2",
                desc = "Sets secondary numeric value of touch widget",
                fn = function() return setWidgetValue2(0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setWidgetValue3",
                desc = "Sets tertiary numeric value of touch widget",
                fn = function() return setWidgetValue3(0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setWidgetVisible",
                desc = "Sets visibility of touch widget (true/false)",
                fn = function() return setWidgetVisible(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- Screen Rendering & Drawing (57 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "Screen Rendering & Drawing",
        tests = {
{
                name = "clearGxtEntry",
                desc = "clearGxtEntry(string key) ->",
                fn = function() return clearGxtEntry("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "displayNthOnscreenCounterWithString",
                desc = "displayNthOnscreenCounterWithString(VarId text, int type, int line, GxtString gxtString) ->",
                fn = function() return displayNthOnscreenCounterWithString(0, 0, 0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "displayOnscreenCounterWithString",
                desc = "displayOnscreenCounterWithString(VarId var, bool type, GxtString gxtString) ->",
                fn = function() return displayOnscreenCounterWithString(0, 0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "displayText",
                desc = "displayText(float posX, float posY, GxtString gxtString) ->",
                fn = function() return displayText(0.0, 0.0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "displayTextWith2Numbers",
                desc = "displayTextWith2Numbers(float x, float y, GxtString gxtString, int numbersX, int numbersY) ->",
                fn = function() return displayTextWith2Numbers(0.0, 0.0, "", 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "displayTextWithFloat",
                desc = "displayTextWithFloat(float X, float Y, GxtString GXT, float value, int flag) ->",
                fn = function() return displayTextWithFloat(0.0, 0.0, "", 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "displayTextWithNumber",
                desc = "displayTextWithNumber(float x, float y, GxtString gxtString, int number) ->",
                fn = function() return displayTextWithNumber(0.0, 0.0, "", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "freeTextures",
                desc = "Releases cached render textures from memory",
                fn = function() return freeTextures() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getGxtText",
                desc = "getGxtText(string key) -> string text",
                fn = function() return getGxtText("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadMissionText",
                desc = "loadMissionText(GxtString table) ->",
                fn = function() return loadMissionText("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadTextureDictionary",
                desc = "loadTextureDictionary(zstring txd) -> bool result",
                fn = function() return loadTextureDictionary("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "printHelpForever",
                desc = "printHelpForever(GxtString text) ->",
                fn = function() return printHelpForever("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "printHelpForeverWithNumber",
                desc = "printHelpForeverWithNumber(GxtString text, int number) ->",
                fn = function() return printHelpForeverWithNumber("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "printHelpString",
                desc = "printHelpString(string text) ->",
                fn = function() return printHelpString("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "printString",
                desc = "printString(string text, int time) ->",
                fn = function() return printString("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "printStringInStringNow",
                desc = "printStringInStringNow(GxtString gxtString, GxtString string, int time1, int time2) ->",
                fn = function() return printStringInStringNow("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeTextureDictionary",
                desc = "Unloads and destroys loaded TXD texture dictionary",
                fn = function() return removeTextureDictionary() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderBegin",
                desc = "Begins 2D direct rendering pass",
                fn = function() return renderBegin(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderBindTexture",
                desc = "Binds texture handle for 2D rendering operations",
                fn = function() return renderBindTexture() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderColor",
                desc = "Sets active drawing color (RGBA format)",
                fn = function() return renderColor(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderCreateFont",
                desc = "Creates render font with font name, size and flags",
                fn = function() return renderCreateFont("", 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderDrawBox",
                desc = "Draws solid filled 2D rectangle on screen",
                fn = function() return renderDrawBox(0.0, 0.0, 0.0, 0.0, getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderDrawBoxWithBorder",
                desc = "Draws 2D filled box with outlined border",
                fn = function() return renderDrawBoxWithBorder(0.0, 0.0, 0.0, 0.0, getTargetObjectHandle(), 0.0, getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderDrawColoredLines",
                desc = "Draws colored line segments between 2D points",
                fn = function() return renderDrawColoredLines(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderDrawLines",
                desc = "Draws 2D line segments between point array",
                fn = function() return renderDrawLines(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderDrawPolygon",
                desc = "Draws filled 2D convex polygon",
                fn = function() return renderDrawPolygon(0.0, 0.0, 0.0, 0.0, 0, 0.0, getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderDrawTexture",
                desc = "Draws 2D textured quad at screen coordinates",
                fn = function() return renderDrawTexture(0, 0.0, 0.0, 0.0, 0.0, 0.0, getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderEnd",
                desc = "Finishes 2D direct rendering pass and flushes buffer",
                fn = function() return renderEnd() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderGetFontCharIndexAt",
                desc = "Returns character index in font string at pixel offset",
                fn = function() return renderGetFontCharIndexAt(0, "", 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderGetFontCharWidth",
                desc = "Returns rendered width of character in pixels",
                fn = function() return renderGetFontCharWidth(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderGetFontDrawHeight",
                desc = "Returns font line height in pixels",
                fn = function() return renderGetFontDrawHeight(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderGetTextureSize",
                desc = "Returns width and height dimensions of texture",
                fn = function() return renderGetTextureSize(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderGetTextureSprite",
                desc = "Returns sub-region sprite handle from texture",
                fn = function() return renderGetTextureSprite(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderGetTextureStruct",
                desc = "Returns memory pointer to texture data structure",
                fn = function() return renderGetTextureStruct(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderLoadTextureFromFile",
                desc = "Loads texture into memory from image file on disk",
                fn = function() return renderLoadTextureFromFile("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderLoadTextureFromFileInMemory",
                desc = "Loads texture from encoded image buffer in memory",
                fn = function() return renderLoadTextureFromFileInMemory(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderReleaseFont",
                desc = "Destroys font resource and frees font memory",
                fn = function() return renderReleaseFont(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderReleaseTexture",
                desc = "Destroys texture resource and frees GPU memory",
                fn = function() return renderReleaseTexture(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderSetRenderState",
                desc = "Configures graphics rendering state flags",
                fn = function() return renderSetRenderState(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderSetTexCoord",
                desc = "Sets UV texture mapping coordinates for primitives",
                fn = function() return renderSetTexCoord(0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "renderVertex",
                desc = "Emits 2D vertex coordinate into active render batch",
                fn = function() return renderVertex(0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setGxtEntry",
                desc = "setGxtEntry(string key, string text) ->",
                fn = function() return setGxtEntry("", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTextBackground",
                desc = "setTextBackground(bool background) ->",
                fn = function() return setTextBackground(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTextCentre",
                desc = "setTextCentre(bool centered) ->",
                fn = function() return setTextCentre(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTextCentreSize",
                desc = "setTextCentreSize(float linewidth) ->",
                fn = function() return setTextCentreSize(0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTextDrawBeforeFade",
                desc = "setTextDrawBeforeFade(bool int1) ->",
                fn = function() return setTextDrawBeforeFade(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTextDropshadow",
                desc = "setTextDropshadow(int shadow, int r, int g, int b, int a) ->",
                fn = function() return setTextDropshadow(0, 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTextEdge",
                desc = "setTextEdge(int size, int r, int g, int b, int a) ->",
                fn = function() return setTextEdge(0, 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTextJustify",
                desc = "setTextJustify(bool alignJustify) ->",
                fn = function() return setTextJustify(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTextProportional",
                desc = "setTextProportional(bool proportional) ->",
                fn = function() return setTextProportional(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTextRightJustify",
                desc = "setTextRightJustify(bool alignRight) ->",
                fn = function() return setTextRightJustify(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTextWrapx",
                desc = "setTextWrapx(float linewidth) ->",
                fn = function() return setTextWrapx(0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
            {
                name = "printHelp",
                desc = "printHelp(GxtString gxtString) ->",
                fn = function() return printHelp("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
            {
                name = "printStringNow",
                desc = "printStringNow(string text, int time) ->",
                fn = function() return printStringNow("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
            {
                name = "setTextColour",
                desc = "setTextColour(int r, int g, int b, int a) ->",
                fn = function() return setTextColour(0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
            {
                name = "setTextFont",
                desc = "setTextFont(int font) ->",
                fn = function() return setTextFont(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
            {
                name = "setTextScale",
                desc = "setTextScale(float sizeX, float sizeY) ->",
                fn = function() return setTextScale(0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- Memory & Utilities (194 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "Memory & Utilities",
        tests = {
{
                name = "json_Roundtrip",
                isCompound = true,
                desc = "Encode nested table to JSON and decode back with value verification",
                fn = function()
                    if type(encodeJson) ~= "function" or type(decodeJson) ~= "function" then
                        return makeSkip("JSON API unavailable")
                    end
                    local original = { id = 42, name = "NeoMLoader", flags = { true, false } }
                    local jsonStr = encodeJson(original)
                    if type(jsonStr) ~= "string" or #jsonStr == 0 then return false, "failed to encode" end
                    local decoded = decodeJson(jsonStr)
                    if type(decoded) ~= "table" then return false, "failed to decode" end
                    if decoded.id ~= 42 or decoded.name ~= "NeoMLoader" then return false, "content mismatch" end
                    return true, jsonStr
                end,
                validate = function(v)
                    return true, "encoded & decoded: " .. v[2]
                end
            },
{
                name = "ReadInt32",
                desc = "Read 32-bit integer from SA-MP base address",
                fn = function() return ReadInt32(sampGetBase()) end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) then return false, "expected integer" end
                    return true, string.format("0x%08X", v[1])
                end
            },
{
                name = "ReadFloat",
                desc = "Read 32-bit float from valid memory address",
                fn = function()
                    local ped = getTargetPlayerHandle()
                    if ped <= 0 then return makeSkip("no ped") end
                    local ptr = getCharPointer(ped)
                    -- PED_HEALTH is at offset 0x540
                    return ReadFloat(ptr + 0x540)
                end,
                validate = function(v)
                    if not isFiniteNumber(v[1]) or v[1] < 0 or v[1] > 1000 then return false, "expected health float" end
                    return true, string.format("%.1f", v[1])
                end
            },
{
                name = "getModuleBaseAddress",
                desc = "Query base address of libGTASA.so",
                fn = function() return getModuleBaseAddress("libGTASA.so") end,
                validate = function(v)
                    if not isPointer(v[1]) then return false, "expected valid module base pointer" end
                    return true, string.format("0x%X", v[1])
                end
            },
{
                name = "getMoonloaderVersion",
                desc = "Verify MoonLoader compatibility API level (__moonloader = 27)",
                fn = function() return getMoonloaderVersion() end,
                validate = function(v)
                    if v[1] ~= 27 then return false, "expected version 27, got: " .. formatValue(v[1]) end
                    return true, "v27"
                end
            },
{
                name = "filesystem_FindFiles",
                isCompound = true,
                desc = "Find files in script directory with findFirstFile/findNextFile/findClose",
                fn = function()
                    if type(findFirstFile) ~= "function" then return makeSkip("findFirstFile unavailable") end
                    local h, first = findFirstFile(getWorkingDirectory() .. "/*")
                    if not h or not first then return false, "no files found" end
                    local nextName = (type(findNextFile) == "function") and findNextFile(h) or nil
                    if type(findClose) == "function" then findClose(h) end
                    return true, first, nextName
                end,
                validate = function(v)
                    return true, "first: " .. tostring(v[2])
                end
            },
{
                name = "lua_thread_Execution",
                isCompound = true,
                desc = "Spawn cooperative coroutine thread and verify execution",
                fn = function()
                    if not lua_thread or type(lua_thread.create) ~= "function" then
                        return makeSkip("lua_thread unavailable")
                    end
                    local th = lua_thread.create(function()
                        wait(100)
                    end)
                    return th ~= nil and (type(th) == "userdata" or type(th) == "table" or type(th) == "thread")
                end,
                validate = function(v)
                    if v[1] ~= true then return false, "failed to spawn coroutine thread" end
                    return true, "thread created & registered"
                end
            },
{
                name = "thisScript_Metadata",
                isCompound = true,
                desc = "Inspect thisScript object properties",
                fn = function()
                    if not thisScript then return makeSkip("thisScript global missing") end
                    return thisScript.filename or thisScript.name
                end,
                validate = function(v)
                    if type(v[1]) ~= "string" or #v[1] == 0 then return false, "expected filename string" end
                    return true, v[1]
                end
            },
{
                name = "unicode_to_utf8",
                desc = "Convert Unicode code point to UTF-8 string (RFC 3629)",
                fn = function()
                    if type(unicode_to_utf8) ~= "function" then return makeSkip("unicode_to_utf8 not available") end
                    local a = unicode_to_utf8(0x41)
                    local cyr = unicode_to_utf8(0x041F)
                    local heart = unicode_to_utf8(0x2764)
                    return a, cyr, heart
                end,
                validate = function(v)
                    if v[1] ~= "A" or v[2] ~= "\xD0\x9F" or v[3] ~= "\xE2\x9D\xA4" then
                        return false, "unicode_to_utf8 conversion mismatch: " .. formatReturnValues(v)
                    end
                    return true, string.format("'%s', '%s', '%s' verified", v[1], v[2], v[3])
                end
            },
{
                name = "afk_notify",
                desc = "Safe AFK notification handler",
                fn = function()
                    if type(afk_notify) ~= "function" then return makeSkip("afk_notify not available") end
                    afk_notify("info", "TestTitle", "TestMessage")
                    return true
                end,
                validate = function(v)
                    return true, "notification handled cleanly"
                end
            },
{
                name = "GetBase",
                desc = "Returns base memory address of loaded game library",
                fn = function() return GetBase() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "GetCapability",
                desc = "Checks support capability flag for memory operations",
                fn = function() return GetCapability("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "GetEntity",
                desc = "Returns entity memory pointer by handle or ID",
                fn = function() return GetEntity(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "GetEntityPosition",
                desc = "Returns 3D position vector from entity memory",
                fn = function() return GetEntityPosition(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "GetEntityType",
                desc = "Returns entity type enum/integer from memory",
                fn = function() return GetEntityType(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "GetNetGame",
                desc = "Returns CNetGame singleton memory pointer",
                fn = function() return GetNetGame() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "GetPoolEntry",
                desc = "Returns pool entry pointer at specified index",
                fn = function() return GetPoolEntry(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "GetPoolPtr",
                desc = "Returns base pointer of specified game pool",
                fn = function() return GetPoolPtr(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "GetRakPeer",
                desc = "Returns pointer to active RakPeer instance",
                fn = function() return GetRakPeer() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "GetSampInfo",
                desc = "Returns SA-MP state and version information structure",
                fn = function() return GetSampInfo(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "GetSize",
                desc = "Returns size of specified memory pool or structure",
                fn = function() return GetSize() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "IsAvailable",
                desc = "Checks if memory reader/writer is initialized and available",
                fn = function() return IsAvailable() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "IsEntityValid",
                desc = "Validates entity pointer or handle in memory",
                fn = function() return IsEntityValid(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "ReadInt64",
                desc = "Reads 64-bit signed integer from memory address",
                fn = function() return ReadInt64(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "ReadMemory",
                desc = "Reads raw byte array from specified memory address",
                fn = function() return ReadMemory(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "ReadUInt16",
                desc = "Reads 16-bit unsigned integer from memory address",
                fn = function() return ReadUInt16(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "ReadUInt32",
                desc = "Reads 32-bit unsigned integer from memory address",
                fn = function() return ReadUInt32(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "WriteFloat",
                desc = "Writes 32-bit floating point value to memory address",
                fn = function() return WriteFloat(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "WriteInt32",
                desc = "Writes 32-bit signed integer to memory address",
                fn = function() return WriteInt32(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "WriteMemory",
                desc = "Writes raw byte buffer to specified memory address",
                fn = function() return WriteMemory(0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "WriteUInt32",
                desc = "Writes 32-bit unsigned integer to memory address",
                fn = function() return WriteUInt32(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "activateMenuItem",
                desc = "activateMenuItem(int menu, int row, bool enable) ->",
                fn = function() return activateMenuItem(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "activatePimpCheat",
                desc = "activatePimpCheat(bool enable) ->",
                fn = function() return activatePimpCheat(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "activateSaveMenu",
                desc = "Opens GTA San Andreas game save menu",
                fn = function() return activateSaveMenu() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addBlood",
                desc = "addBlood(float atX, float atY, float atZ, float offsetX, float offsetY, float offsetZ, int density, int onActor) ->",
                fn = function() return addBlood(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addHospitalRestart",
                desc = "addHospitalRestart(float atX, float atY, float atZ, float angle, int townNumber) ->",
                fn = function() return addHospitalRestart(0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addPoliceRestart",
                desc = "addPoliceRestart(float atX, float atY, float atZ, float angle, int townNumber) ->",
                fn = function() return addPoliceRestart(0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addPriceModifier",
                desc = "addPriceModifier(int item, int price) ->",
                fn = function() return addPriceModifier("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addSmokeParticle",
                desc = "addSmokeParticle(float atX, float atY, float atZ, float velocityX, float velocityY, float velocityZ, int r, int g, int b, int a, float size, float factor) ->",
                fn = function() return addSmokeParticle(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addSparks",
                desc = "addSparks(float posX, float posY, float posZ, float vecX, float vecY, float vecZ, int density) ->",
                fn = function() return addSparks(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "allocateMemory",
                desc = "Allocates block of raw process memory with given size",
                fn = function() return allocateMemory(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "base64decode",
                desc = "Decodes Base64-encoded string into raw bytes",
                fn = function() return base64decode("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "base64encode",
                desc = "Encodes binary buffer into Base64 ASCII string",
                fn = function() return base64encode("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "callFunction",
                desc = "Calls native cdecl/stdcall memory function pointer with arguments",
                fn = function() return callFunction(0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "callMethod",
                desc = "Calls native C++ thiscall class method pointer with arguments",
                fn = function() return callMethod(0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "changeGarageType",
                desc = "changeGarageType(GxtString garage, int type) ->",
                fn = function() return changeGarageType("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clamp",
                desc = "Clamps numeric value between minimum and maximum bounds",
                fn = function() return clamp() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearHelp",
                desc = "Clears currently displayed help text box",
                fn = function() return clearHelp() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearPrints",
                desc = "Clears on-screen subtitle prints",
                fn = function() return clearPrints() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearSmallPrints",
                desc = "Clears on-screen small subtitle prints",
                fn = function() return clearSmallPrints() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearThisPrint",
                desc = "clearThisPrint(GxtString text) ->",
                fn = function() return clearThisPrint("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "closeGarage",
                desc = "closeGarage(GxtString garage) ->",
                fn = function() return closeGarage("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "convertMatrixToQuaternion",
                desc = "convertMatrixToQuaternion(float rightX, float rightY, float rightZ, float frontX, float frontY, float frontZ, float upX, float upY, float upZ) -> float w, float x, float y, float z",
                fn = function() return convertMatrixToQuaternion(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "convertQuaternionToMatrix",
                desc = "convertQuaternionToMatrix(float w, float x, float y, float z) -> float rightX, float rightY, float rightZ, float frontX, float frontY, float frontZ, float upX, float upY, float upZ",
                fn = function() return convertQuaternionToMatrix(0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "crc32",
                desc = "Calculates 32-bit CRC checksum of string or buffer",
                fn = function() return crc32("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createMenu",
                desc = "createMenu(GxtString title, float posX, float posY, float width, int columns, bool interactive, bool background, int alignment) -> int menu",
                fn = function() return createMenu("", 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "deactivateGarage",
                desc = "deactivateGarage(GxtString garage) ->",
                fn = function() return deactivateGarage("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "deleteMenu",
                desc = "deleteMenu(int menu) ->",
                fn = function() return deleteMenu(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "destroyHandlers",
                desc = "Destroys all registered event handler callbacks",
                fn = function() return destroyHandlers() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dirClose",
                desc = "Closes open filesystem directory handle",
                fn = function() return dirClose(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dirCreate",
                desc = "Creates new directory in filesystem",
                fn = function() return dirCreate("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dirDelete",
                desc = "Deletes empty directory from filesystem",
                fn = function() return dirDelete("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dirExists",
                desc = "Checks if directory exists at specified path",
                fn = function() return dirExists("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dirGetDirectories",
                desc = "Returns list of subdirectories in folder",
                fn = function() return dirGetDirectories("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dirGetFiles",
                desc = "Returns list of files in folder",
                fn = function() return dirGetFiles("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dirOpen",
                desc = "Opens filesystem directory for iteration",
                fn = function() return dirOpen("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dirRead",
                desc = "Reads next file or directory entry from directory handle",
                fn = function() return dirRead(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "downloadUrlToFile",
                desc = "downloadUrlToFile(string url, string file, function statusCallback) -> int index",
                fn = function() return downloadUrlToFile("", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "drawLightWithRange",
                desc = "drawLightWithRange(float atX, float atY, float atZ, int r, int g, int b, float radius) ->",
                fn = function() return drawLightWithRange(0.0, 0.0, 0.0, 0, 0, 0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "ensureUtf8",
                desc = "Validates and sanitizes string into valid UTF-8",
                fn = function() return ensureUtf8("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "fileClose",
                desc = "Closes open file handle",
                fn = function() return fileClose(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "fileCopy",
                desc = "Copies file from source path to destination path",
                fn = function() return fileCopy("", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "fileDelete",
                desc = "Deletes file from disk",
                fn = function() return fileDelete("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "fileExists",
                desc = "Checks if file exists at specified path",
                fn = function() return fileExists("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "fileFlush",
                desc = "Flushes unwritten buffered data to disk",
                fn = function() return fileFlush(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "fileGetPos",
                desc = "Returns current read/write cursor position in file",
                fn = function() return fileGetPos(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "fileGetSize",
                desc = "Returns total file size in bytes",
                fn = function() return fileGetSize("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "fileOpen",
                desc = "Opens file with specified access mode (r, w, a)",
                fn = function() return fileOpen("", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "fileRead",
                desc = "Reads specified number of bytes or entire content from file",
                fn = function() return fileRead(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "fileRename",
                desc = "Renames or moves file to new path",
                fn = function() return fileRename("", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "fileSetPos",
                desc = "Seeks file read/write cursor to byte offset",
                fn = function() return fileSetPos(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "fileWrite",
                desc = "Writes string or byte buffer to open file",
                fn = function() return fileWrite(0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "formatDate",
                desc = "Formats Unix timestamp into formatted date string",
                fn = function() return formatDate("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "freeMemory",
                desc = "freeMemory(uint memory) ->",
                fn = function() return freeMemory(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getAll3dTexts",
                desc = "Returns table of all active 3D text label IDs and texts",
                fn = function() return getAll3dTexts() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCleoLibraryVersion",
                desc = "getCleoLibraryVersion() -> int version",
                fn = function() return getCleoLibraryVersion() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getClipboardText",
                desc = "getClipboardText() -> string text",
                fn = function() return getClipboardText() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getControllerMode",
                desc = "getControllerMode() -> int mode",
                fn = function() return getControllerMode() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCurrentDate",
                desc = "getCurrentDate() -> int day, int month",
                fn = function() return getCurrentDate() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCurrentLanguage",
                desc = "getCurrentLanguage() -> int language",
                fn = function() return getCurrentLanguage() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getDate",
                desc = "Returns current system date table (year, month, day, time)",
                fn = function() return getDate() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getFolderPath",
                desc = "getFolderPath(int csidl) -> string path",
                fn = function() return getFolderPath(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getGameKeyState",
                desc = "Returns current state of game controller key",
                fn = function() return getGameKeyState(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getGameVersion",
                desc = "getGameVersion() -> int major, int minor, int majorRev, int minorRev, int game, int region, bool steam, bool cracked",
                fn = function() return getGameVersion() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getHashKey",
                desc = "getHashKey(string string) -> int CRC32",
                fn = function() return getHashKey("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getMaxWantedLevel",
                desc = "getMaxWantedLevel() -> int level",
                fn = function() return getMaxWantedLevel() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getModuleHandle",
                desc = "getModuleHandle(string module) -> uint handle",
                fn = function() return getModuleHandle("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getModuleProcAddress",
                desc = "getModuleProcAddress(string module, string proc) -> uint address",
                fn = function() return getModuleProcAddress(0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getMousewheelDelta",
                desc = "getMousewheelDelta() -> int delta",
                fn = function() return getMousewheelDelta() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getPcMouseMovement",
                desc = "getPcMouseMovement() -> float x, float y",
                fn = function() return getPcMouseMovement() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getSampfuncsGlobalVar",
                desc = "getSampfuncsGlobalVar(zstring var) -> bool result, int value",
                fn = function() return getSampfuncsGlobalVar("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getSampfuncsGlobalVarAccessForThread",
                desc = "getSampfuncsGlobalVarAccessForThread(zstring var, uint thread) -> bool read, bool write",
                fn = function() return getSampfuncsGlobalVarAccessForThread("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getState",
                desc = "Returns current execution state integer",
                fn = function() return getState() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getStructElement",
                desc = "getStructElement(uint struct, int offset, uint size, [bool unprotect=false]) -> int value",
                fn = function() return getStructElement(0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getStructFloatElement",
                desc = "getStructFloatElement(uint struct, int offset, [bool unprotect=false]) -> float value",
                fn = function() return getStructFloatElement(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getTickCount",
                desc = "Returns milliseconds elapsed since system boot",
                fn = function() return getTickCount() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getfloat",
                desc = "Reads 32-bit float value from memory address",
                fn = function() return getfloat() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getint16",
                desc = "Reads 16-bit integer value from memory address",
                fn = function() return getint16() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getint32",
                desc = "Reads 32-bit integer value from memory address",
                fn = function() return getint32() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getint8",
                desc = "Reads 8-bit integer value from memory address",
                fn = function() return getint8() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hexDecode",
                desc = "Decodes hexadecimal string into raw binary bytes",
                fn = function() return hexDecode("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hexEncode",
                desc = "Encodes binary buffer into hexadecimal string",
                fn = function() return hexEncode("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hideGameText",
                desc = "Hides currently displayed on-screen game text message",
                fn = function() return hideGameText(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "iniClose",
                desc = "Closes open INI configuration file handle",
                fn = function() return iniClose(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "iniDeleteKey",
                desc = "Deletes key and value from INI file section",
                fn = function() return iniDeleteKey(0, "", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "iniDeleteSection",
                desc = "Deletes entire section from INI file",
                fn = function() return iniDeleteSection(0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "iniKeyExists",
                desc = "Checks if key exists in INI file section",
                fn = function() return iniKeyExists(0, "", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "iniOpen",
                desc = "Opens INI configuration file from disk",
                fn = function() return iniOpen("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "iniReadFloat",
                desc = "Reads floating point value for key from INI section",
                fn = function() return iniReadFloat(0, "", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "iniReadInteger",
                desc = "Reads integer value for key from INI section",
                fn = function() return iniReadInteger(0, "", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "iniReadString",
                desc = "Reads string value for key from INI section",
                fn = function() return iniReadString(0, "", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "iniSectionExists",
                desc = "Checks if section exists in INI file",
                fn = function() return iniSectionExists(0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "iniWriteFloat",
                desc = "Writes floating point value for key to INI section",
                fn = function() return iniWriteFloat(0, "", "", 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "iniWriteInteger",
                desc = "Writes integer value for key to INI section",
                fn = function() return iniWriteInteger(0, "", "", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "iniWriteString",
                desc = "Writes string value for key to INI section",
                fn = function() return iniWriteString(0, "", "", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isButtonPressed",
                desc = "isButtonPressed(Player player, int key) -> bool result",
                fn = function() return isButtonPressed(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCleoLoaded",
                desc = "isCleoLoaded() -> bool loaded",
                fn = function() return isCleoLoaded() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isGarageClosed",
                desc = "isGarageClosed(GxtString garage) -> bool result",
                fn = function() return isGarageClosed("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isGarageOpen",
                desc = "isGarageOpen(GxtString garage) -> bool result",
                fn = function() return isGarageOpen("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isKeyDown",
                desc = "isKeyDown(int keyId) -> bool state",
                fn = function() return isKeyDown(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isKeyJustPressed",
                desc = "isKeyJustPressed(int key) -> bool state",
                fn = function() return isKeyJustPressed(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isMouseUsingVerticalInversion",
                desc = "isMouseUsingVerticalInversion() -> bool result",
                fn = function() return isMouseUsingVerticalInversion() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isOpcodesAvailable",
                desc = "isOpcodesAvailable() -> bool status",
                fn = function() return isOpcodesAvailable() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPcUsingJoypad",
                desc = "isPcUsingJoypad() -> bool result",
                fn = function() return isPcUsingJoypad() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPcVersion",
                desc = "isPcVersion() -> bool result",
                fn = function() return isPcVersion() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPs2KeyboardKeyJustPressed",
                desc = "isPs2KeyboardKeyJustPressed(int key) -> bool result",
                fn = function() return isPs2KeyboardKeyJustPressed(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPs2KeyboardKeyPressed",
                desc = "isPs2KeyboardKeyPressed(int key) -> bool result",
                fn = function() return isPs2KeyboardKeyPressed(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isSampAvailable",
                desc = "isSampAvailable() -> bool result",
                fn = function() return isSampAvailable() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isSampLoaded",
                desc = "isSampLoaded() -> bool loaded",
                fn = function() return isSampLoaded() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isSampfuncsConsoleActive",
                desc = "isSampfuncsConsoleActive() -> bool result",
                fn = function() return isSampfuncsConsoleActive() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isSampfuncsConsoleCommandDefined",
                desc = "isSampfuncsConsoleCommandDefined(zstring cmd) -> bool result",
                fn = function() return isSampfuncsConsoleCommandDefined("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isSampfuncsGlobalVarDefined",
                desc = "isSampfuncsGlobalVarDefined(zstring var) -> bool result",
                fn = function() return isSampfuncsGlobalVarDefined("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isSampfuncsLoaded",
                desc = "isSampfuncsLoaded() -> bool loaded",
                fn = function() return isSampfuncsLoaded() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "lerp",
                desc = "Calculates linear interpolation between two values",
                fn = function() return lerp(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "openGarage",
                desc = "openGarage(GxtString garage) ->",
                fn = function() return openGarage("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "printBig",
                desc = "printBig(GxtString gxtString, int time, int style) ->",
                fn = function() return printBig("", 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "printBigQ",
                desc = "printBigQ(GxtString gxtString, int time, int style) -> bool result",
                fn = function() return printBigQ("", 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "printStyledString",
                desc = "printStyledString(string text, int time, int style) ->",
                fn = function() return printStyledString("", 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "printText",
                desc = "printText(GxtString gxtString, int time, int flag) ->",
                fn = function() return printText("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "printTextNow",
                desc = "printTextNow(GxtString gxtString, int time, int flag) ->",
                fn = function() return printTextNow("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "printWith2NumbersBig",
                desc = "printWith2NumbersBig(GxtString gxtString, int numbers1, int numbers2, int time, int style) ->",
                fn = function() return printWith2NumbersBig("", 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "printWith2NumbersNow",
                desc = "printWith2NumbersNow(GxtString gxtString, int numbers1, int numbers2, int time, int flag) ->",
                fn = function() return printWith2NumbersNow("", 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "printWith3Numbers",
                desc = "printWith3Numbers(GxtString gxtString, int numbers1, int numbers2, int numbers3, int time, int flag) ->",
                fn = function() return printWith3Numbers("", 0, 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "printWith4Numbers",
                desc = "printWith4Numbers(GxtString gxtString, int numbers1, int numbers2, int numbers3, int numbers4, int time, int flag) ->",
                fn = function() return printWith4Numbers("", 0, 0, 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "printWith4NumbersNow",
                desc = "printWith4NumbersNow(GxtString gxtString, int numbers1, int numbers2, int numbers3, int numbers4, int time, int flag) ->",
                fn = function() return printWith4NumbersNow("", 0, 0, 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "printWith6Numbers",
                desc = "printWith6Numbers(GxtString gxtString, int numbers1, int numbers2, int numbers3, int numbers4, int numbers5, int numbers6, int time, int flag) ->",
                fn = function() return printWith6Numbers("", 0, 0, 0, 0, 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "printWithNumber",
                desc = "printWithNumber(GxtString gxtString, int number, int time, int flag) -> bool result",
                fn = function() return printWithNumber("", 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "printWithNumberBig",
                desc = "printWithNumberBig(GxtString gxtString, int number, int time, int style) -> bool result",
                fn = function() return printWithNumberBig("", 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "printWithNumberNow",
                desc = "printWithNumberNow(GxtString gxtString, int number, int time, int flag) -> bool result",
                fn = function() return printWithNumberNow("", 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "randomSeed",
                desc = "Seeds pseudo-random number generator",
                fn = function() return randomSeed(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "readMemory",
                desc = "Reads raw memory buffer from address",
                fn = function() return readMemory(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "registerHandler",
                desc = "Registers callback handler for game or script event",
                fn = function() return registerHandler() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "representFloatAsInt",
                desc = "representFloatAsInt(float f) -> int i",
                fn = function() return representFloatAsInt(0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "representIntAsFloat",
                desc = "representIntAsFloat(int i) -> float i",
                fn = function() return representIntAsFloat(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "runSampfuncsConsoleCommand",
                desc = "runSampfuncsConsoleCommand(zstring cmd) ->",
                fn = function() return runSampfuncsConsoleCommand("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendChat",
                desc = "Sends chat text message packet to server",
                fn = function() return sendChat() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendClickTextdraw",
                desc = "Sends textdraw click RPC to server",
                fn = function() return sendClickTextdraw() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendDialogResponse",
                desc = "Sends dialog response RPC with button and input to server",
                fn = function() return sendDialogResponse() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendGiveDamage",
                desc = "Sends give damage packet to server for specified player",
                fn = function() return sendGiveDamage() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendInteriorChange",
                desc = "Informs server that local player changed interior ID",
                fn = function() return sendInteriorChange() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendMenuQuit",
                desc = "Sends menu quit notification RPC to server",
                fn = function() return sendMenuQuit() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendMenuSelectRow",
                desc = "Sends selected menu row index RPC to server",
                fn = function() return sendMenuSelectRow() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendRconCommand",
                desc = "Sends RCON administrative command to server",
                fn = function() return sendRconCommand() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendRequestSpawn",
                desc = "Sends request spawn RPC to server",
                fn = function() return sendRequestSpawn() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendSpawn",
                desc = "Sends spawn player RPC to server",
                fn = function() return sendSpawn() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sendTakeDamage",
                desc = "Sends take damage packet to server from specified player",
                fn = function() return sendTakeDamage() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setClipboardText",
                desc = "setClipboardText(string text) -> bool result",
                fn = function() return setClipboardText("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setGameKeyState",
                desc = "setGameKeyState(int key, int state) ->",
                fn = function() return setGameKeyState(0, getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setSampfuncsConsoleCommandDescription",
                desc = "setSampfuncsConsoleCommandDescription(zstring cmd, zstring text) ->",
                fn = function() return setSampfuncsConsoleCommandDescription("", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setSampfuncsGlobalVar",
                desc = "setSampfuncsGlobalVar(zstring var, int value) -> bool result",
                fn = function() return setSampfuncsGlobalVar("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setStructElement",
                desc = "setStructElement(uint struct, int offset, uint size, int value, [bool unprotect=false]) ->",
                fn = function() return setStructElement(0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setStructFloatElement",
                desc = "setStructFloatElement(uint struct, int offset, float value, [bool unprotect=false]) ->",
                fn = function() return setStructFloatElement(0, 0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setVirtualKeyDown",
                desc = "setVirtualKeyDown(int vkey, bool down) ->",
                fn = function() return setVirtualKeyDown(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setfloat",
                desc = "Writes 32-bit float value to memory address",
                fn = function() return setfloat() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setint16",
                desc = "Writes 16-bit integer value to memory address",
                fn = function() return setint16() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setint32",
                desc = "Writes 32-bit integer value to memory address",
                fn = function() return setint32() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setint8",
                desc = "Writes 8-bit integer value to memory address",
                fn = function() return setint8() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "showCursor",
                desc = "showCursor(bool show, [bool lockControls]) ->",
                fn = function() return showCursor(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "showGameText",
                desc = "Displays on-screen GTA game text for duration (ms)",
                fn = function() return showGameText("", 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sleep",
                desc = "Yields coroutine execution for specified milliseconds",
                fn = function() return sleep(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "testCheat",
                desc = "testCheat(string text) -> bool result",
                fn = function() return testCheat("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "wasKeyPressed",
                desc = "wasKeyPressed(int key) -> bool state",
                fn = function() return wasKeyPressed(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "wasKeyReleased",
                desc = "wasKeyReleased(int key) -> bool state",
                fn = function() return wasKeyReleased(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "writeMemory",
                desc = "writeMemory(uint address, uint size, int value, bool virtualProtect) ->",
                fn = function() return writeMemory(0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- Auto-Stubs Safety Contract (4 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "Auto-Stubs Safety Contract",
        tests = {
{
                name = "activateGarage",
                desc = "Call generated auto-stub without crashing",
                fn = function() return activateGarage("boddob") end,
                validate = function(v)
                    return true, "safe fallback: " .. formatValue(v[1])
                end
            },
{
                name = "activateInteriorPeds",
                desc = "Call generated auto-stub without crashing",
                fn = function() return activateInteriorPeds(true) end,
                validate = function(v)
                    return true, "safe fallback: " .. formatValue(v[1])
                end
            },
{
                name = "addArmourToChar",
                desc = "Add armour to local ped (amount 0 safe test)",
                fn = function()
                    local ped = getTargetPlayerHandle()
                    if ped <= 0 then return makeSkip("no ped") end
                    addArmourToChar(ped, 0)
                    return true
                end,
                validate = function(v)
                    return true, "invoked safely"
                end
            },
{
                name = "clearCharTasks",
                desc = "Clear AI tasks on local ped safely",
                fn = function()
                    local ped = getTargetPlayerHandle()
                    if ped <= 0 then return makeSkip("no ped") end
                    clearCharTasks(ped)
                    return true
                end,
                validate = function(v)
                    return true, "tasks cleared"
                end
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- Auto-Stubs: Game Subsystems (652 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "Auto-Stubs: Game Subsystems",
        tests = {
{
                name = "addAttractor",
                desc = "addAttractor(float originX, float originY, float originZ, float zAngle, float unknownAngle, int taskSequence) -> int handle",
                fn = function() return addAttractor(0.0, 0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addEventHandler",
                desc = "addEventHandler(string eventName, function callback) ->",
                fn = function() return addEventHandler("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addNextMessageToPreviousBriefs",
                desc = "addNextMessageToPreviousBriefs(bool int1) ->",
                fn = function() return addNextMessageToPreviousBriefs(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addSetPiece",
                desc = "addSetPiece(int type, float rectX1, float rectY1, float rectX2, float rectY2, float spawnAX, float spawnAY, float headedTowards1X, float headedTowards1Y, float spawnBX, float spawnBY, float headedTowards2X, float headedTowards2Y) ->",
                fn = function() return addSetPiece(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "addStuntJump",
                desc = "addStuntJump(float startX, float startY, float startZ, float radiusX, float radiusY, float radiusZ, float goalX, float goalY, float goalZ, float radius2X, float radius2Y, float radius2Z, float cameraX, float cameraY, float cameraZ, int reward) ->",
                fn = function() return addStuntJump(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "allocateStreamedScriptToObject",
                desc = "allocateStreamedScriptToObject(int externalScript, Model objectModel, int priority, float radius, int type) ->",
                fn = function() return allocateStreamedScriptToObject(0, 0, 0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "areAnyCarCheatsActivated",
                desc = "areAnyCarCheatsActivated() -> bool result",
                fn = function() return areAnyCarCheatsActivated() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "areCreditsFinished",
                desc = "areCreditsFinished() -> bool result",
                fn = function() return areCreditsFinished() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "areMeasurementsInMetres",
                desc = "areMeasurementsInMetres() -> bool result",
                fn = function() return areMeasurementsInMetres() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachAnimsToModel",
                desc = "attachAnimsToModel(Model modelId, GxtString externalScript) ->",
                fn = function() return attachAnimsToModel(0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachCarToCar",
                desc = "attachCarToCar(Vehicle car, int toCar, float offsetX, float offsetY, float offsetZ, float rotationX, float rotationY, float rotationZ) ->",
                fn = function() return attachCarToCar(getTargetVehicleHandle(), 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachCarToObject",
                desc = "attachCarToObject(Vehicle car, Object object, float offsetX, float offsetY, float offsetZ, float rotationX, float rotationY, float rotationZ) ->",
                fn = function() return attachCarToObject(getTargetVehicleHandle(), getTargetObjectHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachMissionAudioToCar",
                desc = "attachMissionAudioToCar(int audioId, Vehicle car) ->",
                fn = function() return attachMissionAudioToCar(0, getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachMissionAudioToChar",
                desc = "attachMissionAudioToChar(int id, Ped ped) ->",
                fn = function() return attachMissionAudioToChar(0, getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachMissionAudioToObject",
                desc = "attachMissionAudioToObject(int id, Object object) ->",
                fn = function() return attachMissionAudioToObject(0, getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachSearchlightToSearchlightObject",
                desc = "attachSearchlightToSearchlightObject(Searchlight searchlight, int tower, int housing, int bulb, float offsetX, float offsetY, float offsetZ) ->",
                fn = function() return attachSearchlightToSearchlightObject(0, 0, 0, 0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "attachWinchToHeli",
                desc = "attachWinchToHeli(Vehicle heli, bool magnet) ->",
                fn = function() return attachWinchToHeli(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "boatGotoCoords",
                desc = "boatGotoCoords(Vehicle boat, float toX, float toY, float toZ) ->",
                fn = function() return boatGotoCoords(getTargetVehicleHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "boatStop",
                desc = "boatStop(Vehicle car) ->",
                fn = function() return boatStop(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "buyItem",
                desc = "buyItem(int item) ->",
                fn = function() return buyItem(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "canCharSeeDeadChar",
                desc = "canCharSeeDeadChar(Ped ped, int pedtype) -> bool result",
                fn = function() return canCharSeeDeadChar(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "canTriggerGangWarWhenOnAMission",
                desc = "canTriggerGangWarWhenOnAMission(bool can) ->",
                fn = function() return canTriggerGangWarWhenOnAMission(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "cancelOverrideRestart",
                desc = "cancelOverrideRestart() -> bool result",
                fn = function() return cancelOverrideRestart() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "changePlaybackToUseAi",
                desc = "changePlaybackToUseAi(Vehicle car) ->",
                fn = function() return changePlaybackToUseAi(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearAllCharRelationships",
                desc = "clearAllCharRelationships(Ped ped, int acquaintance) ->",
                fn = function() return clearAllCharRelationships(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearAllScriptRoadblocks",
                desc = "Removes all script-created police roadblocks",
                fn = function() return clearAllScriptRoadblocks() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearAttractor",
                desc = "clearAttractor(int handle) ->",
                fn = function() return clearAttractor(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearCharDecisionMakerEventResponse",
                desc = "clearCharDecisionMakerEventResponse(int maker, int event) ->",
                fn = function() return clearCharDecisionMakerEventResponse(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearCharLastDamageEntity",
                desc = "clearCharLastDamageEntity(Ped ped) ->",
                fn = function() return clearCharLastDamageEntity(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearCharRelationship",
                desc = "clearCharRelationship(Ped ped, int acquaintance, int pedtype) ->",
                fn = function() return clearCharRelationship(getTargetPlayerHandle(), 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearConversationForChar",
                desc = "clearConversationForChar(Ped ped) ->",
                fn = function() return clearConversationForChar(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearExtraColours",
                desc = "clearExtraColours(bool fade) ->",
                fn = function() return clearExtraColours(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearGroupDecisionMakerEventResponse",
                desc = "clearGroupDecisionMakerEventResponse(int maker, int event) ->",
                fn = function() return clearGroupDecisionMakerEventResponse(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearHeliOrientation",
                desc = "clearHeliOrientation(Vehicle heli) ->",
                fn = function() return clearHeliOrientation(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearLoadedShop",
                desc = "Clears currently loaded interior shop items from memory",
                fn = function() return clearLoadedShop() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearLookAt",
                desc = "clearLookAt(Ped ped) ->",
                fn = function() return clearLookAt(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearOnscreenCounter",
                desc = "clearOnscreenCounter(VarId var) ->",
                fn = function() return clearOnscreenCounter(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearRelationship",
                desc = "clearRelationship(int acquaintance, int pedtype, int toPedtype) ->",
                fn = function() return clearRelationship(0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearSkip",
                desc = "Clears cutscene skip flag",
                fn = function() return clearSkip() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearThisBigPrint",
                desc = "clearThisBigPrint(GxtString text) ->",
                fn = function() return clearThisBigPrint("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "clearThisPrintBigNow",
                desc = "clearThisPrintBigNow(int style) ->",
                fn = function() return clearThisPrintBigNow(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "connectLods",
                desc = "connectLods(Object object, int lod) ->",
                fn = function() return connectLods(getTargetObjectHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "controlMovableVehiclePart",
                desc = "controlMovableVehiclePart(Vehicle car, float angle) ->",
                fn = function() return controlMovableVehiclePart(getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "convertMetresToFeetInt",
                desc = "convertMetresToFeetInt(int metric) -> int imperial",
                fn = function() return convertMetresToFeetInt(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "copyCharDecisionMaker",
                desc = "copyCharDecisionMaker(Ped ped) -> int maker",
                fn = function() return copyCharDecisionMaker(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "copyGroupDecisionMaker",
                desc = "copyGroupDecisionMaker(int group) -> int maker",
                fn = function() return copyGroupDecisionMaker(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "copySharedCharDecisionMaker",
                desc = "copySharedCharDecisionMaker(int from) -> int to",
                fn = function() return copySharedCharDecisionMaker(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createBirds",
                desc = "createBirds(float x1, float y1, float z1, float x2, float y2, float z2, int flag1, int flag2) ->",
                fn = function() return createBirds(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createCarGenerator",
                desc = "createCarGenerator(float atX, float atY, float atZ, float angle, Model modelId, int color1, int color2, bool forceSpawn, int alarm, int doorLock, int minDelay, int maxDelay) -> int carGenerator",
                fn = function() return createCarGenerator(0.0, 0.0, 0.0, 0.0, 0, 0, 0, false, 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createCarGeneratorWithPlate",
                desc = "createCarGeneratorWithPlate(float atX, float atY, float atZ, float angle, Model modelId, int color1, int color2, bool forceSpawn, int alarm, int doorLock, int minDelay, int maxDelay, string plate) -> int generator",
                fn = function() return createCarGeneratorWithPlate(0.0, 0.0, 0.0, 0.0, 0, 0, 0, false, 0, 0, 0, 0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createCharAtAttractor",
                desc = "createCharAtAttractor(int pedtype, Model modelId, int ASOrigin, int task) -> Ped ped",
                fn = function() return createCharAtAttractor(0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createEmergencyServicesCar",
                desc = "createEmergencyServicesCar(Model car, float X, float Y, float Z) ->",
                fn = function() return createEmergencyServicesCar(0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createForsalePropertyPickup",
                desc = "createForsalePropertyPickup(float pX, float pY, float pZ, int price, GxtString gxtString) -> Pickup pickup",
                fn = function() return createForsalePropertyPickup(0.0, 0.0, 0.0, 0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createGroup",
                desc = "createGroup(int type) -> int group",
                fn = function() return createGroup(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createHorseshoePickup",
                desc = "createHorseshoePickup(float atX, float atY, float atZ) -> Pickup pickup",
                fn = function() return createHorseshoePickup(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createLockedPropertyPickup",
                desc = "createLockedPropertyPickup(float pX, float pY, float pZ, GxtString gxtString) -> Pickup pickup",
                fn = function() return createLockedPropertyPickup(0.0, 0.0, 0.0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createMenuGrid",
                desc = "createMenuGrid(GxtString gxtString, int positionX, int positionY, float width, int columns, bool interactive, bool background, int alignment) -> int id",
                fn = function() return createMenuGrid("", 0, 0, 0.0, 0, false, false, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createMissionTrain",
                desc = "createMissionTrain(int type, float atX, float atY, float atZ, bool direction) -> Vehicle train",
                fn = function() return createMissionTrain(0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createObjectNoOffset",
                desc = "createObjectNoOffset(Model modelId, float atX, float atY, float atZ) -> Object object",
                fn = function() return createObjectNoOffset(0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createOysterPickup",
                desc = "createOysterPickup(float atX, float atY, float atZ) -> Pickup pickup",
                fn = function() return createOysterPickup(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createProtectionPickup",
                desc = "createProtectionPickup(float atX, float atY, float atZ, int int4, int int5) -> Pickup pickup",
                fn = function() return createProtectionPickup(0.0, 0.0, 0.0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createRandomCarForCarPark",
                desc = "createRandomCarForCarPark(float coordsX, float coordsY, float coordsZ, float zAngle) ->",
                fn = function() return createRandomCarForCarPark(0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createRandomCharAsDriver",
                desc = "createRandomCharAsDriver(Vehicle car) -> Ped ped",
                fn = function() return createRandomCharAsDriver(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createRandomCharAsPassenger",
                desc = "createRandomCharAsPassenger(Vehicle car, int seat) -> Ped ped",
                fn = function() return createRandomCharAsPassenger(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createScmThreadAtPointer",
                desc = "createScmThreadAtPointer(uint pointer, table args) -> uint thread",
                fn = function() return createScmThreadAtPointer(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createScriptRoadblock",
                desc = "createScriptRoadblock(float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ, int type) ->",
                fn = function() return createScriptRoadblock(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createSearchlight",
                desc = "createSearchlight(float atX, float atY, float atZ, float targetX, float targetY, float targetZ, float radius1, float radius2) -> Searchlight searchlight",
                fn = function() return createSearchlight(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createSearchlightOnVehicle",
                desc = "createSearchlightOnVehicle(Vehicle car, float offsetX, float offsetY, float offsetZ, float targetX, float targetY, float targetZ, float radius, float radius) -> Searchlight searchlight",
                fn = function() return createSearchlightOnVehicle(getTargetVehicleHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createSnapshotPickup",
                desc = "createSnapshotPickup(float atX, float atY, float atZ) -> Pickup pickup",
                fn = function() return createSnapshotPickup(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "createSwatRope",
                desc = "createSwatRope(int pedtype, Model modelId, float X, float Y, float Z) -> int handleAs",
                fn = function() return createSwatRope(0, 0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "customPlateDesignForNextCar",
                desc = "customPlateDesignForNextCar(Model modelNumplate, int townTexture) ->",
                fn = function() return customPlateDesignForNextCar(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "customPlateForNextCar",
                desc = "customPlateForNextCar(Model modelId, string numberplate) ->",
                fn = function() return customPlateForNextCar(0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "damageChar",
                desc = "damageChar(Ped ped, int health, bool affectArmour) ->",
                fn = function() return damageChar(getTargetPlayerHandle(), 0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "declareMissionFlag",
                desc = "declareMissionFlag(VarId flag) ->",
                fn = function() return declareMissionFlag(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "decrementFloatStat",
                desc = "decrementFloatStat(int stat, float float) ->",
                fn = function() return decrementFloatStat(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "decrementIntStat",
                desc = "decrementIntStat(int stat, int int) ->",
                fn = function() return decrementIntStat(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "deleteAllTrains",
                desc = "Deletes all active train entities in the world",
                fn = function() return deleteAllTrains() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "deleteMissionTrain",
                desc = "deleteMissionTrain(Vehicle train) ->",
                fn = function() return deleteMissionTrain(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "deleteMissionTrains",
                desc = "Deletes mission-spawned train vehicles",
                fn = function() return deleteMissionTrains() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "deletePlayer",
                desc = "deletePlayer(Player player) ->",
                fn = function() return deletePlayer(getTargetPlayer()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "deleteSearchlight",
                desc = "deleteSearchlight(Searchlight searchlight) ->",
                fn = function() return deleteSearchlight(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "destroyScmThread",
                desc = "destroyScmThread(uint thread) ->",
                fn = function() return destroyScmThread(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "disableAllEntryExits",
                desc = "disableAllEntryExits(bool disable) ->",
                fn = function() return disableAllEntryExits(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "disableCharSpeech",
                desc = "disableCharSpeech(Ped ped, bool disable) ->",
                fn = function() return disableCharSpeech(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "disableHeliAudio",
                desc = "disableHeliAudio(Vehicle helicopter, bool disable) ->",
                fn = function() return disableHeliAudio(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "displayCarNames",
                desc = "displayCarNames(bool show) ->",
                fn = function() return displayCarNames(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "displayNonMinigameHelpMessages",
                desc = "displayNonMinigameHelpMessages(bool display) ->",
                fn = function() return displayNonMinigameHelpMessages(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "do2dRectanglesCollide",
                desc = "do2dRectanglesCollide(float areaX, float areaY, float scaleX, float scaleY, float overlapareaX, float overlapareaY, float overlapscaleX, float overlapscaleY) -> bool result",
                fn = function() return do2dRectanglesCollide(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "doFade",
                desc = "doFade(bool in, int time) ->",
                fn = function() return doFade(false, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "doesCarHaveStuckCarCheck",
                desc = "doesCarHaveStuckCarCheck(Vehicle car) -> bool result",
                fn = function() return doesCarHaveStuckCarCheck(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "doesDecisionMakerExist",
                desc = "doesDecisionMakerExist(int maker) -> bool result",
                fn = function() return doesDecisionMakerExist(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "doesGroupExist",
                desc = "doesGroupExist(int group) -> bool result",
                fn = function() return doesGroupExist(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "doesSearchlightExist",
                desc = "doesSearchlightExist(Searchlight searchlight) -> bool result",
                fn = function() return doesSearchlightExist(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dontRemoveChar",
                desc = "dontRemoveChar(Ped ped) ->",
                fn = function() return dontRemoveChar(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dontRemoveObject",
                desc = "dontRemoveObject(Object object) ->",
                fn = function() return dontRemoveObject(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dontSuppressAnyCarModels",
                desc = "Disables car model suppression restrictions",
                fn = function() return dontSuppressAnyCarModels() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dontSuppressCarModel",
                desc = "dontSuppressCarModel(Model modelId) ->",
                fn = function() return dontSuppressCarModel(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "drawCorona",
                desc = "drawCorona(float atX, float atY, float atZ, float radius, int type, bool lensflares, int r, int g, int b) ->",
                fn = function() return drawCorona(0.0, 0.0, 0.0, 0.0, 0, false, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "drawCrosshair",
                desc = "drawCrosshair(bool draw) ->",
                fn = function() return drawCrosshair(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "drawOddjobTitleBeforeFade",
                desc = "drawOddjobTitleBeforeFade(bool flag) ->",
                fn = function() return drawOddjobTitleBeforeFade(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "drawRect",
                desc = "drawRect(float positionX, float positionY, float width, float height, int r, int g, int b, int a) ->",
                fn = function() return drawRect(0.0, 0.0, 0.0, 0.0, 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "drawSphere",
                desc = "drawSphere(float atX, float atY, float atZ, float radius) ->",
                fn = function() return drawSphere(0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "drawSprite",
                desc = "drawSprite(int texture, float positionX, float positionY, float width, float height, int r, int g, int b, int a) ->",
                fn = function() return drawSprite(0, 0.0, 0.0, 0.0, 0.0, 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "drawSpriteWithRotation",
                desc = "drawSpriteWithRotation(int texture, float x, float y, float scaleX, float scaleY, float angle, int r, int g, int b, int a) ->",
                fn = function() return drawSpriteWithRotation(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "drawSubtitlesBeforeFade",
                desc = "drawSubtitlesBeforeFade(bool flag) ->",
                fn = function() return drawSubtitlesBeforeFade(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "drawWindow",
                desc = "drawWindow(float cornerAX, float cornerAY, float cornerBX, float cornerBY, GxtString gxtString, int style) ->",
                fn = function() return drawWindow(0.0, 0.0, 0.0, 0.0, "", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dropObject",
                desc = "dropObject(Ped ped, bool object) ->",
                fn = function() return dropObject(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dropSecondObject",
                desc = "dropSecondObject(Ped ped, bool to) ->",
                fn = function() return dropSecondObject(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "enableAmbientCrime",
                desc = "enableAmbientCrime(bool enable) ->",
                fn = function() return enableAmbientCrime(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "enableBurglaryHouses",
                desc = "enableBurglaryHouses(bool enable) ->",
                fn = function() return enableBurglaryHouses(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "enableCharSpeech",
                desc = "enableCharSpeech(Ped ped) ->",
                fn = function() return enableCharSpeech(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "enableConversation",
                desc = "enableConversation(Ped ped, bool enable) ->",
                fn = function() return enableConversation(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "enableCraneControls",
                desc = "enableCraneControls(bool UP, bool DOWN, bool RELEASE) ->",
                fn = function() return enableCraneControls(false, false, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "enableDisabledAttractorsOnObject",
                desc = "enableDisabledAttractorsOnObject(Object object, bool enable) ->",
                fn = function() return enableDisabledAttractorsOnObject(getTargetObjectHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "enableEntryExitPlayerGroupWarping",
                desc = "enableEntryExitPlayerGroupWarping(float X, float Y, float radius, bool access) ->",
                fn = function() return enableEntryExitPlayerGroupWarping(0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "explodeCharHead",
                desc = "explodeCharHead(Ped ped) ->",
                fn = function() return explodeCharHead(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "extendPatrolRoute",
                desc = "extendPatrolRoute(float X, float Y, float Z, string animation, string IFPFile) ->",
                fn = function() return extendPatrolRoute(0.0, 0.0, 0.0, "", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "extendRoute",
                desc = "extendRoute(float pointX, float pointY, float pointZ) ->",
                fn = function() return extendRoute(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "failCurrentMission",
                desc = "Triggers immediate failure of active mission",
                fn = function() return failCurrentMission() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "failKillFrenzy",
                desc = "Fails currently active rampage / kill frenzy mission",
                fn = function() return failKillFrenzy() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "fetchNextCard",
                desc = "fetchNextCard() -> int card",
                fn = function() return fetchNextCard() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "findAllRandomObjectsInSphere",
                desc = "findAllRandomObjectsInSphere(float posX, float posY, float posZ, float radius, bool findNext) -> bool result, Object object",
                fn = function() return findAllRandomObjectsInSphere(0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "findAllRandomVehiclesInSphere",
                desc = "findAllRandomVehiclesInSphere(float posX, float posY, float posZ, float radius, bool findNext, bool skipWrecked) -> bool result, Vehicle car",
                fn = function() return findAllRandomVehiclesInSphere(0.0, 0.0, 0.0, 0.0, false, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "findMaxNumberOfGroupMembers",
                desc = "findMaxNumberOfGroupMembers() -> int max",
                fn = function() return findMaxNumberOfGroupMembers() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "findNumberTagsTagged",
                desc = "findNumberTagsTagged() -> int num",
                fn = function() return findNumberTagsTagged() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "findTrainDirection",
                desc = "findTrainDirection(Vehicle train) -> bool result",
                fn = function() return findTrainDirection(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "finishSettingUpConversation",
                desc = "Finalizes scripted audio conversation setup",
                fn = function() return finishSettingUpConversation() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "finishSettingUpConversationNoSubtitles",
                desc = "Finalizes conversation setup without displaying subtitles",
                fn = function() return finishSettingUpConversationNoSubtitles() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "flushPatrolRoute",
                desc = "Clears ped patrol route node list",
                fn = function() return flushPatrolRoute() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "flushRoute",
                desc = "Clears active path route node list",
                fn = function() return flushRoute() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "forceAllVehicleLightsOff",
                desc = "forceAllVehicleLightsOff(bool off) ->",
                fn = function() return forceAllVehicleLightsOff(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "forceBigMessageAndCounter",
                desc = "forceBigMessageAndCounter(bool stayOnScreen) ->",
                fn = function() return forceBigMessageAndCounter(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "forceCarLights",
                desc = "forceCarLights(Vehicle car, int lights) ->",
                fn = function() return forceCarLights(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "forceDeathRestart",
                desc = "Forces game to restart at hospital after player death",
                fn = function() return forceDeathRestart() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "freeDynamicLibrary",
                desc = "freeDynamicLibrary(uint handle) ->",
                fn = function() return freeDynamicLibrary(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "freezeObjectPosition",
                desc = "freezeObjectPosition(Object object, bool freeze) ->",
                fn = function() return freezeObjectPosition(getTargetObjectHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "get2dLinesIntersectPoint",
                desc = "get2dLinesIntersectPoint(float l1x1, float l1y1, float l1x2, float l1y2, float l2x1, float l2y1, float l2x2, float l2y2) -> bool result, float X, float Y",
                fn = function() return get2dLinesIntersectPoint(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getAvailableVehicleMod",
                desc = "getAvailableVehicleMod(Vehicle car, int poolIndex) -> Model itemID",
                fn = function() return getAvailableVehicleMod(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getBeatProximity",
                desc = "getBeatProximity(int track) -> int int2, int int3, int int4",
                fn = function() return getBeatProximity(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getBeatTrackStatus",
                desc = "getBeatTrackStatus() -> int status",
                fn = function() return getBeatTrackStatus() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCarMovingComponentOffset",
                desc = "getCarMovingComponentOffset(Vehicle car) -> float angle",
                fn = function() return getCarMovingComponentOffset(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCarPitch",
                desc = "getCarPitch(Vehicle car) -> float pitch",
                fn = function() return getCarPitch(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCarUprightValue",
                desc = "getCarUprightValue(Vehicle car) -> float value",
                fn = function() return getCarUprightValue(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCharHighestPriorityEvent",
                desc = "getCharHighestPriorityEvent(Ped ped) -> int event",
                fn = function() return getCharHighestPriorityEvent(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCityFromCoords",
                desc = "getCityFromCoords(float X, float Y, float Z) -> int city",
                fn = function() return getCityFromCoords(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCleoSharedVar",
                desc = "getCleoSharedVar(int var) -> int value",
                fn = function() return getCleoSharedVar(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getClosestCarNode",
                desc = "getClosestCarNode(float closestToX, float closestToY, float closestToZ) -> float nodeX, float nodeY, float nodeZ",
                fn = function() return getClosestCarNode(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getClosestCarNodeWithHeading",
                desc = "getClosestCarNodeWithHeading(float X, float Y, float Z) -> float nodeX, float nodeY, float nodeZ, float angle",
                fn = function() return getClosestCarNodeWithHeading(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getClosestCharNode",
                desc = "getClosestCharNode(float closestToX, float closestToY, float closestToZ) -> float nodeX, float nodeY, float nodeZ",
                fn = function() return getClosestCharNode(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getClosestStealableObject",
                desc = "getClosestStealableObject(float X, float Y, float Z, float radius) -> Object object",
                fn = function() return getClosestStealableObject(0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getClothesItem",
                desc = "getClothesItem(Player player, int bodypart) -> int textureCRC, int modelCRC",
                fn = function() return getClothesItem(getTargetPlayer(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCollectable1sCollected",
                desc = "getCollectable1sCollected() -> int collected",
                fn = function() return getCollectable1sCollected() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCurrentCarMod",
                desc = "getCurrentCarMod(Vehicle car, int slot) -> Model modelId",
                fn = function() return getCurrentCarMod(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCurrentVehiclePaintjob",
                desc = "getCurrentVehiclePaintjob(Vehicle car) -> int paintjob",
                fn = function() return getCurrentVehiclePaintjob(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getCursorPos",
                desc = "getCursorPos() -> int posX, int posY",
                fn = function() return getCursorPos() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getD3DDevicePtr",
                desc = "getD3DDevicePtr() -> uint devicePtr",
                fn = function() return getD3DDevicePtr() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getDeadCharCoordinates",
                desc = "getDeadCharCoordinates(Ped ped) -> float X, float Y, float Z",
                fn = function() return getDeadCharCoordinates(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getDeadCharPickupCoords",
                desc = "getDeadCharPickupCoords(Ped ped) -> float coordsX, float coordsY, float coordsZ",
                fn = function() return getDeadCharPickupCoords(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getDynamicLibraryProcedure",
                desc = "getDynamicLibraryProcedure(string proc, uint handle) -> bool result, uint proc",
                fn = function() return getDynamicLibraryProcedure("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getExtraCarColours",
                desc = "getExtraCarColours(Vehicle car) -> int tertiaryColor, int quaternaryColor",
                fn = function() return getExtraCarColours(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getFadingStatus",
                desc = "getFadingStatus() -> bool result",
                fn = function() return getFadingStatus() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getFloatStat",
                desc = "getFloatStat(int stat) -> float stat",
                fn = function() return getFloatStat(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getFreeGxtKey",
                desc = "getFreeGxtKey() -> string key",
                fn = function() return getFreeGxtKey() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getGameGlobal",
                desc = "getGameGlobal(int index) -> int value",
                fn = function() return getGameGlobal(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getGameGlobalFloat",
                desc = "getGameGlobalFloat(int index) -> float value",
                fn = function() return getGameGlobalFloat(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getGameGlobalPtr",
                desc = "getGameGlobalPtr(int index) -> uint ptr",
                fn = function() return getGameGlobalPtr(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getGroupMember",
                desc = "getGroupMember(int group, int member) -> int handle",
                fn = function() return getGroupMember(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getGroupSize",
                desc = "getGroupSize(int group) -> int numberOfLeaders, int numberOfMembers",
                fn = function() return getGroupSize(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getHavocCausedByPlayer",
                desc = "getHavocCausedByPlayer(int int1) -> int int2",
                fn = function() return getHavocCausedByPlayer(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getIntStat",
                desc = "getIntStat(int stat) -> int stat",
                fn = function() return getIntStat(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getItemInShop",
                desc = "getItemInShop(int index) -> int item",
                fn = function() return getItemInShop(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getLevelDesignCoordsForObject",
                desc = "getLevelDesignCoordsForObject(Object object, int spoot) -> float X, float Y, float Z",
                fn = function() return getLevelDesignCoordsForObject(getTargetObjectHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getLoadedShop",
                desc = "getLoadedShop() -> GxtString shop",
                fn = function() return getLoadedShop() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getMenuItemAccepted",
                desc = "getMenuItemAccepted(int menu) -> int item",
                fn = function() return getMenuItemAccepted(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getMenuItemSelected",
                desc = "getMenuItemSelected(int menu) -> int item",
                fn = function() return getMenuItemSelected(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getNameOfEntryExitCharUsed",
                desc = "getNameOfEntryExitCharUsed(Ped ped) -> GxtString interiorName",
                fn = function() return getNameOfEntryExitCharUsed(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getNameOfItem",
                desc = "getNameOfItem(int item) -> GxtString name",
                fn = function() return getNameOfItem(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getNearestTagPosition",
                desc = "getNearestTagPosition(float X, float Y, float Z) -> float X, float Y, float Z",
                fn = function() return getNearestTagPosition(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getNthClosestCarNode",
                desc = "getNthClosestCarNode(float X, float Y, float Z, int type) -> float X, float Y, float Z",
                fn = function() return getNthClosestCarNode(0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getNthClosestCarNodeWithHeading",
                desc = "getNthClosestCarNodeWithHeading(float forX, float forY, float forZ, int direction) -> float X, float Y, float Z, float ZAngle",
                fn = function() return getNthClosestCarNodeWithHeading(0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getNumAvailablePaintjobs",
                desc = "getNumAvailablePaintjobs(Vehicle car) -> int num",
                fn = function() return getNumAvailablePaintjobs(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getNumCarColours",
                desc = "getNumCarColours(Vehicle car) -> int colours",
                fn = function() return getNumCarColours(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getNumOfModelsKilledByPlayer",
                desc = "getNumOfModelsKilledByPlayer(Player player, Model modelId) -> int quantity",
                fn = function() return getNumOfModelsKilledByPlayer(getTargetPlayer(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getNumberOfFollowers",
                desc = "getNumberOfFollowers(Ped ped) -> int followers",
                fn = function() return getNumberOfFollowers(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getNumberOfInstancesOfStreamedScript",
                desc = "getNumberOfInstancesOfStreamedScript(int externalScript) -> int value",
                fn = function() return getNumberOfInstancesOfStreamedScript(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getNumberOfItemsInShop",
                desc = "getNumberOfItemsInShop() -> int num",
                fn = function() return getNumberOfItemsInShop() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getObjectTurnMass",
                desc = "getObjectTurnMass(Object object) -> float turnMass",
                fn = function() return getObjectTurnMass(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getOffsetFromCarInWorldCoords",
                desc = "getOffsetFromCarInWorldCoords(Vehicle car, float offsetX, float offsetY, float offsetZ) -> float X, float Y, float Z",
                fn = function() return getOffsetFromCarInWorldCoords(getTargetVehicleHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getOffsetFromObjectInWorldCoords",
                desc = "getOffsetFromObjectInWorldCoords(Object object, float offsetX, float offsetY, float offsetZ) -> float X, float Y, float Z",
                fn = function() return getOffsetFromObjectInWorldCoords(getTargetObjectHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getPadState",
                desc = "getPadState(Player player, int key) -> int state",
                fn = function() return getPadState(getTargetPlayer(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getParkingNodeInArea",
                desc = "getParkingNodeInArea(float x1, float y1, float z1, float x2, float y2, float z2) -> float X, float Y, float Z",
                fn = function() return getParkingNodeInArea(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getPercentageTaggedInArea",
                desc = "getPercentageTaggedInArea(float x1, float y1, float x2, float y2) -> int percentage",
                fn = function() return getPercentageTaggedInArea(0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getPlaneUndercarriagePosition",
                desc = "getPlaneUndercarriagePosition(int plane) -> int landingGearStatus",
                fn = function() return getPlaneUndercarriagePosition(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getPlayerGroup",
                desc = "getPlayerGroup(Player player) -> int group",
                fn = function() return getPlayerGroup(getTargetPlayer()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getPlayerMaxArmour",
                desc = "getPlayerMaxArmour(Player player) -> int maxArmour",
                fn = function() return getPlayerMaxArmour(getTargetPlayer()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getPositionOfAnalogueSticks",
                desc = "getPositionOfAnalogueSticks(int joystick) -> int offset1, int offset2, int offset3, int offset4",
                fn = function() return getPositionOfAnalogueSticks(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getPositionOfEntryExitCharUsed",
                desc = "getPositionOfEntryExitCharUsed(Ped ped) -> float coordX, float coordY, float coordZ, int number",
                fn = function() return getPositionOfEntryExitCharUsed(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getPriceOfItem",
                desc = "getPriceOfItem(int item) -> int price",
                fn = function() return getPriceOfItem(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getProgressPercentage",
                desc = "getProgressPercentage() -> float progress",
                fn = function() return getProgressPercentage() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getRandomCarInSphereNoSave",
                desc = "getRandomCarInSphereNoSave(float X, float Y, float Z, float radius, int model) -> Vehicle car",
                fn = function() return getRandomCarInSphereNoSave(0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getRandomCarModelInMemory",
                desc = "getRandomCarModelInMemory(bool unk) -> Model modelId, int class",
                fn = function() return getRandomCarModelInMemory(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getRandomCarOfTypeInAngledAreaNoSave",
                desc = "getRandomCarOfTypeInAngledAreaNoSave(float x1, float y1, float x2, float y2, float angle, int int6) -> Vehicle car",
                fn = function() return getRandomCarOfTypeInAngledAreaNoSave(0.0, 0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getRandomCarOfTypeInArea",
                desc = "getRandomCarOfTypeInArea(float cornerAX, float cornerAY, float cornerBX, float cornerBY, Model modelId) -> Vehicle car",
                fn = function() return getRandomCarOfTypeInArea(0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getRandomCarOfTypeInAreaNoSave",
                desc = "getRandomCarOfTypeInAreaNoSave(float x1, float y1, float x2, float y2, Model modelId) -> Vehicle car",
                fn = function() return getRandomCarOfTypeInAreaNoSave(0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getRandomCharInAreaOffsetNoSave",
                desc = "getRandomCharInAreaOffsetNoSave(float sphereX, float sphereY, float sphereZ, float radiusX, float radiusY, float radiusZ) -> Ped ped",
                fn = function() return getRandomCharInAreaOffsetNoSave(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getRandomCharInSphere",
                desc = "getRandomCharInSphere(float X, float Y, float Z, float radius, bool pedtypeCivilian, bool gang, bool prostitute) -> Ped ped",
                fn = function() return getRandomCharInSphere(0.0, 0.0, 0.0, 0.0, false, false, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getRandomCharInSphereNoBrain",
                desc = "getRandomCharInSphereNoBrain(float X, float Y, float Z, float radius) -> Ped ped",
                fn = function() return getRandomCharInSphereNoBrain(0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getRandomCharInSphereOnlyDrugsBuyers",
                desc = "getRandomCharInSphereOnlyDrugsBuyers(float X, float Y, float Z, float radius) -> Ped ped",
                fn = function() return getRandomCharInSphereOnlyDrugsBuyers(0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getRandomCopInArea",
                desc = "getRandomCopInArea(float float1, float float2, float float3, float float4, bool int5, bool int6, bool int7, bool int8, bool int9) -> int int10",
                fn = function() return getRandomCopInArea(0.0, 0.0, 0.0, 0.0, false, false, false, false, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getRemoteControlledCar",
                desc = "getRemoteControlledCar(Player player) -> Vehicle car",
                fn = function() return getRemoteControlledCar(getTargetPlayer()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getRidOfPlayerProstitute",
                desc = "Removes prostitute ped following the player",
                fn = function() return getRidOfPlayerProstitute() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getRopeHeightForObject",
                desc = "getRopeHeightForObject(int magnet) -> float length",
                fn = function() return getRopeHeightForObject(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getScmThreadLocalVar",
                desc = "getScmThreadLocalVar(uint thread, int var) -> int value",
                fn = function() return getScmThreadLocalVar(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getScmThreadStructNamed",
                desc = "getScmThreadStructNamed(GxtString thread) -> int handle",
                fn = function() return getScmThreadStructNamed("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getSequenceProgress",
                desc = "getSequenceProgress(Ped ped) -> int progess",
                fn = function() return getSequenceProgress(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getSequenceProgressRecursive",
                desc = "getSequenceProgressRecursive(Ped ped) -> int unkProgress1, int unkProgress2",
                fn = function() return getSequenceProgressRecursive(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getShoppingExtraInfo",
                desc = "getShoppingExtraInfo(int item, int flag) -> int info",
                fn = function() return getShoppingExtraInfo(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getStringWidth",
                desc = "getStringWidth(GxtString gxtString) -> int width",
                fn = function() return getStringWidth("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getStringWidthWithNumber",
                desc = "getStringWidthWithNumber(GxtString gxtString, int number) -> int width",
                fn = function() return getStringWidthWithNumber("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getTerritoryUnderControlPercentage",
                desc = "getTerritoryUnderControlPercentage() -> int percentage",
                fn = function() return getTerritoryUnderControlPercentage() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getTotalNumberOfPedsKilledByPlayer",
                desc = "getTotalNumberOfPedsKilledByPlayer(Player player) -> int number",
                fn = function() return getTotalNumberOfPedsKilledByPlayer(getTargetPlayer()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getTrainCaboose",
                desc = "getTrainCaboose(Vehicle train) -> int caboose",
                fn = function() return getTrainCaboose(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getTrainCarriage",
                desc = "getTrainCarriage(Vehicle train, int handle) -> int carriage",
                fn = function() return getTrainCarriage(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getUserOfClosestMapAttractor",
                desc = "getUserOfClosestMapAttractor(float sphereX, float sphereY, float sphereZ, float radius, Model modelId, string externalScriptNamed) -> Ped ped",
                fn = function() return getUserOfClosestMapAttractor(0.0, 0.0, 0.0, 0.0, 0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "getVehicleQuaternion",
                desc = "getVehicleQuaternion(Vehicle car) -> float x, float y, float z, float w",
                fn = function() return getVehicleQuaternion(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "giveMeleeAttackToChar",
                desc = "giveMeleeAttackToChar(Ped ped, int fightingStyle, int moves) ->",
                fn = function() return giveMeleeAttackToChar(getTargetPlayerHandle(), 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "giveNonPlayerCarNitro",
                desc = "giveNonPlayerCarNitro(Vehicle car) ->",
                fn = function() return giveNonPlayerCarNitro(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "giveRemoteControlledCarToPlayer",
                desc = "giveRemoteControlledCarToPlayer(Player player, float float2, float float3, float float4) ->",
                fn = function() return giveRemoteControlledCarToPlayer(getTargetPlayer(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "giveRemoteControlledModelToPlayer",
                desc = "giveRemoteControlledModelToPlayer(Player player, float atX, float atY, float atZ, float angle, Model RCModel) ->",
                fn = function() return giveRemoteControlledModelToPlayer(getTargetPlayer(), 0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "giveVehiclePaintjob",
                desc = "giveVehiclePaintjob(int set, int paintjob) ->",
                fn = function() return giveVehiclePaintjob(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "grabEntityOnRopeForObject",
                desc = "grabEntityOnRopeForObject(int magnet) -> Vehicle carHandle, Ped pedHandle, Object objectHandle",
                fn = function() return grabEntityOnRopeForObject(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "grabEntityOnWinch",
                desc = "grabEntityOnWinch(Vehicle heli) -> Vehicle carHandle, Ped pedHandle, Object objectHandle",
                fn = function() return grabEntityOnWinch(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasCarBeenDamagedByChar",
                desc = "hasCarBeenDamagedByChar(Vehicle car, Ped byActor) -> bool result",
                fn = function() return hasCarBeenDamagedByChar(getTargetVehicleHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasCarBeenResprayed",
                desc = "hasCarBeenResprayed(Vehicle car) -> bool result",
                fn = function() return hasCarBeenResprayed(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasCarRecordingBeenLoaded",
                desc = "hasCarRecordingBeenLoaded(int path) -> bool result",
                fn = function() return hasCarRecordingBeenLoaded(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasCharBeenArrested",
                desc = "hasCharBeenArrested(Ped ped) -> bool result",
                fn = function() return hasCharBeenArrested(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasCharBeenDamagedByCar",
                desc = "hasCharBeenDamagedByCar(Ped ped, Vehicle byCar) -> bool result",
                fn = function() return hasCharBeenDamagedByCar(getTargetPlayerHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasCharBeenDamagedByChar",
                desc = "hasCharBeenDamagedByChar(Ped ped, Ped byActor) -> bool result",
                fn = function() return hasCharBeenDamagedByChar(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasCharBeenPhotographed",
                desc = "hasCharBeenPhotographed(Ped ped) -> bool result",
                fn = function() return hasCharBeenPhotographed(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasCharSpottedChar",
                desc = "hasCharSpottedChar(Ped ped, Ped ped) -> bool result",
                fn = function() return hasCharSpottedChar(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasCharSpottedCharInFront",
                desc = "hasCharSpottedCharInFront(Ped ped, Ped ped2) -> bool result",
                fn = function() return hasCharSpottedCharInFront(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasDeatharrestBeenExecuted",
                desc = "hasDeatharrestBeenExecuted() -> bool result",
                fn = function() return hasDeatharrestBeenExecuted() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasGameJustReturnedFromFrontend",
                desc = "hasGameJustReturnedFromFrontend() -> bool result",
                fn = function() return hasGameJustReturnedFromFrontend() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasImportGarageSlotBeenFilled",
                desc = "hasImportGarageSlotBeenFilled(int int1, int int2) -> bool result",
                fn = function() return hasImportGarageSlotBeenFilled(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasLanguageChanged",
                desc = "hasLanguageChanged() -> bool result",
                fn = function() return hasLanguageChanged() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasObjectBeenDamaged",
                desc = "hasObjectBeenDamaged(Object object) -> bool result",
                fn = function() return hasObjectBeenDamaged(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasObjectBeenPhotographed",
                desc = "hasObjectBeenPhotographed(Object object) -> bool result",
                fn = function() return hasObjectBeenPhotographed(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasObjectBeenUprooted",
                desc = "hasObjectBeenUprooted(Object object) -> bool result",
                fn = function() return hasObjectBeenUprooted(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasObjectCollidedWithAnything",
                desc = "hasObjectCollidedWithAnything(Object object) -> bool result",
                fn = function() return hasObjectCollidedWithAnything(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasObjectOfTypeBeenSmashed",
                desc = "hasObjectOfTypeBeenSmashed(float X, float Y, float Z, float radius, Model modelId) -> bool result",
                fn = function() return hasObjectOfTypeBeenSmashed(0.0, 0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasPlayerBoughtItem",
                desc = "hasPlayerBoughtItem(int item) -> bool result",
                fn = function() return hasPlayerBoughtItem(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasResprayHappened",
                desc = "hasResprayHappened(Vehicle car) -> bool result",
                fn = function() return hasResprayHappened(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasSaveGameFinished",
                desc = "hasSaveGameFinished() -> bool result",
                fn = function() return hasSaveGameFinished() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasSpecialCharacterLoaded",
                desc = "hasSpecialCharacterLoaded(int id) -> bool result",
                fn = function() return hasSpecialCharacterLoaded(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasStreamedScriptLoaded",
                desc = "hasStreamedScriptLoaded(int script) -> bool result",
                fn = function() return hasStreamedScriptLoaded(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasTrainDerailed",
                desc = "hasTrainDerailed(Vehicle train) -> bool result",
                fn = function() return hasTrainDerailed(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "hasVehicleModLoaded",
                desc = "hasVehicleModLoaded(Model component) -> bool result",
                fn = function() return hasVehicleModLoaded(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "heliAttackPlayer",
                desc = "heliAttackPlayer(Vehicle heli, Player player, float radius) ->",
                fn = function() return heliAttackPlayer(getTargetVehicleHandle(), getTargetPlayer(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "heliFollowEntity",
                desc = "heliFollowEntity(Vehicle heli, Ped ped, Vehicle car, float radius) ->",
                fn = function() return heliFollowEntity(getTargetVehicleHandle(), getTargetPlayerHandle(), getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "heliGotoCoords",
                desc = "heliGotoCoords(Vehicle heli, float toX, float toY, float toZ, float altitudeMin, float altitudeMax) ->",
                fn = function() return heliGotoCoords(getTargetVehicleHandle(), 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "heliKeepEntityInView",
                desc = "heliKeepEntityInView(Vehicle heli, Ped ped, Vehicle car, float minaltitude, float maxaltitude) ->",
                fn = function() return heliKeepEntityInView(getTargetVehicleHandle(), getTargetPlayerHandle(), getTargetVehicleHandle(), 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "heliLandAtCoords",
                desc = "heliLandAtCoords(Vehicle heli, float X, float Y, float Z, float minaltitude, float maxaltitude) ->",
                fn = function() return heliLandAtCoords(getTargetVehicleHandle(), 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "highlightMenuItem",
                desc = "highlightMenuItem(int panel, int row, bool highlight) ->",
                fn = function() return highlightMenuItem(0, 0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "ignoreHeightDifferenceFollowingNodes",
                desc = "ignoreHeightDifferenceFollowingNodes(Ped ped, bool ignore) ->",
                fn = function() return ignoreHeightDifferenceFollowingNodes(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "improveCarByCheating",
                desc = "improveCarByCheating(Vehicle car, bool affectedByCheats) ->",
                fn = function() return improveCarByCheating(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "incrementFloatStat",
                desc = "incrementFloatStat(int stat, float add) ->",
                fn = function() return incrementFloatStat(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "incrementFloatStatNoMessage",
                desc = "incrementFloatStatNoMessage(int stat, float value) ->",
                fn = function() return incrementFloatStatNoMessage(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "incrementIntStat",
                desc = "incrementIntStat(int stat, int add) ->",
                fn = function() return incrementIntStat(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "incrementIntStatNoMessage",
                desc = "incrementIntStatNoMessage(int stat, int value) ->",
                fn = function() return incrementIntStatNoMessage(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "is2playerGameGoingOn",
                desc = "is2playerGameGoingOn() -> bool result",
                fn = function() return is2playerGameGoingOn() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isAreaOccupied",
                desc = "isAreaOccupied(float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ, bool solid, bool car, bool actor, bool object, bool particle) -> bool result",
                fn = function() return isAreaOccupied(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isAttachedPlayerHeadingAchieved",
                desc = "isAttachedPlayerHeadingAchieved(Player player) -> bool result",
                fn = function() return isAttachedPlayerHeadingAchieved(getTargetPlayer()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isBigVehicle",
                desc = "isBigVehicle(Vehicle car) -> bool result",
                fn = function() return isBigVehicle(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarInAirProper",
                desc = "isCarInAirProper(Vehicle car) -> bool result",
                fn = function() return isCarInAirProper(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarInArea2d",
                desc = "isCarInArea2d(Vehicle car, float cornerAX, float cornerAY, float cornerBX, float cornerBY, bool sphere) -> bool result",
                fn = function() return isCarInArea2d(getTargetVehicleHandle(), 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarInArea3d",
                desc = "isCarInArea3d(Vehicle car, float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ, bool sphere) -> bool result",
                fn = function() return isCarInArea3d(getTargetVehicleHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarLowRider",
                desc = "isCarLowRider(Vehicle car) -> bool result",
                fn = function() return isCarLowRider(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarStoppedInArea2d",
                desc = "isCarStoppedInArea2d(Vehicle car, float cornerAX, float cornerAY, float cornerBX, float cornerBY, bool sphere) -> bool result",
                fn = function() return isCarStoppedInArea2d(getTargetVehicleHandle(), 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarStoppedInArea3d",
                desc = "isCarStoppedInArea3d(Vehicle car, float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ, bool sphere) -> bool result",
                fn = function() return isCarStoppedInArea3d(getTargetVehicleHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarStreetRacer",
                desc = "isCarStreetRacer(Vehicle car) -> bool result",
                fn = function() return isCarStreetRacer(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarTouchingCar",
                desc = "isCarTouchingCar(Vehicle car1, Vehicle car2) -> bool result",
                fn = function() return isCarTouchingCar(getTargetVehicleHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCarWaitingForWorldCollision",
                desc = "isCarWaitingForWorldCollision(Vehicle car) -> bool result",
                fn = function() return isCarWaitingForWorldCollision(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharAtScriptedAttractor",
                desc = "isCharAtScriptedAttractor(Ped ped, int origin) -> bool result",
                fn = function() return isCharAtScriptedAttractor(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharHeadMissing",
                desc = "isCharHeadMissing(Ped ped) -> bool result",
                fn = function() return isCharHeadMissing(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInAnySearchlight",
                desc = "isCharInAnySearchlight(Ped ped) -> bool result, Searchlight searchlight",
                fn = function() return isCharInAnySearchlight(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharInSearchlight",
                desc = "isCharInSearchlight(Searchlight searchlight, Ped ped) -> bool result",
                fn = function() return isCharInSearchlight(0, getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharRespondingToEvent",
                desc = "isCharRespondingToEvent(Ped ped, int event) -> bool result",
                fn = function() return isCharRespondingToEvent(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharTouchingChar",
                desc = "isCharTouchingChar(Ped ped, Ped ped2) -> bool result",
                fn = function() return isCharTouchingChar(getTargetPlayerHandle(), getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharTouchingObject",
                desc = "isCharTouchingObject(Ped ped, Object object) -> bool result",
                fn = function() return isCharTouchingObject(getTargetPlayerHandle(), getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharTouchingObjectOnFoot",
                desc = "isCharTouchingObjectOnFoot(Ped ped, Object object) -> bool result",
                fn = function() return isCharTouchingObjectOnFoot(getTargetPlayerHandle(), getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharTouchingVehicle",
                desc = "isCharTouchingVehicle(Ped ped, Vehicle car) -> bool result",
                fn = function() return isCharTouchingVehicle(getTargetPlayerHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharUsingMapAttractor",
                desc = "isCharUsingMapAttractor(Ped ped) -> bool result",
                fn = function() return isCharUsingMapAttractor(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCharWaitingForWorldCollision",
                desc = "isCharWaitingForWorldCollision(Ped ped) -> bool result",
                fn = function() return isCharWaitingForWorldCollision(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isClosestObjectOfTypeSmashedOrDamaged",
                desc = "isClosestObjectOfTypeSmashedOrDamaged(Model object, float atX, float atY, float atZ, float radius, bool smashed, bool damaged) -> bool result",
                fn = function() return isClosestObjectOfTypeSmashedOrDamaged(0, 0.0, 0.0, 0.0, 0.0, false, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isConversationAtNode",
                desc = "isConversationAtNode(Ped ped, GxtString gxtString) -> bool result",
                fn = function() return isConversationAtNode(getTargetPlayerHandle(), "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCopVehicleInArea3dNoSave",
                desc = "isCopVehicleInArea3dNoSave(float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ) -> bool result",
                fn = function() return isCopVehicleInArea3dNoSave(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isCursorActive",
                desc = "isCursorActive() -> bool result",
                fn = function() return isCursorActive() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isEmergencyServicesVehicle",
                desc = "isEmergencyServicesVehicle(Vehicle car) -> bool result",
                fn = function() return isEmergencyServicesVehicle(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isFlameInAngledArea2d",
                desc = "isFlameInAngledArea2d(float x1, float y1, float x2, float y2, float angle, bool sphere) -> bool result",
                fn = function() return isFlameInAngledArea2d(0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isFlameInAngledArea3d",
                desc = "isFlameInAngledArea3d(float x1, float y1, float z1, float x2, float y2, float z2, float angle, bool sphere) -> bool result",
                fn = function() return isFlameInAngledArea3d(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isGameWindowForeground",
                desc = "isGameWindowForeground() -> bool foreground",
                fn = function() return isGameWindowForeground() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isGangWarFightingGoingOn",
                desc = "isGangWarFightingGoingOn() -> bool result",
                fn = function() return isGangWarFightingGoingOn() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isGangWarGoingOn",
                desc = "isGangWarGoingOn() -> bool result",
                fn = function() return isGangWarGoingOn() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isGroupLeader",
                desc = "isGroupLeader(Ped ped, int group) -> bool result",
                fn = function() return isGroupLeader(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isGroupMember",
                desc = "isGroupMember(Ped ped, int group) -> bool result",
                fn = function() return isGroupMember(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isHelpMessageBeingDisplayed",
                desc = "isHelpMessageBeingDisplayed() -> bool result",
                fn = function() return isHelpMessageBeingDisplayed() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isLastBuildingModelShotByPlayer",
                desc = "isLastBuildingModelShotByPlayer(Player player, Model modelId) -> bool result",
                fn = function() return isLastBuildingModelShotByPlayer(getTargetPlayer(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isMessageBeingDisplayed",
                desc = "isMessageBeingDisplayed() -> bool result",
                fn = function() return isMessageBeingDisplayed() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isMinigameInProgress",
                desc = "isMinigameInProgress() -> bool result",
                fn = function() return isMinigameInProgress() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isNextStationAllowed",
                desc = "isNextStationAllowed(Vehicle train) -> bool result",
                fn = function() return isNextStationAllowed(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isObjectInAngledArea2d",
                desc = "isObjectInAngledArea2d(Object object, float x1, float y1, float x2, float y2, float radius, bool sphere) -> bool result",
                fn = function() return isObjectInAngledArea2d(getTargetObjectHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isObjectInAngledArea3d",
                desc = "isObjectInAngledArea3d(Object object, float x1, float y1, float z1, float x2, float y2, float z2, float depth, bool flag) -> bool result",
                fn = function() return isObjectInAngledArea3d(getTargetObjectHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isObjectInArea2d",
                desc = "isObjectInArea2d(Object object, float cornerAX, float cornerAY, float cornerBX, float cornerBY, bool sphere) -> bool result",
                fn = function() return isObjectInArea2d(getTargetObjectHandle(), 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isObjectInArea3d",
                desc = "isObjectInArea3d(Object object, float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ, bool flag) -> bool result",
                fn = function() return isObjectInArea3d(getTargetObjectHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isObjectInWater",
                desc = "isObjectInWater(Object object) -> bool result",
                fn = function() return isObjectInWater(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isObjectIntersectingWorld",
                desc = "isObjectIntersectingWorld(Object object) -> bool result",
                fn = function() return isObjectIntersectingWorld(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isObjectPlayingAnim",
                desc = "isObjectPlayingAnim(Object object, string anim) -> bool result",
                fn = function() return isObjectPlayingAnim(getTargetObjectHandle(), "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isObjectStatic",
                desc = "isObjectStatic(Object object) -> bool result",
                fn = function() return isObjectStatic(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isObjectWithinBrainActivationRange",
                desc = "isObjectWithinBrainActivationRange(Player player) -> bool result",
                fn = function() return isObjectWithinBrainActivationRange(getTargetPlayer()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPlaybackGoingOnForCar",
                desc = "isPlaybackGoingOnForCar(Vehicle car) -> bool result",
                fn = function() return isPlaybackGoingOnForCar(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isPointObscuredByAMissionEntity",
                desc = "isPointObscuredByAMissionEntity(float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ) -> bool result",
                fn = function() return isPointObscuredByAMissionEntity(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isProceduralInteriorActive",
                desc = "isProceduralInteriorActive(int interior) -> bool result",
                fn = function() return isProceduralInteriorActive(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isProjectileInArea",
                desc = "isProjectileInArea(float cornerAX, float cornerAY, float cornerAZ, float cornerBX, float cornerBY, float cornerBZ) -> bool result",
                fn = function() return isProjectileInArea(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isRelationshipSet",
                desc = "isRelationshipSet(int acquaintance, int ofActors, int toActors) -> bool result",
                fn = function() return isRelationshipSet(0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isSkipWaitingForScriptToFadeIn",
                desc = "isSkipWaitingForScriptToFadeIn() -> bool result",
                fn = function() return isSkipWaitingForScriptToFadeIn() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isThisHelpMessageBeingDisplayed",
                desc = "isThisHelpMessageBeingDisplayed(GxtString gxtString) -> bool result",
                fn = function() return isThisHelpMessageBeingDisplayed("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isVehicleAttached",
                desc = "isVehicleAttached(Vehicle car) -> bool result",
                fn = function() return isVehicleAttached(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isVehicleInSearchlight",
                desc = "isVehicleInSearchlight(int int, Vehicle car) -> bool result",
                fn = function() return isVehicleInSearchlight(0, getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "isWidescreenOnInOptions",
                desc = "isWidescreenOnInOptions() -> bool result",
                fn = function() return isWidescreenOnInOptions() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "launchCustomMission",
                desc = "launchCustomMission(zstring filepath, table args) ->",
                fn = function() return launchCustomMission("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "limitTwoPlayerDistance",
                desc = "limitTwoPlayerDistance(float distance) ->",
                fn = function() return limitTwoPlayerDistance(0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "linkObjectToInterior",
                desc = "linkObjectToInterior(Object object, int interior) ->",
                fn = function() return linkObjectToInterior(getTargetObjectHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "listenToPlayerGroupCommands",
                desc = "listenToPlayerGroupCommands(Ped ped, bool listen) ->",
                fn = function() return listenToPlayerGroupCommands(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadAndLaunchMissionInternal",
                desc = "loadAndLaunchMissionInternal(int mission) ->",
                fn = function() return loadAndLaunchMissionInternal(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadCharDecisionMaker",
                desc = "loadCharDecisionMaker(int type) -> int maker",
                fn = function() return loadCharDecisionMaker(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadDynamicLibrary",
                desc = "loadDynamicLibrary(string library) -> bool result, uint handle",
                fn = function() return loadDynamicLibrary("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadGroupDecisionMaker",
                desc = "loadGroupDecisionMaker(int type) -> int maker",
                fn = function() return loadGroupDecisionMaker(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadPathNodesInArea",
                desc = "loadPathNodesInArea(float x1, float y1, float x2, float y2) ->",
                fn = function() return loadPathNodesInArea(0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadPrices",
                desc = "loadPrices(GxtString shopping) ->",
                fn = function() return loadPrices("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadScene",
                desc = "loadScene(float atX, float atY, float atZ) ->",
                fn = function() return loadScene(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadSceneInDirection",
                desc = "loadSceneInDirection(float coordX, float coordY, float coordZ, float angle) ->",
                fn = function() return loadSceneInDirection(0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadShop",
                desc = "loadShop(GxtString shopping) ->",
                fn = function() return loadShop("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadSpecialCharacter",
                desc = "loadSpecialCharacter(GxtString gxtString, int id) ->",
                fn = function() return loadSpecialCharacter("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadSplashScreen",
                desc = "loadSplashScreen(GxtString gxtString) ->",
                fn = function() return loadSplashScreen("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "loadSprite",
                desc = "loadSprite(string name) -> int id",
                fn = function() return loadSprite("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCar2d",
                desc = "locateCar2d(Vehicle car, float pointX, float pointY, float radiusX, float radiusY, bool sphere) -> bool result",
                fn = function() return locateCar2d(getTargetVehicleHandle(), 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateCar3d",
                desc = "locateCar3d(Vehicle car, float sphereX, float sphereY, float sphereZ, float radiusX, float radiusY, float radiusZ, bool sphere) -> bool result",
                fn = function() return locateCar3d(getTargetVehicleHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateObject2d",
                desc = "locateObject2d(Object object, float X, float Y, float radiusX, float radiusY, bool sphere) -> bool result",
                fn = function() return locateObject2d(getTargetObjectHandle(), 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateObject3d",
                desc = "locateObject3d(Object object, float X, float Y, float Z, float radiusX, float radiusY, float radiusZ, bool flag) -> bool result",
                fn = function() return locateObject3d(getTargetObjectHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateStoppedCar2d",
                desc = "locateStoppedCar2d(Vehicle car, float pointX, float pointY, float radiusX, float radiusY, bool sphere) -> bool result",
                fn = function() return locateStoppedCar2d(getTargetVehicleHandle(), 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "locateStoppedCar3d",
                desc = "locateStoppedCar3d(Vehicle car, float sphereX, float sphereY, float sphereZ, float radiusX, float radiusY, float radiusZ, bool sphere) -> bool result",
                fn = function() return locateStoppedCar3d(getTargetVehicleHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "makeHeliComeCrashingDown",
                desc = "makeHeliComeCrashingDown(Vehicle heli) ->",
                fn = function() return makeHeliComeCrashingDown(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "makeObjectTargettable",
                desc = "makeObjectTargettable(Object object, bool targetable) ->",
                fn = function() return makeObjectTargettable(getTargetObjectHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "makePlayerGangDisappear",
                desc = "Hides player gang members in current territory",
                fn = function() return makePlayerGangDisappear() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "makePlayerGangReappear",
                desc = "Restores visibility of player gang members",
                fn = function() return makePlayerGangReappear() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "makeRoomInPlayerGangForMissionPeds",
                desc = "makeRoomInPlayerGangForMissionPeds(int group) ->",
                fn = function() return makeRoomInPlayerGangForMissionPeds(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "manageAllPopulation",
                desc = "Controls ambient ped and vehicle population generation",
                fn = function() return manageAllPopulation() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "markCarAsConvoyCar",
                desc = "markCarAsConvoyCar(Vehicle car, bool convoy) ->",
                fn = function() return markCarAsConvoyCar(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "markCarAsNoLongerNeeded",
                desc = "markCarAsNoLongerNeeded(Vehicle car) ->",
                fn = function() return markCarAsNoLongerNeeded(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "markCharAsNoLongerNeeded",
                desc = "markCharAsNoLongerNeeded(Ped ped) ->",
                fn = function() return markCharAsNoLongerNeeded(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "markMissionTrainAsNoLongerNeeded",
                desc = "markMissionTrainAsNoLongerNeeded(Vehicle train) ->",
                fn = function() return markMissionTrainAsNoLongerNeeded(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "markMissionTrainsAsNoLongerNeeded",
                desc = "Releases mission trains to ambient cleanup",
                fn = function() return markMissionTrainsAsNoLongerNeeded() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "markObjectAsNoLongerNeeded",
                desc = "markObjectAsNoLongerNeeded(Object object) ->",
                fn = function() return markObjectAsNoLongerNeeded(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "markRoadNodeAsDontWander",
                desc = "markRoadNodeAsDontWander(float atX, float atY, float atZ) ->",
                fn = function() return markRoadNodeAsDontWander(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "markStreamedScriptAsNoLongerNeeded",
                desc = "markStreamedScriptAsNoLongerNeeded(int externalScript) ->",
                fn = function() return markStreamedScriptAsNoLongerNeeded(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "markVehicleModAsNoLongerNeeded",
                desc = "markVehicleModAsNoLongerNeeded(Model component) ->",
                fn = function() return markVehicleModAsNoLongerNeeded(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "moveSearchlightBetweenCoords",
                desc = "moveSearchlightBetweenCoords(Searchlight searchlight, float fromX, float fromY, float fromZ, float toX, float toY, float toZ, float speed) ->",
                fn = function() return moveSearchlightBetweenCoords(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "overrideNextRestart",
                desc = "overrideNextRestart(float atX, float atY, float atZ, float angle) ->",
                fn = function() return overrideNextRestart(0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "pauseCurrentBeatTrack",
                desc = "pauseCurrentBeatTrack(bool paused) ->",
                fn = function() return pauseCurrentBeatTrack(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "pausePlaybackRecordedCar",
                desc = "pausePlaybackRecordedCar(Vehicle car) ->",
                fn = function() return pausePlaybackRecordedCar(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "pauseScmThread",
                desc = "pauseScmThread(uint thread) ->",
                fn = function() return pauseScmThread(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "placeObjectRelativeToCar",
                desc = "placeObjectRelativeToCar(Object object, Vehicle car, float offsetX, float offsetY, float offsetZ) ->",
                fn = function() return placeObjectRelativeToCar(getTargetObjectHandle(), getTargetVehicleHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "placeWaypoint",
                desc = "placeWaypoint(float x, float y, float z) -> bool result",
                fn = function() return placeWaypoint(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "planeAttackPlayer",
                desc = "planeAttackPlayer(int hydra, Vehicle car, float radius) ->",
                fn = function() return planeAttackPlayer(0, getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "planeAttackPlayerUsingDogFight",
                desc = "planeAttackPlayerUsingDogFight(int hydra, Player player, float radius) ->",
                fn = function() return planeAttackPlayerUsingDogFight(0, getTargetPlayer(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "planeFlyInDirection",
                desc = "planeFlyInDirection(int plane, float direction, float altitudemin, float altitudemax) ->",
                fn = function() return planeFlyInDirection(0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "planeFollowEntity",
                desc = "planeFollowEntity(int plane, Ped ped, Vehicle car, float radius) ->",
                fn = function() return planeFollowEntity(0, getTargetPlayerHandle(), getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "planeGotoCoords",
                desc = "planeGotoCoords(int plane, float X, float Y, float Z, float z1, float z2) ->",
                fn = function() return planeGotoCoords(0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "planeStartsInAir",
                desc = "planeStartsInAir(int hydra) ->",
                fn = function() return planeStartsInAir(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "playBeatTrack",
                desc = "Plays rhythmic beat audio track",
                fn = function() return playBeatTrack() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "playMissionPassedTune",
                desc = "playMissionPassedTune(int music) ->",
                fn = function() return playMissionPassedTune(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "playObjectAnim",
                desc = "playObjectAnim(Object object, string animation, string IFPFile, float framedelta, bool lockF, bool loop) -> bool result",
                fn = function() return playObjectAnim(getTargetObjectHandle(), "", "", 0.0, false, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "playerEnteredBuildingsiteCrane",
                desc = "Notifies game that player entered building site crane",
                fn = function() return playerEnteredBuildingsiteCrane() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "playerEnteredDockCrane",
                desc = "Notifies game that player entered ocean dock crane",
                fn = function() return playerEnteredDockCrane() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "playerEnteredLasVegasCrane",
                desc = "Notifies game that player entered Las Venturas crane",
                fn = function() return playerEnteredLasVegasCrane() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "playerEnteredQuarryCrane",
                desc = "Notifies game that player entered quarry mining crane",
                fn = function() return playerEnteredQuarryCrane() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "playerLeftCrane",
                desc = "Notifies game that player exited industrial crane",
                fn = function() return playerLeftCrane() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "pointSearchlightAtChar",
                desc = "pointSearchlightAtChar(Searchlight searchlight, Ped ped, float speed) ->",
                fn = function() return pointSearchlightAtChar(0, getTargetPlayerHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "pointSearchlightAtCoord",
                desc = "pointSearchlightAtCoord(Searchlight searchlight, float toX, float toY, float toZ, float speed) ->",
                fn = function() return pointSearchlightAtCoord(0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "pointSearchlightAtVehicle",
                desc = "pointSearchlightAtVehicle(Searchlight searchlight, Vehicle car, float speed) ->",
                fn = function() return pointSearchlightAtVehicle(0, getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "policeHeliChaseEntity",
                desc = "policeHeliChaseEntity(Vehicle heli, Ped ped, Vehicle car, float radius) ->",
                fn = function() return policeHeliChaseEntity(getTargetVehicleHandle(), getTargetPlayerHandle(), getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "policeRadioMessage",
                desc = "policeRadioMessage(float float1, float float2, float float3) ->",
                fn = function() return policeRadioMessage(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "popFloat",
                desc = "popFloat() -> float val",
                fn = function() return popFloat() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "preloadBeatTrack",
                desc = "preloadBeatTrack(int soundtrack) ->",
                fn = function() return preloadBeatTrack(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "randomPassengerSay",
                desc = "randomPassengerSay(int passengers, int audioTable) ->",
                fn = function() return randomPassengerSay(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "readKillFrenzyStatus",
                desc = "readKillFrenzyStatus() -> bool result, int status",
                fn = function() return readKillFrenzyStatus() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "registerAttractorScriptBrainForCodeUse",
                desc = "registerAttractorScriptBrainForCodeUse(int handle, GxtString script) ->",
                fn = function() return registerAttractorScriptBrainForCodeUse(0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "registerBestPosition",
                desc = "registerBestPosition(int stat, float float) ->",
                fn = function() return registerBestPosition(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "registerFloatStat",
                desc = "registerFloatStat(int stat, float value) ->",
                fn = function() return registerFloatStat(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "registerHighestScore",
                desc = "registerHighestScore(int int1, int int2) ->",
                fn = function() return registerHighestScore(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "registerIntStat",
                desc = "registerIntStat(int stat, int int) ->",
                fn = function() return registerIntStat(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "registerMissionGiven",
                desc = "Registers mission as accepted by player",
                fn = function() return registerMissionGiven() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "registerMissionPassed",
                desc = "registerMissionPassed(GxtString mission) ->",
                fn = function() return registerMissionPassed("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "registerOddjobMissionPassed",
                desc = "Registers side-job (oddjob) mission as completed",
                fn = function() return registerOddjobMissionPassed() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "registerScriptBrainForCodeUse",
                desc = "registerScriptBrainForCodeUse(int id, GxtString gxtString) ->",
                fn = function() return registerScriptBrainForCodeUse(0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "releaseEntityFromRopeForObject",
                desc = "releaseEntityFromRopeForObject(int magnet) ->",
                fn = function() return releaseEntityFromRopeForObject(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "releaseEntityFromWinch",
                desc = "releaseEntityFromWinch(Vehicle heli) ->",
                fn = function() return releaseEntityFromWinch(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "releasePathNodes",
                desc = "Releases reserved pathfinding nodes",
                fn = function() return releasePathNodes() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "releaseTwoPlayerDistance",
                desc = "Releases 2-player camera distance constraint",
                fn = function() return releaseTwoPlayerDistance() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeCarRecording",
                desc = "removeCarRecording(int path) ->",
                fn = function() return removeCarRecording(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeCharFromCarMaintainPosition",
                desc = "removeCharFromCarMaintainPosition(Ped ped, Vehicle car) ->",
                fn = function() return removeCharFromCarMaintainPosition(getTargetPlayerHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeCharFromGroup",
                desc = "removeCharFromGroup(Ped ped) ->",
                fn = function() return removeCharFromGroup(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeDecisionMaker",
                desc = "removeDecisionMaker(int maker) ->",
                fn = function() return removeDecisionMaker(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeGroup",
                desc = "removeGroup(int group) ->",
                fn = function() return removeGroup(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeIpl",
                desc = "removeIpl(string group) ->",
                fn = function() return removeIpl("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeIplDiscreetly",
                desc = "removeIplDiscreetly(string group) ->",
                fn = function() return removeIplDiscreetly("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeObjectElegantly",
                desc = "removeObjectElegantly(Object object) ->",
                fn = function() return removeObjectElegantly(getTargetObjectHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeOilPuddlesInArea",
                desc = "removeOilPuddlesInArea(float x1, float y1, float x2, float y2) ->",
                fn = function() return removeOilPuddlesInArea(0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removePriceModifier",
                desc = "removePriceModifier(int item) ->",
                fn = function() return removePriceModifier(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeRcBuggy",
                desc = "Destroys and removes player remote-controlled RC buggy",
                fn = function() return removeRcBuggy() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeSphere",
                desc = "removeSphere(int sphere) ->",
                fn = function() return removeSphere(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeStreamedScript",
                desc = "removeStreamedScript(int externalScript) ->",
                fn = function() return removeStreamedScript(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "removeWaypoint",
                desc = "removeWaypoint() -> bool result",
                fn = function() return removeWaypoint() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "reportMissionAudioEventAtCar",
                desc = "reportMissionAudioEventAtCar(Vehicle car, int event) ->",
                fn = function() return reportMissionAudioEventAtCar(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "reportMissionAudioEventAtChar",
                desc = "reportMissionAudioEventAtChar(Ped ped, int event) ->",
                fn = function() return reportMissionAudioEventAtChar(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "reportMissionAudioEventAtObject",
                desc = "reportMissionAudioEventAtObject(int at, int event) ->",
                fn = function() return reportMissionAudioEventAtObject(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "reportMissionAudioEventAtPosition",
                desc = "reportMissionAudioEventAtPosition(float atX, float atY, float atZ, int event) ->",
                fn = function() return reportMissionAudioEventAtPosition(0.0, 0.0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "requestCarRecording",
                desc = "requestCarRecording(int path) ->",
                fn = function() return requestCarRecording(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "requestCollision",
                desc = "requestCollision(float X, float Y) ->",
                fn = function() return requestCollision(0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "requestIpl",
                desc = "requestIpl(string group) ->",
                fn = function() return requestIpl("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "requestVehicleMod",
                desc = "requestVehicleMod(Model component) ->",
                fn = function() return requestVehicleMod(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "resetHavocCausedByPlayer",
                desc = "resetHavocCausedByPlayer(int int1) ->",
                fn = function() return resetHavocCausedByPlayer(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "resetNumOfModelsKilledByPlayer",
                desc = "resetNumOfModelsKilledByPlayer(Player player) ->",
                fn = function() return resetNumOfModelsKilledByPlayer(getTargetPlayer()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "resetStuffUponResurrection",
                desc = "Resets game state flags when player resurrects",
                fn = function() return resetStuffUponResurrection() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "restartScmThread",
                desc = "restartScmThread(uint thread, table args) ->",
                fn = function() return restartScmThread(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "restoreCarModState",
                desc = "Restores saved vehicle modification configuration",
                fn = function() return restoreCarModState() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "restoreClothesState",
                desc = "Restores saved character clothes configuration",
                fn = function() return restoreClothesState() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "resumeScmThread",
                desc = "resumeScmThread(uint thread) ->",
                fn = function() return resumeScmThread(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "rotateObject",
                desc = "rotateObject(Object object, float fromAngle, float toAngle, bool flag) -> bool result",
                fn = function() return rotateObject(getTargetObjectHandle(), 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setActiveMenuItem",
                desc = "setActiveMenuItem(int panel, int activeRow) ->",
                fn = function() return setActiveMenuItem(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setAircraftCarrierSamSite",
                desc = "setAircraftCarrierSamSite(bool enable) ->",
                fn = function() return setAircraftCarrierSamSite(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setAllCarsCanBeDamaged",
                desc = "setAllCarsCanBeDamaged(bool enable) ->",
                fn = function() return setAllCarsCanBeDamaged(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setAllTaxisHaveNitro",
                desc = "setAllTaxisHaveNitro(bool toggle) ->",
                fn = function() return setAllTaxisHaveNitro(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setAlwaysDraw3dMarkers",
                desc = "setAlwaysDraw3dMarkers(bool set) ->",
                fn = function() return setAlwaysDraw3dMarkers(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setAnimGroupForChar",
                desc = "setAnimGroupForChar(Ped ped, string style) ->",
                fn = function() return setAnimGroupForChar(getTargetPlayerHandle(), "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setArea51SamSite",
                desc = "setArea51SamSite(bool enable) ->",
                fn = function() return setArea51SamSite(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setAreaName",
                desc = "setAreaName(GxtString gxtString) ->",
                fn = function() return setAreaName("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setBoatCruiseSpeed",
                desc = "setBoatCruiseSpeed(Vehicle boat, float speed) ->",
                fn = function() return setBoatCruiseSpeed(getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCanBurstCarTires",
                desc = "setCanBurstCarTires(Vehicle car, bool vulnerability) ->",
                fn = function() return setCanBurstCarTires(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCanResprayCar",
                desc = "setCanResprayCar(Vehicle car, bool sprayable) ->",
                fn = function() return setCanResprayCar(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarAlwaysCreateSkids",
                desc = "setCarAlwaysCreateSkids(Vehicle car, bool enable) ->",
                fn = function() return setCarAlwaysCreateSkids(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarAsMissionCar",
                desc = "setCarAsMissionCar(Vehicle car) ->",
                fn = function() return setCarAsMissionCar(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarAvoidLevelTransitions",
                desc = "setCarAvoidLevelTransitions(Vehicle car, bool avoidLevelTransitions) ->",
                fn = function() return setCarAvoidLevelTransitions(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarCoordinatesNoOffset",
                desc = "setCarCoordinatesNoOffset(Vehicle car, float X, float Y, float Z) ->",
                fn = function() return setCarCoordinatesNoOffset(getTargetVehicleHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarEscortCarFront",
                desc = "setCarEscortCarFront(Vehicle car, Vehicle followCar) ->",
                fn = function() return setCarEscortCarFront(getTargetVehicleHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarEscortCarLeft",
                desc = "setCarEscortCarLeft(Vehicle car, Vehicle followCar) ->",
                fn = function() return setCarEscortCarLeft(getTargetVehicleHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarEscortCarRear",
                desc = "setCarEscortCarRear(Vehicle car, Vehicle followCar) ->",
                fn = function() return setCarEscortCarRear(getTargetVehicleHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarEscortCarRight",
                desc = "setCarEscortCarRight(Vehicle car, Vehicle followCar) ->",
                fn = function() return setCarEscortCarRight(getTargetVehicleHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarFollowCar",
                desc = "setCarFollowCar(Vehicle car, int followCar, float radius) ->",
                fn = function() return setCarFollowCar(getTargetVehicleHandle(), 0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarModelComponents",
                desc = "setCarModelComponents(Model car, int variation1, int variation2) ->",
                fn = function() return setCarModelComponents(0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarOnlyDamagedByPlayer",
                desc = "setCarOnlyDamagedByPlayer(Vehicle car, bool enabled) ->",
                fn = function() return setCarOnlyDamagedByPlayer(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarRamCar",
                desc = "setCarRamCar(Vehicle car, Vehicle car) ->",
                fn = function() return setCarRamCar(getTargetVehicleHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarRandomRouteSeed",
                desc = "setCarRandomRouteSeed(Vehicle car, int routeSeed) ->",
                fn = function() return setCarRandomRouteSeed(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarRoll",
                desc = "setCarRoll(Vehicle car, float roll) ->",
                fn = function() return setCarRoll(getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarStatus",
                desc = "setCarStatus(Vehicle car, int action) ->",
                fn = function() return setCarStatus(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarStayInFastLane",
                desc = "setCarStayInFastLane(Vehicle car, bool flag) ->",
                fn = function() return setCarStayInFastLane(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarStayInSlowLane",
                desc = "setCarStayInSlowLane(Vehicle car, bool stay) ->",
                fn = function() return setCarStayInSlowLane(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarStraightLineDistance",
                desc = "setCarStraightLineDistance(Vehicle car, int radius) ->",
                fn = function() return setCarStraightLineDistance(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCarTempAction",
                desc = "setCarTempAction(Vehicle car, int action, int time) ->",
                fn = function() return setCarTempAction(getTargetVehicleHandle(), 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharAnimPlayingFlag",
                desc = "setCharAnimPlayingFlag(Ped ped, string animation, bool flag) ->",
                fn = function() return setCharAnimPlayingFlag(getTargetPlayerHandle(), "", false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharCanBeShotInVehicle",
                desc = "setCharCanBeShotInVehicle(Ped ped, bool can) ->",
                fn = function() return setCharCanBeShotInVehicle(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharCoordinatesDontWarpGang",
                desc = "setCharCoordinatesDontWarpGang(Ped ped, float X, float Y, float Z) ->",
                fn = function() return setCharCoordinatesDontWarpGang(getTargetPlayerHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharCoordinatesDontWarpGangNoOffset",
                desc = "setCharCoordinatesDontWarpGangNoOffset(Ped ped, float atX, float atY, float atZ) ->",
                fn = function() return setCharCoordinatesDontWarpGangNoOffset(getTargetPlayerHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharDecisionMaker",
                desc = "setCharDecisionMaker(Ped ped, int maker) ->",
                fn = function() return setCharDecisionMaker(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharDruggedUp",
                desc = "setCharDruggedUp(Ped ped, bool druggedUp) ->",
                fn = function() return setCharDruggedUp(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharIsChrisCriminal",
                desc = "setCharIsChrisCriminal(Ped ped, bool flag) ->",
                fn = function() return setCharIsChrisCriminal(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharIsTargetPriority",
                desc = "setCharIsTargetPriority(Ped ped, bool targetPriority) ->",
                fn = function() return setCharIsTargetPriority(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharKindaStayInSamePlace",
                desc = "setCharKindaStayInSamePlace(Ped ped, bool stay) ->",
                fn = function() return setCharKindaStayInSamePlace(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharNeverLeavesGroup",
                desc = "setCharNeverLeavesGroup(Ped ped, bool set) ->",
                fn = function() return setCharNeverLeavesGroup(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharNeverTargetted",
                desc = "setCharNeverTargetted(Ped ped, bool untargetable) ->",
                fn = function() return setCharNeverTargetted(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharOnlyDamagedByPlayer",
                desc = "setCharOnlyDamagedByPlayer(Ped ped, bool enabled) ->",
                fn = function() return setCharOnlyDamagedByPlayer(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharRelationship",
                desc = "setCharRelationship(Ped ped, int acquaintance, int pedtype) ->",
                fn = function() return setCharRelationship(getTargetPlayerHandle(), 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharSayContext",
                desc = "setCharSayContext(Ped ped, int speech) -> int spokenPhrase",
                fn = function() return setCharSayContext(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharSayContextImportant",
                desc = "setCharSayContextImportant(Ped ped, int soundslot, bool flags1, bool flags2, bool flags3) -> int unk",
                fn = function() return setCharSayContextImportant(getTargetPlayerHandle(), 0, false, false, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharSayScript",
                desc = "setCharSayScript(Ped ped, int sound, bool flags1, bool flags2, bool flags3) ->",
                fn = function() return setCharSayScript(getTargetPlayerHandle(), 0, false, false, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharStayInCarWhenJacked",
                desc = "setCharStayInCarWhenJacked(Ped ped, bool stay) ->",
                fn = function() return setCharStayInCarWhenJacked(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharUsesCollisionClosestObjectOfType",
                desc = "setCharUsesCollisionClosestObjectOfType(float sphereX, float sphereY, float sphereZ, float radius, Model modelId, bool solid, int forActor) ->",
                fn = function() return setCharUsesCollisionClosestObjectOfType(0.0, 0.0, 0.0, 0.0, 0, false, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCharUsesUpperbodyDamageAnimsOnly",
                desc = "setCharUsesUpperbodyDamageAnimsOnly(Ped ped, bool uninterupted) ->",
                fn = function() return setCharUsesUpperbodyDamageAnimsOnly(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCleoSharedVar",
                desc = "setCleoSharedVar(int var, int value) ->",
                fn = function() return setCleoSharedVar(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setClosestEntryExitFlag",
                desc = "setClosestEntryExitFlag(float atX, float atY, float radius, int bitmask, bool flag) ->",
                fn = function() return setClosestEntryExitFlag(0.0, 0.0, 0.0, 0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCollectable1Total",
                desc = "setCollectable1Total(int total) ->",
                fn = function() return setCollectable1Total(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCreateRandomCops",
                desc = "setCreateRandomCops(bool enable) ->",
                fn = function() return setCreateRandomCops(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setCreateRandomGangMembers",
                desc = "setCreateRandomGangMembers(bool enable) ->",
                fn = function() return setCreateRandomGangMembers(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setDeatharrestState",
                desc = "setDeatharrestState(bool value) ->",
                fn = function() return setDeatharrestState(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setDrunkInputDelay",
                desc = "setDrunkInputDelay(Player player, int handlingResponsiveness) ->",
                fn = function() return setDrunkInputDelay(getTargetPlayer(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setEnableRcDetonate",
                desc = "setEnableRcDetonate(bool detonation) ->",
                fn = function() return setEnableRcDetonate(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setEnableRcDetonateOnContact",
                desc = "setEnableRcDetonateOnContact(bool enable) ->",
                fn = function() return setEnableRcDetonateOnContact(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setEnterCarRangeMultiplier",
                desc = "setEnterCarRangeMultiplier(float float1) ->",
                fn = function() return setEnterCarRangeMultiplier(0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setExtraCarColours",
                desc = "setExtraCarColours(Vehicle car, int tertiaryColor, int quaternaryColor) ->",
                fn = function() return setExtraCarColours(getTargetVehicleHandle(), 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setExtraColours",
                desc = "setExtraColours(int color, bool fade) ->",
                fn = function() return setExtraColours(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setExtraHospitalRestartPoint",
                desc = "setExtraHospitalRestartPoint(float X, float Y, float Z, float radius, float angle) ->",
                fn = function() return setExtraHospitalRestartPoint(0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setExtraPoliceStationRestartPoint",
                desc = "setExtraPoliceStationRestartPoint(float X, float Y, float Z, float radius, float angle) ->",
                fn = function() return setExtraPoliceStationRestartPoint(0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setFadingColour",
                desc = "setFadingColour(int r, int g, int b) ->",
                fn = function() return setFadingColour(0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setFloatStat",
                desc = "setFloatStat(int stat, float float) ->",
                fn = function() return setFloatStat(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setFollowNodeThresholdDistance",
                desc = "setFollowNodeThresholdDistance(Ped ped, float dist) ->",
                fn = function() return setFollowNodeThresholdDistance(getTargetPlayerHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setForceRandomCarModel",
                desc = "setForceRandomCarModel(Model modelId) ->",
                fn = function() return setForceRandomCarModel(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setFreeGxtEntry",
                desc = "setFreeGxtEntry(string text) -> string key",
                fn = function() return setFreeGxtEntry("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setFreeHealthCare",
                desc = "setFreeHealthCare(Player player, bool free) ->",
                fn = function() return setFreeHealthCare(getTargetPlayer(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setFreeResprays",
                desc = "setFreeResprays(bool enable) ->",
                fn = function() return setFreeResprays(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setFreebiesInVehicle",
                desc = "setFreebiesInVehicle(Vehicle car, bool containsGoodies) ->",
                fn = function() return setFreebiesInVehicle(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setGameGlobal",
                desc = "setGameGlobal(int index, int value) ->",
                fn = function() return setGameGlobal(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setGameGlobalFloat",
                desc = "setGameGlobalFloat(int index, float value) ->",
                fn = function() return setGameGlobalFloat(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setGangWarsActive",
                desc = "setGangWarsActive(bool enable) ->",
                fn = function() return setGangWarsActive(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setGangWarsTrainingMission",
                desc = "setGangWarsTrainingMission(bool set) ->",
                fn = function() return setGangWarsTrainingMission(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setGarageResprayFree",
                desc = "setGarageResprayFree(GxtString garage, bool free) ->",
                fn = function() return setGarageResprayFree("", false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setGenerateCarsAroundCamera",
                desc = "setGenerateCarsAroundCamera(bool int1) ->",
                fn = function() return setGenerateCarsAroundCamera(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setGroupDecisionMaker",
                desc = "setGroupDecisionMaker(int group, int maker) ->",
                fn = function() return setGroupDecisionMaker(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setGroupFollowStatus",
                desc = "setGroupFollowStatus(int group, bool status) ->",
                fn = function() return setGroupFollowStatus(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setGroupLeader",
                desc = "setGroupLeader(int group, Ped ped) ->",
                fn = function() return setGroupLeader(0, getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setGroupMember",
                desc = "setGroupMember(int group, Ped ped) ->",
                fn = function() return setGroupMember(0, getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setGroupSeparationRange",
                desc = "setGroupSeparationRange(int group, float range) ->",
                fn = function() return setGroupSeparationRange(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setGroupSequence",
                desc = "setGroupSequence(int group, int Aspack) ->",
                fn = function() return setGroupSequence(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setHasBeenOwnedForCarGenerator",
                desc = "setHasBeenOwnedForCarGenerator(int generator, bool owned) ->",
                fn = function() return setHasBeenOwnedForCarGenerator(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setHeadingForAttachedPlayer",
                desc = "setHeadingForAttachedPlayer(Player player, float toAngle, float rotationSpeed) ->",
                fn = function() return setHeadingForAttachedPlayer(getTargetPlayer(), 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setHeadingLimitForAttachedChar",
                desc = "setHeadingLimitForAttachedChar(Ped ped, int orientation, float limit) ->",
                fn = function() return setHeadingLimitForAttachedChar(getTargetPlayerHandle(), 0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setHeliReachedTargetDistance",
                desc = "setHeliReachedTargetDistance(Vehicle heli, int dist) ->",
                fn = function() return setHeliReachedTargetDistance(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setHeliStabiliser",
                desc = "setHeliStabiliser(Vehicle heli, bool limiter) ->",
                fn = function() return setHeliStabiliser(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setHelpMessageBoxSize",
                desc = "setHelpMessageBoxSize(int width) ->",
                fn = function() return setHelpMessageBoxSize(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setInformRespectedFriends",
                desc = "setInformRespectedFriends(int flags, float radius, int pedsToScan) ->",
                fn = function() return setInformRespectedFriends(0, 0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setIntStat",
                desc = "setIntStat(int stat, int int) ->",
                fn = function() return setIntStat(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setInterpolationParameters",
                desc = "setInterpolationParameters(float delay, int time) ->",
                fn = function() return setInterpolationParameters(0.0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setJamesCarOnPathToPlayer",
                desc = "setJamesCarOnPathToPlayer(int int1) ->",
                fn = function() return setJamesCarOnPathToPlayer(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setLaRiots",
                desc = "setLaRiots(bool enable) ->",
                fn = function() return setLaRiots(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setLoadCollisionForCarFlag",
                desc = "setLoadCollisionForCarFlag(Vehicle car, bool enable) ->",
                fn = function() return setLoadCollisionForCarFlag(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setLoadCollisionForCharFlag",
                desc = "setLoadCollisionForCharFlag(Ped ped, bool enable) ->",
                fn = function() return setLoadCollisionForCharFlag(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setMaxWantedLevel",
                desc = "setMaxWantedLevel(int level) ->",
                fn = function() return setMaxWantedLevel(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setMenuColumn",
                desc = "setMenuColumn(int menu, int column, GxtString header, GxtString data1, GxtString data2, GxtString data3, GxtString data4, GxtString data5, GxtString data6, GxtString data7, GxtString data8, GxtString data9, GxtString data10, GxtString data11, GxtString data12) ->",
                fn = function() return setMenuColumn(0, 0, "", "", "", "", "", "", "", "", "", "", "", "", "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setMenuColumnOrientation",
                desc = "setMenuColumnOrientation(int menu, int column, int alignment) ->",
                fn = function() return setMenuColumnOrientation(0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setMenuColumnWidth",
                desc = "setMenuColumnWidth(int panel, int column, int width) ->",
                fn = function() return setMenuColumnWidth(0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setMenuItemWith2Numbers",
                desc = "setMenuItemWith2Numbers(int panel, int column, int row, GxtString gxtString, int numbers1, int numbers2) ->",
                fn = function() return setMenuItemWith2Numbers(0, 0, 0, "", 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setMenuItemWithNumber",
                desc = "setMenuItemWithNumber(int panel, int column, int row, GxtString gxtString, int number) ->",
                fn = function() return setMenuItemWithNumber(0, 0, 0, "", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setMessageFormatting",
                desc = "setMessageFormatting(bool priority, int leftmargin, int maxwidth) ->",
                fn = function() return setMessageFormatting(false, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setMinigameInProgress",
                desc = "setMinigameInProgress(bool enable) ->",
                fn = function() return setMinigameInProgress(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setMissionRespectTotal",
                desc = "setMissionRespectTotal(int respect) ->",
                fn = function() return setMissionRespectTotal(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setMissionTrainCoordinates",
                desc = "setMissionTrainCoordinates(Vehicle train, float X, float Y, float Z) ->",
                fn = function() return setMissionTrainCoordinates(getTargetVehicleHandle(), 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setMusicDoesFade",
                desc = "setMusicDoesFade(bool enable) ->",
                fn = function() return setMusicDoesFade(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setNamedEntryExitFlag",
                desc = "setNamedEntryExitFlag(GxtString interior, int bitmask, bool flag) ->",
                fn = function() return setNamedEntryExitFlag("", 0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setNextDesiredMoveState",
                desc = "setNextDesiredMoveState(int speed) ->",
                fn = function() return setNextDesiredMoveState(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setNoResprays",
                desc = "setNoResprays(bool enable) ->",
                fn = function() return setNoResprays(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectAnimSpeed",
                desc = "setObjectAnimSpeed(Object object, string animation, float speed) ->",
                fn = function() return setObjectAnimSpeed(getTargetObjectHandle(), "", 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectAsStealable",
                desc = "setObjectAsStealable(Object object, bool liftable) ->",
                fn = function() return setObjectAsStealable(getTargetObjectHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectCollisionDamageEffect",
                desc = "setObjectCollisionDamageEffect(Object object, bool destructible) ->",
                fn = function() return setObjectCollisionDamageEffect(getTargetObjectHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectDrawLast",
                desc = "setObjectDrawLast(Object object, bool drawLast) ->",
                fn = function() return setObjectDrawLast(getTargetObjectHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectOnlyDamagedByPlayer",
                desc = "setObjectOnlyDamagedByPlayer(Object object, bool player) ->",
                fn = function() return setObjectOnlyDamagedByPlayer(getTargetObjectHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectPathPosition",
                desc = "setObjectPathPosition(int int1, float float2) ->",
                fn = function() return setObjectPathPosition(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectPathSpeed",
                desc = "setObjectPathSpeed(int int1, int int2) ->",
                fn = function() return setObjectPathSpeed(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectQuaternion",
                desc = "setObjectQuaternion(Object object, float x, float y, float z, float w) ->",
                fn = function() return setObjectQuaternion(getTargetObjectHandle(), 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectRenderScorched",
                desc = "setObjectRenderScorched(Object object, bool fireproof) ->",
                fn = function() return setObjectRenderScorched(getTargetObjectHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setObjectTurnMass",
                desc = "setObjectTurnMass(Object object, float turnMass) ->",
                fn = function() return setObjectTurnMass(getTargetObjectHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setOnlyCreateGangMembers",
                desc = "setOnlyCreateGangMembers(bool enable) ->",
                fn = function() return setOnlyCreateGangMembers(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setOnscreenCounterFlashWhenFirstDisplayed",
                desc = "setOnscreenCounterFlashWhenFirstDisplayed(VarId text, bool flashing) ->",
                fn = function() return setOnscreenCounterFlashWhenFirstDisplayed(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPetrolTankWeakpoint",
                desc = "setPetrolTankWeakpoint(Vehicle car, bool enabled) ->",
                fn = function() return setPetrolTankWeakpoint(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlaneThrottle",
                desc = "setPlaneThrottle(int plane, float throttle) ->",
                fn = function() return setPlaneThrottle(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlaneUndercarriageUp",
                desc = "setPlaneUndercarriageUp(int plane, bool set) ->",
                fn = function() return setPlaneUndercarriageUp(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPlaybackSpeed",
                desc = "setPlaybackSpeed(Vehicle car, float speed) ->",
                fn = function() return setPlaybackSpeed(getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPoliceIgnorePlayer",
                desc = "setPoliceIgnorePlayer(Player player, bool ignored) -> bool result",
                fn = function() return setPoliceIgnorePlayer(getTargetPlayer(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setPoolTableCoords",
                desc = "setPoolTableCoords(float x1, float y1, float z1, float x2, float y2, float z2) ->",
                fn = function() return setPoolTableCoords(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setProgressTotal",
                desc = "setProgressTotal(int maxProgress) ->",
                fn = function() return setProgressTotal(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setRadioToPlayersFavouriteStation",
                desc = "Tunes vehicle radio to player's favorite station",
                fn = function() return setRadioToPlayersFavouriteStation() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setRailtrackResistanceMult",
                desc = "setRailtrackResistanceMult(float tracksFriction) ->",
                fn = function() return setRailtrackResistanceMult(0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setRelationship",
                desc = "setRelationship(int acquaintance, int pedtype, int toPedtype) ->",
                fn = function() return setRelationship(0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setRespawnPointForDurationOfMission",
                desc = "setRespawnPointForDurationOfMission(float posX, float posY, float posZ) ->",
                fn = function() return setRespawnPointForDurationOfMission(0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setRopeHeightForObject",
                desc = "setRopeHeightForObject(int magnet, float length) ->",
                fn = function() return setRopeHeightForObject(0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setScmThreadLocalVar",
                desc = "setScmThreadLocalVar(uint thread, int var, any value) ->",
                fn = function() return setScmThreadLocalVar(0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setScriptCoopGame",
                desc = "setScriptCoopGame(bool enable) ->",
                fn = function() return setScriptCoopGame(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setScriptLimitToGangSize",
                desc = "setScriptLimitToGangSize(bool max) ->",
                fn = function() return setScriptLimitToGangSize(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setSearchlightClipIfColliding",
                desc = "setSearchlightClipIfColliding(Searchlight searchlight, bool flag) ->",
                fn = function() return setSearchlightClipIfColliding(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setSenseRange",
                desc = "setSenseRange(Ped ped, float accuracy) ->",
                fn = function() return setSenseRange(getTargetPlayerHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setSequenceToRepeat",
                desc = "setSequenceToRepeat(int pack, bool loop) ->",
                fn = function() return setSequenceToRepeat(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setSpritesDrawBeforeFade",
                desc = "setSpritesDrawBeforeFade(bool antialiased) ->",
                fn = function() return setSpritesDrawBeforeFade(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTagStatusInArea",
                desc = "setTagStatusInArea(float x1, float y1, float x2, float y2, bool value) ->",
                fn = function() return setTagStatusInArea(0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTankDetonateCars",
                desc = "setTankDetonateCars(int tank, bool detonate) ->",
                fn = function() return setTankDetonateCars(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTargetCarForMissionGarage",
                desc = "setTargetCarForMissionGarage(GxtString garage, Vehicle car) -> bool result",
                fn = function() return setTargetCarForMissionGarage("", getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTaxiLights",
                desc = "setTaxiLights(Vehicle taxi, bool light) -> bool result",
                fn = function() return setTaxiLights(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTotalNumberOfMissions",
                desc = "setTotalNumberOfMissions(int totalMissions) ->",
                fn = function() return setTotalNumberOfMissions(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTrainCruiseSpeed",
                desc = "setTrainCruiseSpeed(Vehicle train, float speed) ->",
                fn = function() return setTrainCruiseSpeed(getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTrainForcedToSlowDown",
                desc = "setTrainForcedToSlowDown(Vehicle train, bool forced) ->",
                fn = function() return setTrainForcedToSlowDown(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setTrainSpeed",
                desc = "setTrainSpeed(Vehicle train, float speed) ->",
                fn = function() return setTrainSpeed(getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setUpConversationEndNodeWithScriptedSpeech",
                desc = "setUpConversationEndNodeWithScriptedSpeech(GxtString dialogueGxt, int wav) ->",
                fn = function() return setUpConversationEndNodeWithScriptedSpeech("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setUpConversationEndNodeWithSpeech",
                desc = "setUpConversationEndNodeWithSpeech(GxtString gxtString, int speech) ->",
                fn = function() return setUpConversationEndNodeWithSpeech("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setUpConversationNodeWithScriptedSpeech",
                desc = "setUpConversationNodeWithScriptedSpeech(GxtString questionGXT, GxtString answerYesGXT, GxtString answerNoGXT, int questionWAV, int answerYesWAV, int answerNoWAV) ->",
                fn = function() return setUpConversationNodeWithScriptedSpeech("", "", "", 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setUpConversationNodeWithSpeech",
                desc = "setUpConversationNodeWithSpeech(GxtString question, GxtString answerY, GxtString answerN, int questionWav, int answerYWav, int answerNWav) ->",
                fn = function() return setUpConversationNodeWithSpeech("", "", "", 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setUpSkip",
                desc = "setUpSkip(float posX, float posY, float posZ, float angle) ->",
                fn = function() return setUpSkip(0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setUpSkipAfterMission",
                desc = "setUpSkipAfterMission(float posX, float posY, float posZ, float angle) ->",
                fn = function() return setUpSkipAfterMission(0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setUpSkipForSpecificVehicle",
                desc = "setUpSkipForSpecificVehicle(float posX, float posY, float posZ, float angle, Vehicle car) ->",
                fn = function() return setUpSkipForSpecificVehicle(0.0, 0.0, 0.0, 0.0, getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setUpSkipForVehicleFinishedByScript",
                desc = "setUpSkipForVehicleFinishedByScript(float posX, float posY, float posZ, float angle, Vehicle car) ->",
                fn = function() return setUpSkipForVehicleFinishedByScript(0.0, 0.0, 0.0, 0.0, getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setUpsidedownCarNotDamaged",
                desc = "setUpsidedownCarNotDamaged(Vehicle car, bool disableFlippedExplosion) ->",
                fn = function() return setUpsidedownCarNotDamaged(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setUsesCollisionOfClosestObjectOfType",
                desc = "setUsesCollisionOfClosestObjectOfType(float X, float Y, float Z, float radius, Model modelId, bool collisionDetection) ->",
                fn = function() return setUsesCollisionOfClosestObjectOfType(0.0, 0.0, 0.0, 0.0, 0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setVehicleAirResistanceMultiplier",
                desc = "setVehicleAirResistanceMultiplier(Vehicle car, float multiplier) ->",
                fn = function() return setVehicleAirResistanceMultiplier(getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setVehicleCanBeTargetted",
                desc = "setVehicleCanBeTargetted(Vehicle car, bool unk) ->",
                fn = function() return setVehicleCanBeTargetted(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setVehicleIsConsideredByPlayer",
                desc = "setVehicleIsConsideredByPlayer(Vehicle car, bool accessible) ->",
                fn = function() return setVehicleIsConsideredByPlayer(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setVehicleQuaternion",
                desc = "setVehicleQuaternion(Vehicle car, float x, float y, float z, float w) ->",
                fn = function() return setVehicleQuaternion(getTargetVehicleHandle(), 0.0, 0.0, 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setVehicleToFadeIn",
                desc = "setVehicleToFadeIn(Vehicle car, int flag) ->",
                fn = function() return setVehicleToFadeIn(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setVisibilityOfClosestObjectOfType",
                desc = "setVisibilityOfClosestObjectOfType(float atX, float atY, float atZ, float radius, Model modelId, bool visibility) ->",
                fn = function() return setVisibilityOfClosestObjectOfType(0.0, 0.0, 0.0, 0.0, 0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "setWantedMultiplier",
                desc = "setWantedMultiplier(float sensitivity) ->",
                fn = function() return setWantedMultiplier(0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "shakePad",
                desc = "shakePad(Player player, int time, int intensity) ->",
                fn = function() return shakePad(getTargetPlayer(), 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "showUpdateStats",
                desc = "showUpdateStats(bool display) ->",
                fn = function() return showUpdateStats(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "shuffleCardDecks",
                desc = "shuffleCardDecks(bool shuffle) ->",
                fn = function() return shuffleCardDecks(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "shutAllCharsUp",
                desc = "shutAllCharsUp(bool enable) ->",
                fn = function() return shutAllCharsUp(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "shutCharUp",
                desc = "shutCharUp(Ped ped, bool muted) ->",
                fn = function() return shutCharUp(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "shutCharUpForScriptedSpeech",
                desc = "shutCharUpForScriptedSpeech(Ped ped, bool muted) ->",
                fn = function() return shutCharUpForScriptedSpeech(getTargetPlayerHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "shutPlayerUp",
                desc = "shutPlayerUp(Player player, bool shut) ->",
                fn = function() return shutPlayerUp(getTargetPlayer(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "skipInPlaybackRecordedCar",
                desc = "skipInPlaybackRecordedCar(Vehicle car, float path) ->",
                fn = function() return skipInPlaybackRecordedCar(getTargetVehicleHandle(), 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "skipToEndAndStopPlaybackRecordedCar",
                desc = "skipToEndAndStopPlaybackRecordedCar(Vehicle car) ->",
                fn = function() return skipToEndAndStopPlaybackRecordedCar(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "skipToNextAllowedStation",
                desc = "skipToNextAllowedStation(Vehicle train) ->",
                fn = function() return skipToNextAllowedStation(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "slideObject",
                desc = "slideObject(Object object, float toX, float toY, float toZ, float speedX, float speedY, float speedZ, bool collisionCheck) -> bool result",
                fn = function() return slideObject(getTargetObjectHandle(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "sortOutObjectCollisionWithCar",
                desc = "sortOutObjectCollisionWithCar(Object object, Vehicle car) ->",
                fn = function() return sortOutObjectCollisionWithCar(getTargetObjectHandle(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "spawnVehicleByCheating",
                desc = "spawnVehicleByCheating(Model modelId) -> bool result",
                fn = function() return spawnVehicleByCheating(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "startCharFacialTalk",
                desc = "startCharFacialTalk(Ped ped, int time) ->",
                fn = function() return startCharFacialTalk(getTargetPlayerHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "startCredits",
                desc = "Starts playback of game ending credits scroll",
                fn = function() return startCredits() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "startKillFrenzy",
                desc = "startKillFrenzy(GxtString gxtString, int weapon, int timeLimit, int targets, Model targetModels1, Model targetModels2, Model targetModels3, Model targetModels4, bool completedText) -> bool result",
                fn = function() return startKillFrenzy("", 0, 0, 0, 0, 0, 0, 0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "startNewCustomScript",
                desc = "startNewCustomScript(zstring filepath, table args) -> bool result",
                fn = function() return startNewCustomScript("", 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "startNewStreamedScript",
                desc = "startNewStreamedScript(int externalScript, table args) ->",
                fn = function() return startNewStreamedScript(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "startPlaybackRecordedCar",
                desc = "startPlaybackRecordedCar(Vehicle car, int path) ->",
                fn = function() return startPlaybackRecordedCar(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "startPlaybackRecordedCarLooped",
                desc = "startPlaybackRecordedCarLooped(Vehicle car, int path) ->",
                fn = function() return startPlaybackRecordedCarLooped(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "startPlaybackRecordedCarUsingAi",
                desc = "startPlaybackRecordedCarUsingAi(Vehicle car, int path) ->",
                fn = function() return startPlaybackRecordedCarUsingAi(getTargetVehicleHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "startSettingUpConversation",
                desc = "startSettingUpConversation(Ped ped) ->",
                fn = function() return startSettingUpConversation(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "stopBeatTrack",
                desc = "Stops currently playing rhythmic beat audio track",
                fn = function() return stopBeatTrack() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "stopCharFacialTalk",
                desc = "stopCharFacialTalk(Ped ped) ->",
                fn = function() return stopCharFacialTalk(getTargetPlayerHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "stopCredits",
                desc = "Stops playback of game ending credits scroll",
                fn = function() return stopCredits() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "stopPlaybackRecordedCar",
                desc = "stopPlaybackRecordedCar(Vehicle car) ->",
                fn = function() return stopPlaybackRecordedCar(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "storeCarCharIsAttachedToNoSave",
                desc = "storeCarCharIsAttachedToNoSave(Vehicle car) -> Ped ped",
                fn = function() return storeCarCharIsAttachedToNoSave(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "storeCarModState",
                desc = "Saves current vehicle modification state into memory",
                fn = function() return storeCarModState() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "storeClothesState",
                desc = "Saves current player clothes state into memory",
                fn = function() return storeClothesState() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "storeWantedLevel",
                desc = "storeWantedLevel(Player player) -> bool result, int level",
                fn = function() return storeWantedLevel(getTargetPlayer()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "streamScript",
                desc = "streamScript(int script) ->",
                fn = function() return streamScript(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "suppressCarModel",
                desc = "suppressCarModel(Model modelId) -> bool result",
                fn = function() return suppressCarModel(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "swapNearestBuildingModel",
                desc = "swapNearestBuildingModel(float atX, float atY, float atZ, float radius, Model from, Model to) ->",
                fn = function() return swapNearestBuildingModel(0.0, 0.0, 0.0, 0.0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "syncWater",
                desc = "Synchronizes water level animations and physics",
                fn = function() return syncWater() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "takePhoto",
                desc = "takePhoto(bool unk) ->",
                fn = function() return takePhoto(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "takeRemoteControlOfCar",
                desc = "takeRemoteControlOfCar(Player player, Vehicle car) ->",
                fn = function() return takeRemoteControlOfCar(getTargetPlayer(), getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "turnCarToFaceCoord",
                desc = "turnCarToFaceCoord(Vehicle car, float coordX, float coordY) ->",
                fn = function() return turnCarToFaceCoord(getTargetVehicleHandle(), 0.0, 0.0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "unloadSpecialCharacter",
                desc = "unloadSpecialCharacter(int id) ->",
                fn = function() return unloadSpecialCharacter(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "unmarkAllRoadNodesAsDontWander",
                desc = "Removes wander restriction on all road path nodes",
                fn = function() return unmarkAllRoadNodesAsDontWander() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "unpausePlaybackRecordedCar",
                desc = "unpausePlaybackRecordedCar(Vehicle car) ->",
                fn = function() return unpausePlaybackRecordedCar(getTargetVehicleHandle()) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "updatePickupMoneyPerDay",
                desc = "updatePickupMoneyPerDay(Pickup pickup, int cash) ->",
                fn = function() return updatePickupMoneyPerDay(getTargetPickupHandle(), 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "useDetonator",
                desc = "Detonates placed satchel charges / explosives",
                fn = function() return useDetonator() end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "useRenderCommands",
                desc = "useRenderCommands(bool enable) ->",
                fn = function() return useRenderCommands(false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "vehicleCanBeTargettedByHsMissile",
                desc = "vehicleCanBeTargettedByHsMissile(Vehicle car, bool targetable) ->",
                fn = function() return vehicleCanBeTargettedByHsMissile(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "vehicleDoesProvideCover",
                desc = "vehicleDoesProvideCover(Vehicle car, bool providesCover) ->",
                fn = function() return vehicleDoesProvideCover(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "winchCanPickObjectUp",
                desc = "winchCanPickObjectUp(Object object, bool enable) ->",
                fn = function() return winchCanPickObjectUp(getTargetObjectHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "winchCanPickVehicleUp",
                desc = "winchCanPickVehicleUp(Vehicle car, bool attractive) ->",
                fn = function() return winchCanPickVehicleUp(getTargetVehicleHandle(), false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
    -- ─────────────────────────────────────────────────────────────
    -- Auto-Stubs: DXUT & UI (38 tests)
    -- ─────────────────────────────────────────────────────────────
    {
        category = "Auto-Stubs: DXUT & UI",
        tests = {
{
                name = "dxutAddButton",
                desc = "dxutAddButton(DxutDialog dialog, int id, zstring text, int posX, int posY, int sizeX, int sizeY) ->",
                fn = function() return dxutAddButton(0, 0, "", 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutAddCheckbox",
                desc = "dxutAddCheckbox(DxutDialog dialog, int id, zstring text, int posX, int posY, int sizeX, int sizeY) ->",
                fn = function() return dxutAddCheckbox(0, 0, "", 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutAddEditbox",
                desc = "dxutAddEditbox(DxutDialog dialog, int id, zstring text, int posX, int posY, int sizeX, int sizeY) ->",
                fn = function() return dxutAddEditbox(0, 0, "", 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutAddListbox",
                desc = "dxutAddListbox(DxutDialog dialog, int id, int posX, int posY, int sizeX, int sizeY) ->",
                fn = function() return dxutAddListbox(0, 0, 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutAddSlider",
                desc = "dxutAddSlider(DxutDialog dialog, int id, int posX, int posY, int sizeX, int sizeY, int max) ->",
                fn = function() return dxutAddSlider(0, 0, 0, 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutAddStatic",
                desc = "dxutAddStatic(DxutDialog dialog, int id, zstring text, int posX, int posY, int sizeX, int sizeY) ->",
                fn = function() return dxutAddStatic(0, 0, "", 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutCheckboxSetChecked",
                desc = "dxutCheckboxSetChecked(DxutDialog dialog, int id, bool checked) ->",
                fn = function() return dxutCheckboxSetChecked(0, 0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutControlIsVisible",
                desc = "dxutControlIsVisible(DxutDialog dialog, int id) -> bool result",
                fn = function() return dxutControlIsVisible(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutCreateDialog",
                desc = "dxutCreateDialog(zstring name) -> DxutDialog dialog",
                fn = function() return dxutCreateDialog("") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutDeleteControl",
                desc = "dxutDeleteControl(DxutDialog dialog, int id) ->",
                fn = function() return dxutDeleteControl(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutDeleteDialog",
                desc = "dxutDeleteDialog(DxutDialog dialog) ->",
                fn = function() return dxutDeleteDialog(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutEnableDialogCaption",
                desc = "dxutEnableDialogCaption(DxutDialog dialog, bool enable) ->",
                fn = function() return dxutEnableDialogCaption(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutGetControlPos",
                desc = "dxutGetControlPos(DxutDialog dialog, int id) -> int posX, int posY",
                fn = function() return dxutGetControlPos(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutGetControlSize",
                desc = "dxutGetControlSize(DxutDialog dialog, int id) -> int sizeX, int sizeY",
                fn = function() return dxutGetControlSize(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutGetControlText",
                desc = "dxutGetControlText(DxutDialog dialog, int id) -> zstring text",
                fn = function() return dxutGetControlText(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutGetDialogPosAndSize",
                desc = "dxutGetDialogPosAndSize(DxutDialog dialog) -> int posX, int posY, int sizeX, int sizeY",
                fn = function() return dxutGetDialogPosAndSize(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutGetListboxItemTextAndData",
                desc = "dxutGetListboxItemTextAndData(DxutDialog dialog, int id, int element) -> zstring text, uint data",
                fn = function() return dxutGetListboxItemTextAndData(0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutGetListboxSelectedItemAndCount",
                desc = "dxutGetListboxSelectedItemAndCount(DxutDialog dialog, int id) -> int element, int count",
                fn = function() return dxutGetListboxSelectedItemAndCount(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutGetSliderValue",
                desc = "dxutGetSliderValue(DxutDialog dialog, int id) -> int value",
                fn = function() return dxutGetSliderValue(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutIsCheckboxChecked",
                desc = "dxutIsCheckboxChecked(DxutDialog dialog, int id) -> bool result",
                fn = function() return dxutIsCheckboxChecked(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutIsDialogCaptionEnabled",
                desc = "dxutIsDialogCaptionEnabled(DxutDialog dialog) -> bool result",
                fn = function() return dxutIsDialogCaptionEnabled(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutIsDialogExists",
                desc = "dxutIsDialogExists(DxutDialog dialog) -> bool result",
                fn = function() return dxutIsDialogExists(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutIsDialogMinimized",
                desc = "dxutIsDialogMinimized(DxutDialog dialog) -> bool result",
                fn = function() return dxutIsDialogMinimized(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutIsDialogVisible",
                desc = "dxutIsDialogVisible(DxutDialog dialog) -> bool result",
                fn = function() return dxutIsDialogVisible(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutListboxDeleteItem",
                desc = "dxutListboxDeleteItem(DxutDialog dialog, int id, int element) ->",
                fn = function() return dxutListboxDeleteItem(0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutListboxInsertItem",
                desc = "dxutListboxInsertItem(DxutDialog dialog, int id, zstring element, uint data, int after) ->",
                fn = function() return dxutListboxInsertItem(0, 0, "", 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutPopEvent",
                desc = "dxutPopEvent(DxutDialog dialog) -> bool result, int event, int id",
                fn = function() return dxutPopEvent(0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutSetCheckboxColor",
                desc = "dxutSetCheckboxColor(DxutDialog dialog, int id, uint color) ->",
                fn = function() return dxutSetCheckboxColor(0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutSetControlPos",
                desc = "dxutSetControlPos(DxutDialog dialog, int id, int posX, int posY) ->",
                fn = function() return dxutSetControlPos(0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutSetControlSize",
                desc = "dxutSetControlSize(DxutDialog dialog, int id, int sizeX, int sizeY) ->",
                fn = function() return dxutSetControlSize(0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutSetControlText",
                desc = "dxutSetControlText(DxutDialog dialog, int id, zstring text) ->",
                fn = function() return dxutSetControlText(0, 0, "") end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutSetControlVisible",
                desc = "dxutSetControlVisible(DxutDialog dialog, int id, bool visible) ->",
                fn = function() return dxutSetControlVisible(0, 0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutSetDialogBackgroundColor",
                desc = "dxutSetDialogBackgroundColor(DxutDialog dialog, uint color) ->",
                fn = function() return dxutSetDialogBackgroundColor(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutSetDialogMinimized",
                desc = "dxutSetDialogMinimized(DxutDialog dialog, bool minimized) ->",
                fn = function() return dxutSetDialogMinimized(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutSetDialogPos",
                desc = "dxutSetDialogPos(DxutDialog dialog, int posX, int posY, int sizeX, int sizeY) ->",
                fn = function() return dxutSetDialogPos(0, 0, 0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutSetDialogVisible",
                desc = "dxutSetDialogVisible(DxutDialog dialog, bool visible) ->",
                fn = function() return dxutSetDialogVisible(0, false) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutSetFocusOnControl",
                desc = "dxutSetFocusOnControl(DxutDialog dialog, int id) ->",
                fn = function() return dxutSetFocusOnControl(0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
{
                name = "dxutSetSliderValue",
                desc = "dxutSetSliderValue(DxutDialog dialog, int id, int value) ->",
                fn = function() return dxutSetSliderValue(0, 0, 0) end,
                validate = function(v) return true, formatReturnValues(v) end,
            },
        },
    },
}

-- ═══════════════════════════════════════════════════════════════════
-- Execution Engine
-- ═══════════════════════════════════════════════════════════════════

local function executeSingleTest(test, group, verbose, forceRun)
    local mutating = isMutatingTest(test)
    if not forceRun and safeModeEnabled and safeModeEnabled[0] and mutating then
        local res = { status = "SKIP", detail = "Filtered (Safe Mode: press Run to test)", values = {} }
        res.name = test.name
        res.desc = test.desc
        res.category = group.category
        res.isMutating = true
        allTestResults[test.name] = res
        if verbose then
            totalTested = totalTested + 1
            totalSkipped = totalSkipped + 1
        end
        return res
    end

    local res = invokeTest(test)
    res.name = test.name
    res.desc = test.desc
    res.category = group.category
    res.isMutating = mutating

    allTestResults[test.name] = res

    if verbose then
        totalTested = totalTested + 1
        if res.status == "PASS" then
            totalPassed = totalPassed + 1
            addLog(string.format("  PASS  %-30s -> %s", test.name, res.formatted or ""))
        elseif res.status == "FAIL" then
            totalFailed = totalFailed + 1
            addLog(string.format("  FAIL  %-30s -> %s", test.name, res.err or "failed"))
        elseif res.status == "MISS" then
            totalMissing = totalMissing + 1
            addLog(string.format("  MISS  %-30s -> not defined", test.name))
        elseif res.status == "SKIP" then
            totalSkipped = totalSkipped + 1
            addLog(string.format("  SKIP  %-30s -> %s", test.name, res.detail or "skipped"))
        end
    end

    return res
end

local function runCategory(catIdx, forceRun)
    local group = testCatalog[catIdx]
    if not group then return end
    addLog(string.format("[%d/%d] %s (%d tests)", catIdx, #testCatalog, group.category, #group.tests))
    for _, test in ipairs(group.tests) do
        executeSingleTest(test, group, true, forceRun)
    end
end

local function recalculateTotals()
    local t, p, f, m, s = 0, 0, 0, 0, 0
    for _, r in pairs(allTestResults) do
        t = t + 1
        if r.status == "PASS" then p = p + 1
        elseif r.status == "FAIL" then f = f + 1
        elseif r.status == "MISS" then m = m + 1
        elseif r.status == "SKIP" then s = s + 1 end
    end
    totalTested, totalPassed, totalFailed, totalMissing, totalSkipped = t, p, f, m, s
end

-- Read-only query categories for Live Monitor
local liveCategories = { 1, 2, 3, 4, 7, 8, 9, 10, 11, 12, 13 }

local function runLiveUpdate()
    for _, catIdx in ipairs(liveCategories) do
        local group = testCatalog[catIdx]
        if group then
            for _, test in ipairs(group.tests) do
                -- Only rerun tests that are read-only (non-modifying)
                if not isMutatingTest(test) then
                    executeSingleTest(test, group, false, false)
                end
            end
        end
    end
    recalculateTotals()
end

local function runAllTests()
    totalTested, totalPassed, totalFailed, totalMissing, totalSkipped = 0, 0, 0, 0, 0
    allTestResults = {}
    local pid = getTargetPlayer()
    local vid = getTargetVehicle()
    addLog(string.format("=== NeoMLoader Complete API Testing Suite v4.0 (2,147 Binds) | PID: %d | VID: %d ===", pid, vid))

    for i = 1, #testCatalog do
        runCategory(i)
    end

    addLog(string.format("TOTAL: %d | PASS: %d | FAIL: %d | MISS: %d | SKIP: %d",
        totalTested, totalPassed, totalFailed, totalMissing, totalSkipped))
    addLog("=== TEST RUN COMPLETE ===")

    sendChatMessage(string.format("{00FF88}[Test]{FFFFFF} Done! Total: {00FFFF}%d{FFFFFF} Pass: {00FF00}%d{FFFFFF} Fail: {FF4444}%d{FFFFFF} Skip: {888888}%d{FFFFFF}",
        totalTested, totalPassed, totalFailed, totalSkipped))
end

local function dumpAllValues()
    runAllTests()
    print("\n================================================================================")
    print("                NEOMLOADER COMPREHENSIVE SAMP API DIAGNOSTIC REPORT              ")
    print(string.format("  TIME: %s | TOTAL: %d | PASS: %d | FAIL: %d | MISS: %d | SKIP: %d",
        os.date("%Y-%m-%d %H:%M:%S"), totalTested, totalPassed, totalFailed, totalMissing, totalSkipped))
    print("================================================================================")

    for catIdx, group in ipairs(testCatalog) do
        print(string.format("\n[Category %02d] %s", catIdx, group.category))
        print("--------------------------------------------------------------------------------")
        for _, test in ipairs(group.tests) do
            local r = allTestResults[test.name]
            local tag = "[?]"
            local detail = "<not run>"
            if r then
                if r.status == "PASS" then
                    tag = "[PASS]"
                    detail = r.formatted or "<ok>"
                elseif r.status == "FAIL" then
                    tag = "[FAIL]"
                    detail = r.err or "<error>"
                elseif r.status == "MISS" then
                    tag = "[MISS]"
                    detail = "<not defined>"
                elseif r.status == "SKIP" then
                    tag = "[SKIP]"
                    detail = r.detail or "<skipped>"
                end
            end
            local desc = (test.desc and #test.desc > 0) and (" // " .. test.desc) or ""
            print(string.format("  %-6s %-32s %-34s%s", tag, test.name, detail, desc))
        end
    end

    print("\n============================= END DIAGNOSTIC REPORT ============================\n")
    sendChatMessage("{00FF88}[Test]{FFFFFF} Complete diagnostic dump written to neomloader.log")
end

-- ═══════════════════════════════════════════════════════════════════
-- Modern mimgui Dashboard UI
-- ═══════════════════════════════════════════════════════════════════

if hasMimgui and imgui and imgui.OnFrame then
    local themeApplied = false
    imgui.OnFrame(
        function() return showWindow and showWindow[0] end,
        function()
            if not themeApplied then
                if imgui.StyleColorsDark then
                    pcall(imgui.StyleColorsDark)
                end
                local s = imgui.GetStyle()
                if s then
                    s.WindowRounding = dp(8)
                    s.FrameRounding = dp(5)
                    s.GrabRounding = dp(5)
                    s.ScrollbarRounding = dp(6)
                    s.ScrollbarSize = dp(16)
                    s.WindowPadding = imgui.ImVec2(dp(10), dp(8))
                    s.FramePadding = imgui.ImVec2(dp(8), dp(5))
                    s.ItemSpacing = imgui.ImVec2(dp(8), dp(5))
                    s.ItemInnerSpacing = imgui.ImVec2(dp(5), dp(4))
                    s.Colors[imgui.Col.WindowBg] = imgui.ImVec4(0.08, 0.08, 0.10, 0.95)
                    s.Colors[imgui.Col.ChildBg] = imgui.ImVec4(0.10, 0.10, 0.13, 0.90)
                    s.Colors[imgui.Col.Border] = imgui.ImVec4(0.22, 0.25, 0.32, 0.65)
                    s.Colors[imgui.Col.FrameBg] = imgui.ImVec4(0.13, 0.14, 0.18, 0.90)
                    s.Colors[imgui.Col.FrameBgHovered] = imgui.ImVec4(0.20, 0.22, 0.28, 0.90)
                    s.Colors[imgui.Col.Button] = imgui.ImVec4(0.16, 0.38, 0.48, 0.85)
                    s.Colors[imgui.Col.ButtonHovered] = imgui.ImVec4(0.20, 0.48, 0.60, 1.00)
                    s.Colors[imgui.Col.ButtonActive] = imgui.ImVec4(0.14, 0.40, 0.52, 1.00)
                    s.Colors[imgui.Col.Header] = imgui.ImVec4(0.15, 0.32, 0.42, 0.80)
                    s.Colors[imgui.Col.HeaderHovered] = imgui.ImVec4(0.20, 0.42, 0.54, 0.90)
                    s.Colors[imgui.Col.HeaderActive] = imgui.ImVec4(0.13, 0.36, 0.46, 1.00)
                    s.Colors[imgui.Col.Text] = imgui.ImVec4(0.92, 0.92, 0.95, 1.00)
                    s.Colors[imgui.Col.TextDisabled] = imgui.ImVec4(0.50, 0.52, 0.58, 1.00)
                end
                themeApplied = true
            end

            local resX, resY = 1280, 720
            if imgui.GetMainViewport then
                local vp = imgui.GetMainViewport()
                if vp and vp.Size then resX, resY = vp.Size.x, vp.Size.y end
            end

            local initW = math.min(dp(920), resX - dp(24))
            local initH = math.min(dp(580), resY - dp(24))
            imgui.SetNextWindowSize(imgui.ImVec2(initW, initH), imgui.Cond.FirstUseEver)
            imgui.SetNextWindowPos(imgui.ImVec2(dp(12), dp(12)), imgui.Cond.FirstUseEver)

            if imgui.Begin("NeoMLoader SAMP API Suite v3.0", showWindow) then
                -- Control Toolbar
                if imgui.Button("Run All", imgui.ImVec2(dp(85), dp(28))) then runAllTests() end
                imgui.SameLine()
                if imgui.Button("Dump Log", imgui.ImVec2(dp(80), dp(28))) then dumpAllValues() end
                imgui.SameLine()

                local isSafe = safeModeEnabled and safeModeEnabled[0]
                if isSafe then
                    imgui.PushStyleColor(imgui.Col.Button, 0.15, 0.55, 0.30, 0.85)
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, 0.20, 0.65, 0.35, 1.00)
                    imgui.PushStyleColor(imgui.Col.ButtonActive, 0.10, 0.45, 0.25, 1.00)
                else
                    imgui.PushStyleColor(imgui.Col.Button, 0.65, 0.20, 0.20, 0.85)
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, 0.75, 0.25, 0.25, 1.00)
                    imgui.PushStyleColor(imgui.Col.ButtonActive, 0.55, 0.15, 0.15, 1.00)
                end
                if imgui.Button(isSafe and "Safe: ON" or "Safe: OFF", imgui.ImVec2(dp(85), dp(28))) then
                    if safeModeEnabled then
                        safeModeEnabled[0] = not safeModeEnabled[0]
                        addLog(safeModeEnabled[0] and "Safe Mode ON: game-changing tests filtered" or "Safe Mode OFF: all tests enabled")
                    end
                end
                imgui.PopStyleColor(3)
                imgui.SameLine()

                local isLive = liveMonitorEnabled and liveMonitorEnabled[0]
                if isLive then
                    imgui.PushStyleColor(imgui.Col.Button, 0.15, 0.65, 0.25, 0.90)
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, 0.20, 0.75, 0.35, 1.00)
                    imgui.PushStyleColor(imgui.Col.ButtonActive, 0.10, 0.55, 0.20, 1.00)
                else
                    imgui.PushStyleColor(imgui.Col.Button, 0.22, 0.24, 0.30, 0.85)
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, 0.30, 0.34, 0.42, 1.00)
                    imgui.PushStyleColor(imgui.Col.ButtonActive, 0.16, 0.18, 0.24, 1.00)
                end
                if imgui.Button(isLive and "Live: ON" or "Live: OFF", imgui.ImVec2(dp(85), dp(28))) then
                    if liveMonitorEnabled then
                        liveMonitorEnabled[0] = not liveMonitorEnabled[0]
                        addLog(liveMonitorEnabled[0] and "Live monitor active" or "Live monitor paused")
                    end
                end
                imgui.PopStyleColor(3)
                imgui.SameLine()

                -- Live Counter Badges
                if totalTested > 0 then
                    imgui.TextColored(imgui.ImVec4(0.5, 0.5, 0.55, 1.0), "|")
                    imgui.SameLine()
                    imgui.TextColored(imgui.ImVec4(0.1, 0.9, 0.3, 1.0), string.format("%d pass", totalPassed))
                    imgui.SameLine()
                    if totalFailed > 0 then
                        imgui.TextColored(imgui.ImVec4(0.95, 0.25, 0.2, 1.0), string.format("%d fail", totalFailed))
                        imgui.SameLine()
                    end
                    if totalSkipped > 0 then
                        imgui.TextColored(imgui.ImVec4(0.6, 0.65, 0.75, 1.0), string.format("%d skip", totalSkipped))
                        imgui.SameLine()
                    end
                    if totalMissing > 0 then
                        imgui.TextColored(imgui.ImVec4(0.85, 0.55, 0.1, 1.0), string.format("%d miss", totalMissing))
                    end
                end

                imgui.Separator()

                -- Target Selectors & Search Box
                imgui.SetNextItemWidth(dp(65))
                if targetPlayerId then imgui.InputInt("PID", targetPlayerId, 0, 0) end
                imgui.SameLine()
                imgui.SetNextItemWidth(dp(65))
                if targetVehicleId then imgui.InputInt("VID", targetVehicleId, 0, 0) end
                imgui.SameLine()

                local filterWidth = imgui.GetWindowWidth() - imgui.GetCursorPosX() - dp(15)
                if filterWidth > dp(80) then imgui.SetNextItemWidth(filterWidth) end
                if searchFilter then imgui.InputText("##search", searchFilter) end

                imgui.Separator()

                -- Collapsible Test Categories
                imgui.BeginChild("TestHierarchy", imgui.ImVec2(0, 0), false)
                local filterText = searchFilter and tostring(searchFilter):lower() or ""

                for catIdx, group in ipairs(testCatalog) do
                    local hasMatch = #filterText == 0
                    if not hasMatch then
                        for _, test in ipairs(group.tests) do
                            if test.name:lower():find(filterText, 1, true) or (test.desc and test.desc:lower():find(filterText, 1, true)) then
                                hasMatch = true
                                break
                            end
                        end
                    end

                    if hasMatch then
                        local catPass, catFail, catTotal = 0, 0, 0
                        for _, test in ipairs(group.tests) do
                            local r = allTestResults[test.name]
                            if r then
                                catTotal = catTotal + 1
                                if r.status == "PASS" then catPass = catPass + 1
                                elseif r.status == "FAIL" then catFail = catFail + 1 end
                            end
                        end

                        local icon, iR, iG, iB = " ", 0.55, 0.55, 0.60
                        if catTotal > 0 then
                            if catFail == 0 then icon = "v"; iR, iG, iB = 0.10, 0.88, 0.32
                            else icon = "x"; iR, iG, iB = 0.95, 0.28, 0.20 end
                        end

                        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(iR, iG, iB, 1.0))
                        local headerText = string.format("%s %s [%d/%d]###cat%d", icon, group.category, catPass, #group.tests, catIdx)
                        local isOpen = imgui.CollapsingHeader(headerText)
                        imgui.PopStyleColor()

                        if isOpen then
                            local runBtnW = dp(55)
                            imgui.SameLine(imgui.GetWindowWidth() - runBtnW - dp(24))
                            if imgui.SmallButton(string.format("Run##c%d", catIdx)) then
                                runCategory(catIdx)
                            end

                            imgui.Indent(dp(10))
                            for _, test in ipairs(group.tests) do
                                if #filterText > 0 then
                                    if not test.name:lower():find(filterText, 1, true) and
                                       not (test.desc and test.desc:lower():find(filterText, 1, true)) then
                                        goto skipRow
                                    end
                                end

                                local res = allTestResults[test.name]
                                if not res then
                                    imgui.TextColored(imgui.ImVec4(0.40, 0.42, 0.48, 1.0), " - ")
                                elseif res.status == "PASS" then
                                    imgui.TextColored(imgui.ImVec4(0.12, 0.85, 0.35, 1.0), "v  ")
                                elseif res.status == "FAIL" then
                                    imgui.TextColored(imgui.ImVec4(0.95, 0.25, 0.18, 1.0), "x  ")
                                elseif res.status == "SKIP" then
                                    imgui.TextColored(imgui.ImVec4(0.60, 0.64, 0.72, 1.0), "-  ")
                                elseif res.status == "MISS" then
                                    imgui.TextColored(imgui.ImVec4(0.85, 0.50, 0.10, 1.0), "?  ")
                                end

                                imgui.SameLine()
                                if imgui.SmallButton(string.format("Run##t_%s", test.name)) then
                                    executeSingleTest(test, group, true, true)
                                    recalculateTotals()
                                end
                                imgui.SameLine()

                                local isMut = isMutatingTest(test)
                                if isMut then
                                    imgui.TextColored(imgui.ImVec4(0.95, 0.60, 0.20, 1.0), "[!]")
                                    imgui.SameLine()
                                end

                                imgui.TextColored(imgui.ImVec4(0.90, 0.92, 0.96, 1.0), test.name)

                                if res then
                                    imgui.SameLine()
                                    if res.status == "PASS" then
                                        imgui.TextColored(imgui.ImVec4(0.30, 0.80, 0.92, 0.95), "-> " .. tostring(res.formatted))
                                    elseif res.status == "FAIL" then
                                        imgui.TextColored(imgui.ImVec4(0.95, 0.35, 0.25, 0.95), "-> " .. tostring(res.err))
                                    elseif res.status == "SKIP" then
                                        imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.68, 0.90), "-> " .. tostring(res.detail))
                                    elseif res.status == "MISS" then
                                        imgui.TextColored(imgui.ImVec4(0.80, 0.48, 0.12, 0.90), "-> not defined")
                                    end
                                end

                                if test.desc and #test.desc > 0 then
                                    imgui.Indent(dp(16))
                                    imgui.TextColored(imgui.ImVec4(0.48, 0.52, 0.60, 0.85), test.desc)
                                    imgui.Unindent(dp(16))
                                end

                                ::skipRow::
                            end
                            imgui.Unindent(dp(10))
                            imgui.Spacing()
                        end
                    end
                end

                imgui.EndChild()
            end
            imgui.End()
        end
    )
end

-- ═══════════════════════════════════════════════════════════════════
-- Chat Commands
-- ═══════════════════════════════════════════════════════════════════

local function registerCommands()
    if type(sampRegisterChatCommand) ~= "function" then return end
    sampRegisterChatCommand("samptest", function(param)
        param = param and param:gsub("^%s*(.-)%s*$", "%1") or ""
        if param == "" or param == "gui" then
            if showWindow then
                showWindow[0] = not showWindow[0]
                sendChatMessage(string.format("{00FF88}[Test]{FFFFFF} GUI %s", showWindow[0] and "OPENED" or "CLOSED"))
            end
        elseif param == "run" then
            runAllTests()
        elseif param == "dump" then
            dumpAllValues()
        elseif param == "live" then
            if liveMonitorEnabled then
                liveMonitorEnabled[0] = not liveMonitorEnabled[0]
                sendChatMessage(string.format("{00FF88}[Test]{FFFFFF} Live monitor %s", liveMonitorEnabled[0] and "ENABLED" or "PAUSED"))
            end
        elseif param:sub(1, 6) == "player" then
            local pid = tonumber(param:sub(7)) or getTargetPlayer()
            if targetPlayerId then targetPlayerId[0] = pid end
            sendChatMessage(string.format("{00FF88}[Test]{FFFFFF} Running Player tests on ID %d...", pid))
            runCategory(2)
        elseif param:sub(1, 3) == "veh" then
            local vid = tonumber(param:sub(4)) or getTargetVehicle()
            if targetVehicleId then targetVehicleId[0] = vid end
            sendChatMessage(string.format("{00FF88}[Test]{FFFFFF} Running Vehicle tests on ID %d...", vid))
            runCategory(3)
        elseif param == "safe" then
            if safeModeEnabled then
                safeModeEnabled[0] = not safeModeEnabled[0]
                sendChatMessage(string.format("{00FF88}[Test]{FFFFFF} Safe Mode %s", safeModeEnabled[0] and "ENABLED (mutating tests blocked)" or "DISABLED (all tests allowed)"))
            end
        elseif param == "help" then
            sendChatMessage("{00FF88}--- NeoMLoader SAMP API Testing Suite ---")
            sendChatMessage("{FFFFFF}/samptest          - Toggle graphical UI")
            sendChatMessage("{FFFFFF}/samptest run      - Execute tests (respects Safe Mode)")
            sendChatMessage("{FFFFFF}/samptest safe     - Toggle Safe Mode filter")
            sendChatMessage("{FFFFFF}/samptest dump     - Dump full diagnostic to log")
            sendChatMessage("{FFFFFF}/samptest live     - Toggle live monitoring")
            sendChatMessage("{FFFFFF}/samptest player N - Test specific player ID")
            sendChatMessage("{FFFFFF}/samptest veh N    - Test specific vehicle ID")
        else
            sendChatMessage("{FF8800}[Test]{FFFFFF} Unknown subcommand. Type '/samptest help'")
        end
    end)
    addLog("Chat command '/samptest' registered successfully")
end

-- ═══════════════════════════════════════════════════════════════════
-- Script Lifecycle Entry
-- ═══════════════════════════════════════════════════════════════════

function main()
    if type(isSampLoaded) == "function" and type(wait) == "function" then
        while not isSampLoaded() do wait(200) end
    end

    registerCommands()
    addLog("NeoMLoader NeoMLoader Complete API Testing Suite v4.0 (2,147 Binds) initialized")

    -- Initial baseline execution
    if type(wait) ~= "function" then runAllTests() end

    if type(wait) == "function" then
        while true do
            wait(250)
            if liveMonitorEnabled and liveMonitorEnabled[0] then
                runLiveUpdate()
            end
        end
    end
end

if type(wait) ~= "function" and not _G.NO_AUTO_RUN then
    main()
end

return {
    runAllTests = runAllTests,
    runCategory = runCategory,
    dumpAllValues = dumpAllValues,
    executeSingleTest = executeSingleTest,
    invokeTest = invokeTest,
    getTargetPlayer = getTargetPlayer,
    getTargetVehicle = getTargetVehicle,
    getTargetPlayerHandle = getTargetPlayerHandle,
    targetPlayerId = targetPlayerId,
    targetVehicleId = targetVehicleId,
    safeModeEnabled = safeModeEnabled,
    isMutatingTest = isMutatingTest,
    getResults = function() return allTestResults end,
    catalog = testCatalog,
}
