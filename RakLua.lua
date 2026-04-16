local RakLuaSO = require "RakLuaSO"

addEventHandler("onScriptTerminate", function(scr) 
    if scr == script.this then 
        RakLuaSO.destroyHandlers() 
    end 
end)

local events = {
    ["onSendRpc"]       = RakLuaEvents.OUTGOING_RPC,
    ["onSendPacket"]    = RakLuaEvents.OUTGOING_PACKET,
    ["onReceiveRpc"]    = RakLuaEvents.INCOMING_RPC,
    ["onReceivePacket"] = RakLuaEvents.INCOMING_PACKET
}

local addEventHandler_orig = addEventHandler

local function hookAddEventHandler(event, func)
    if events[event] then
        assert(type(func) == "function", "Expected function, got " .. type(func))
        print(type(func))
        RakLuaSO.registerHandler(events[event], func)
    else
        addEventHandler_orig(event, func)
    end
end

local function defineSampLuaCompatibility() -- To be removed
    addEventHandler = hookAddEventHandler
    isSampfuncsLoaded = function() return true end
end

RakLuaSO.defineSampLuaCompatibility = defineSampLuaCompatibility

return RakLuaSO