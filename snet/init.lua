local snet = {}
local socket = require("socket")

snet._VERSION = "SNET v.1.0.1"
snet._COPYRIGHT = "Copyright © 2020 Pavel Akulichev"
snet._DESCRIPTION = "Simple Network Module v.1.0.1"

-- SNET Statuses Definition
SNET_DISCONNECTED = 0
SNET_CONNECTED = 1

-- SNET Priorities
SNET_SYSTEM_PRIORITY = 4
SNET_HIGH_PRIORITY = 3
SNET_MEDIUM_PRIORITY = 2
SNET_LOW_PRIORITY = 1
SNET_BYPASS_PRIORITY = 0

-- SNET Service Packet IDs
SNET_CONFIRM_PRIORITY = 0xFFFFFFFF
SNET_BLOCK_PACKET = 0xFFFFFFFF - 1

snet.bstream = require("snet.bstream")
local server_class = require("snet.server")
local client_class = require("snet.client")

function snet.server(address, port)
  local new_object = {
    address = address,
    port = port,
    unique_id = 0,
    last_ids = {},
    events = {},
    clients = {},
    packets = {},
    blacklist = {}
  }
  setmetatable(new_object, {
    __index = server_class,
    __tostring = function()
      return "SNET Server"
    end
  })

  local sock = socket.udp()
  if sock then
    sock:settimeout(0)
    pcall(function() sock:setsockname(address, port) end)
  end
  new_object.socket = sock

  return new_object
end

function snet.client(address, port)
  local new_object = {
    address = address,
    port = port,
    status = SNET_DISCONNECTED,
    connected = false,
    unique_id = 0,
    last_ids = {},
    events = {},
    packets = {}
  }
  setmetatable(new_object, {
    __index = client_class,
    __tostring = function()
      return "SNET Client"
    end
  })

  local sock, err = socket.udp()
  if not sock then
    new_object.connect_error = err or "failed to create udp socket"
    return new_object
  end

  new_object.socket = sock
  sock:settimeout(0)
  local ok, res, serr = pcall(function()
    return sock:setpeername(address, port)
  end)

  if ok and (res == 1 or res == true) then
    new_object.connected = true
  else
    new_object.connected = false
    new_object.connect_error = (not ok and tostring(res)) or serr or "setpeername failed"
  end

  return new_object
end

return snet
