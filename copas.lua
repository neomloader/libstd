if package.loaded["socket.http"] and (_VERSION=="Lua 5.1") then
  error("you must require copas before require'ing socket.http")
end
if package.loaded["copas.http"] and (_VERSION=="Lua 5.1") then
  error("you must require copas before require'ing copas.http")
end

local socket = require "socket"
local binaryheap = require "binaryheap"
local gettime = socket.gettime
local ssl

local WATCH_DOG_TIMEOUT = 120
local UDP_DATAGRAM_MAX = socket._DATAGRAMSIZE or 8192
local TIMEOUT_PRECISION = 0.1
local fnil = function() end

local coroutine_create = coroutine.create
local coroutine_running = coroutine.running
local coroutine_yield = coroutine.yield
local coroutine_resume = coroutine.resume
local coroutine_status = coroutine.status

local _unpack = unpack or table.unpack
local unpack = function(t, i, j) return _unpack(t, i or 1, j or t.n or #t) end
local pack = function(...) return { n = select("#", ...), ...} end

local pcall = pcall
if _VERSION=="Lua 5.1" and not jit then
  pcall = require("coxpcall").pcall
  coroutine_running = require("coxpcall").running
end

do

  local err_mt = {
    __tostring = function (self)
      return "Copas 'try' error intermediate table: '"..tostring(self[1].."'")
    end,
  }

  local function statusHandler(status, ...)
    if status then return ... end
    local err = (...)
    if type(err) == "table" and getmetatable(err) == err_mt then
      return nil, err[1]
    else
      error(err)
    end
  end

  function socket.protect(func)
    return function (...)
            return statusHandler(pcall(func, ...))
          end
  end

  function socket.newtry(finalizer)
    return function (...)
            local status = (...)
            if not status then
              pcall(finalizer or fnil, select(2, ...))
              error(setmetatable({ (select(2, ...)) }, err_mt), 0)
            end
            return ...
          end
  end

  socket.try = socket.newtry()
end

local copas do
  local submodules = { "ftp", "http", "lock", "queue", "semaphore", "smtp", "timer" }
  for i, key in ipairs(submodules) do
    submodules[key] = true
    submodules[i] = nil
  end

  copas = setmetatable({},{
    __index = function(self, key)
      if submodules[key] then
        self[key] = require("copas."..key)
        submodules[key] = nil
        return rawget(self, key)
      end
    end,
    __call = function(self, ...)
      return self.loop(...)
    end,
  })
end

copas._COPYRIGHT   = "Copyright (C) 2005-2013 Kepler Project, 2015-2023 Thijs Schreijer"
copas._DESCRIPTION = "Coroutine Oriented Portable Asynchronous Services"
copas._VERSION     = "Copas 4.7.0"

copas.autoclose = true

copas.running = false

local object_names = setmetatable({}, {
  __mode = "k",
  __index = function(self, key)
    local name = tostring(key)
    if key ~= nil then
      rawset(self, key, name)
    end
    return name
  end
})

local function newsocketset()
  local set = {}

  do
    local reverse = {}

    function set:insert(skt)
      if not reverse[skt] then
        self[#self + 1] = skt
        reverse[skt] = #self
        return skt
      end
    end

    function set:remove(skt)
      local index = reverse[skt]
      if index then
        reverse[skt] = nil
        local top = self[#self]
        self[#self] = nil
        if top ~= skt then
          reverse[top] = index
          self[index] = top
        end
        return skt
      end
    end

  end

  do
    local fifo_queues = setmetatable({},{
      __mode = "k",
      __index = function(self, skt)
        local newfifo = {}
        self[skt] = newfifo
        return newfifo
      end,
    })

    function set:push(skt, itm)
      local queue = fifo_queues[skt]
      queue[#queue + 1] = itm
    end

    function set:pop(skt)
      local queue = fifo_queues[skt]
      return table.remove(queue, 1)
    end

  end

  return set
end

local _resumable = {} do
  local resumelist = {}

  function _resumable:push(co)
    resumelist[#resumelist + 1] = co
  end

  function _resumable:clear_resumelist()
    local lst = resumelist
    resumelist = {}
    return lst
  end

  function _resumable:done()
    return resumelist[1] == nil
  end

  function _resumable:count()
    return #resumelist + #_resumable
  end

end

local _sleeping = {} do

  local heap = binaryheap.minUnique()
  local lethargy = setmetatable({}, { __mode = "k" })

  _sleeping.insert = fnil
  _sleeping.remove = fnil

  function _sleeping:push(sleeptime, co)
    if sleeptime < 0 then
      lethargy[co] = true
    elseif sleeptime == 0 then
      _resumable:push(co)
    else
      heap:insert(gettime() + sleeptime, co)
    end
  end

  function _sleeping:pop(time)
    if time < (heap:peekValue() or math.huge) then
      return
    end
    return heap:pop()
  end

  function _sleeping:getnext()
    local t = heap:peekValue()
    if t then

      return math.max(t - gettime(), 0)
    end
  end

  function _sleeping:wakeup(co)
    if lethargy[co] then
      lethargy[co] = nil
      _resumable:push(co)
      return
    end
    if heap:remove(co) then
      _resumable:push(co)
    end
  end

  function _sleeping:cancel(co)
    lethargy[co] = nil
    heap:remove(co)
  end

  function _sleeping:done(tos)

    return heap:size() == 1
           and not (tos > 0 and next(lethargy))
  end

  function _sleeping:status()
    local c = 0
    for _ in pairs(lethargy) do c = c + 1 end

    return heap:size(), c
  end

end

local _servers = newsocketset()
local _threads = setmetatable({}, {__mode = "k"})
local _canceled = setmetatable({}, {__mode = "k"})
local _autoclose = setmetatable({}, {__mode = "kv"})
local _autoclose_r = setmetatable({}, {__mode = "kv"})

local _reading_log = {}
local _writing_log = {}

local _closed = {}

local _reading = newsocketset()
local _writing = newsocketset()
local _isSocketTimeout = {
  ["timeout"] = true,
  ["wantread"] = true,
  ["wantwrite"] = true,
}

local user_timeouts_connect
local user_timeouts_send
local user_timeouts_receive
do
  local timeout_mt = {
    __mode = "k",
    __index = function(self, skt)

      self[skt] = math.huge
      return self[skt]
    end,
  }

  user_timeouts_connect = setmetatable({}, timeout_mt)
  user_timeouts_send = setmetatable({}, timeout_mt)
  user_timeouts_receive = setmetatable({}, timeout_mt)
end

local useSocketTimeoutErrors = setmetatable({},{ __mode = "k" })

local sto_timeout, sto_timed_out, sto_change_queue, sto_error do

  local socket_register = setmetatable({}, { __mode = "k" })
  local operation_register = setmetatable({}, { __mode = "k" })
  local timeout_flags = setmetatable({}, { __mode = "k" })

  local function socket_callback(co)
    local skt = socket_register[co]
    local queue = operation_register[co]

    timeout_flags[co] = true
    _resumable:push(co)

    if queue == "read" then
      _reading:remove(skt)
    elseif queue == "write" then
      _writing:remove(skt)
    else
      error("bad queue name; expected 'read'/'write', got: "..tostring(queue))
    end
  end

  function sto_timeout(skt, queue, use_connect_to)
    local co = coroutine_running()
    socket_register[co] = skt
    operation_register[co] = queue
    timeout_flags[co] = nil
    if skt then
      local to = (use_connect_to and user_timeouts_connect[skt]) or
                 (queue == "read" and user_timeouts_receive[skt]) or
                 user_timeouts_send[skt]
      copas.timeout(to, socket_callback)
    else
      copas.timeout(0)
    end
    return true
  end

  function sto_change_queue(queue)
    operation_register[coroutine_running()] = queue
    return true
  end

  function sto_timed_out()
    return timeout_flags[coroutine_running()]
  end

  function sto_error(err)
    return useSocketTimeoutErrors[coroutine_running()] and err or "timeout"
  end
end

local isTCP do
  local lookup = {
    tcp = "tcp",
    SSL = "ssl",
  }

  function isTCP(socket)
    return lookup[tostring(socket):sub(1,3)]
  end
end

function copas.close(skt, ...)
  _closed[#_closed+1] = skt
  return skt:close(...)
end

function copas.settimeout(skt, timeout)
  timeout = timeout or -1
  if type(timeout) ~= "number" then
    return nil, "timeout must be 'nil' or a number"
  end

  return copas.settimeouts(skt, timeout, timeout, timeout)
end

function copas.settimeouts(skt, connect, send, read)

  if connect ~= nil and type(connect) ~= "number" then
    return nil, "connect timeout must be 'nil' or a number"
  end
  if connect then
    if connect < 0 then
      connect = nil
    end
    user_timeouts_connect[skt] = connect
  end

  if send ~= nil and type(send) ~= "number" then
    return nil, "send timeout must be 'nil' or a number"
  end
  if send then
    if send < 0 then
      send = nil
    end
    user_timeouts_send[skt] = send
  end

  if read ~= nil and type(read) ~= "number" then
    return nil, "read timeout must be 'nil' or a number"
  end
  if read then
    if read < 0 then
      read = nil
    end
    user_timeouts_receive[skt] = read
  end

  return true
end

function copas.receive(client, pattern, part)
  local s, err
  pattern = pattern or "*l"
  local current_log = _reading_log
  sto_timeout(client, "read")

  repeat
    s, err, part = client:receive(pattern, part)

    if (math.random(100) > 90) then
      copas.pause()
    end

    if s then
      current_log[client] = nil
      sto_timeout()
      return s, err, part

    elseif not _isSocketTimeout[err] then
      current_log[client] = nil
      sto_timeout()
      return s, err, part

    elseif sto_timed_out() then
      current_log[client] = nil
      return nil, sto_error(err), part
    end

    if err == "wantwrite" then
      current_log = _writing_log
      current_log[client] = gettime()
      sto_change_queue("write")
      coroutine_yield(client, _writing)
    else
      current_log = _reading_log
      current_log[client] = gettime()
      sto_change_queue("read")
      coroutine_yield(client, _reading)
    end
  until false
end

function copas.receivefrom(client, size)
  local s, err, port
  size = size or UDP_DATAGRAM_MAX
  sto_timeout(client, "read")

  repeat
    s, err, port = client:receivefrom(size)

    if (math.random(100) > 90) then
      copas.pause()
    end

    if s then
      _reading_log[client] = nil
      sto_timeout()
      return s, err, port

    elseif err ~= "timeout" then
      _reading_log[client] = nil
      sto_timeout()
      return s, err, port

    elseif sto_timed_out() then
      _reading_log[client] = nil
      return nil, sto_error(err), port
    end

    _reading_log[client] = gettime()
    coroutine_yield(client, _reading)
  until false
end

function copas.receivepartial(client, pattern, part)
  local s, err
  pattern = pattern or "*l"
  local orig_size = #(part or "")
  local current_log = _reading_log
  sto_timeout(client, "read")

  repeat
    s, err, part = client:receive(pattern, part)

    if (math.random(100) > 90) then
      copas.pause()
    end

    if s or (type(part) == "string" and #part > orig_size) then
      current_log[client] = nil
      sto_timeout()
      return s, err, part

    elseif not _isSocketTimeout[err] then
      current_log[client] = nil
      sto_timeout()
      return s, err, part

    elseif sto_timed_out() then
      current_log[client] = nil
      return nil, sto_error(err), part
    end

    if err == "wantwrite" then
      current_log = _writing_log
      current_log[client] = gettime()
      sto_change_queue("write")
      coroutine_yield(client, _writing)
    else
      current_log = _reading_log
      current_log[client] = gettime()
      sto_change_queue("read")
      coroutine_yield(client, _reading)
    end
  until false
end
copas.receivePartial = copas.receivepartial

function copas.send(client, data, from, to)
  local s, err
  from = from or 1
  local lastIndex = from - 1
  local current_log = _writing_log
  sto_timeout(client, "write")

  repeat
    s, err, lastIndex = client:send(data, lastIndex + 1, to)

    if (math.random(100) > 90) then
      copas.pause()
    end

    if s then
      current_log[client] = nil
      sto_timeout()
      return s, err, lastIndex

    elseif not _isSocketTimeout[err] then
      current_log[client] = nil
      sto_timeout()
      return s, err, lastIndex

    elseif sto_timed_out() then
      current_log[client] = nil
      return nil, sto_error(err), lastIndex
    end

    if err == "wantread" then
      current_log = _reading_log
      current_log[client] = gettime()
      sto_change_queue("read")
      coroutine_yield(client, _reading)
    else
      current_log = _writing_log
      current_log[client] = gettime()
      sto_change_queue("write")
      coroutine_yield(client, _writing)
    end
  until false
end

function copas.sendto(client, data, ip, port)

  return client:sendto(data, ip, port)
end

function copas.connect(skt, host, port)
  skt:settimeout(0)
  local ret, err, tried_more_than_once
  sto_timeout(skt, "write", true)

  repeat
    ret, err = skt:connect(host, port)

    if ret or (err ~= "timeout" and err ~= "Operation already in progress") then
      _writing_log[skt] = nil
      sto_timeout()

      if (not ret) and (err == "already connected" and tried_more_than_once) then
        return 1
      end
      return ret, err

    elseif sto_timed_out() then
      _writing_log[skt] = nil
      return nil, sto_error(err)
    end

    tried_more_than_once = tried_more_than_once or true
    _writing_log[skt] = gettime()
    coroutine_yield(skt, _writing)
  until false
end

local function ssl_wrap(skt, wrap_params)
  if isTCP(skt) == "ssl" then return skt end
  if not wrap_params then
    error("cannot wrap socket into a secure socket (using 'ssl.wrap()') without parameters/context")
  end

  ssl = ssl or require("ssl")
  local nskt = assert(ssl.wrap(skt, wrap_params))

  nskt:settimeout(0)
  copas.settimeouts(nskt, user_timeouts_connect[skt],
    user_timeouts_send[skt], user_timeouts_receive[skt])

  local co = _autoclose_r[skt]
  if co then

    _autoclose[co] = nskt
    _autoclose_r[skt] = nil
    _autoclose_r[nskt] = co
  end

  local sock_name = object_names[skt]
  if sock_name ~= tostring(skt) then

    object_names[nskt] = sock_name
  end
  return nskt
end

local function normalize_sslt(sslt)
  local t = type(sslt)
  local r = setmetatable({}, {
    __index = function(self, key)

      error("accessing unknown 'ssl_params' table key: "..tostring(key))
    end,
  })
  if t == "nil" then
    r.wrap = false
    r.sni = false

  elseif t == "table" then
    if sslt.mode or sslt.protocol then

      r.wrap = sslt
      r.sni = false
    else

      r.wrap = sslt.wrap or false
      r.sni = sslt.sni or false
    end

  elseif t == "userdata" then

    r.wrap = sslt
    r.sni = false

  else
    error("ssl parameters; did not expect type "..tostring(sslt))
  end

  return r
end

function copas.dohandshake(skt, wrap_params)
  ssl = ssl or require("ssl")

  local nskt = ssl_wrap(skt, wrap_params)

  sto_timeout(nskt, "write", true)
  local queue

  repeat
    local success, err = nskt:dohandshake()

    if success then
      sto_timeout()
      return nskt

    elseif not _isSocketTimeout[err] then
      sto_timeout()
      error("TLS/SSL handshake failed: " .. tostring(err))

    elseif sto_timed_out() then
      return nil, sto_error(err)

    elseif err == "wantwrite" then
      sto_change_queue("write")
      queue = _writing

    elseif err == "wantread" then
      sto_change_queue("read")
      queue = _reading

    else
      error("TLS/SSL handshake failed: " .. tostring(err))
    end

    coroutine_yield(nskt, queue)
  until false
end

function copas.flush()
end

local _skt_mt_tcp = {
      __tostring = function(self)
        return tostring(self.socket).." (copas wrapped)"
      end,

      __index = {
        send = function (self, data, from, to)
          return copas.send (self.socket, data, from, to)
        end,

        receive = function (self, pattern, prefix)
          if user_timeouts_receive[self.socket] == 0 then
            return copas.receivepartial(self.socket, pattern, prefix)
          end
          return copas.receive(self.socket, pattern, prefix)
        end,

        receivepartial = function (self, pattern, prefix)
          return copas.receivepartial(self.socket, pattern, prefix)
        end,

        flush = function (self)
          return copas.flush(self.socket)
        end,

        settimeout = function (self, time)
          return copas.settimeout(self.socket, time)
        end,

        settimeouts = function (self, connect, send, receive)
          return copas.settimeouts(self.socket, connect, send, receive)
        end,

        connect = function(self, ...)
          local res, err = copas.connect(self.socket, ...)
          if res then
            if self.ssl_params.sni then self:sni() end
            if self.ssl_params.wrap then res, err = self:dohandshake() end
          end
          return res, err
        end,

        close = function(self, ...)
          return copas.close(self.socket, ...)
        end,

        bind = function(self, ...) return self.socket:bind(...) end,

        getsockname = function(self, ...)
          local ok, ip, port, family = pcall(self.socket.getsockname, self.socket, ...)
          if ok then
            return ip, port, family
          else
            return nil, "not implemented by LuaSec"
          end
        end,

        getstats = function(self, ...) return self.socket:getstats(...) end,

        setstats = function(self, ...) return self.socket:setstats(...) end,

        listen = function(self, ...) return self.socket:listen(...) end,

        accept = function(self, ...) return self.socket:accept(...) end,

        setoption = function(self, ...)
          local ok, res, err = pcall(self.socket.setoption, self.socket, ...)
          if ok then
            return res, err
          else
            return nil, "not implemented by LuaSec"
          end
        end,

        getoption = function(self, ...)
          local ok, val, err = pcall(self.socket.getoption, self.socket, ...)
          if ok then
            return val, err
          else
            return nil, "not implemented by LuaSec"
          end
        end,

        getpeername = function(self, ...)
          local ok, ip, port, family = pcall(self.socket.getpeername, self.socket, ...)
          if ok then
            return ip, port, family
          else
            return nil, "not implemented by LuaSec"
          end
        end,

        shutdown = function(self, ...) return self.socket:shutdown(...) end,

        sni = function(self, names, strict)
          local sslp = self.ssl_params
          self.socket = ssl_wrap(self.socket, sslp.wrap)
          if names == nil then
            names = sslp.sni.names
            strict = sslp.sni.strict
          end
          return self.socket:sni(names, strict)
        end,

        dohandshake = function(self, wrap_params)
          local nskt, err = copas.dohandshake(self.socket, wrap_params or self.ssl_params.wrap)
          if not nskt then return nskt, err end
          self.socket = nskt
          return self
        end,

        getalpn = function(self, ...)
          local ok, proto, err = pcall(self.socket.getalpn, self.socket, ...)
          if ok then
            return proto, err
          else
            return nil, "not a tls socket"
          end
        end,

        getsniname = function(self, ...)
          local ok, name, err = pcall(self.socket.getsniname, self.socket, ...)
          if ok then
            return name, err
          else
            return nil, "not a tls socket"
          end
        end,
      }
}

local _skt_mt_udp = {__index = { }}
for k,v in pairs(_skt_mt_tcp) do _skt_mt_udp[k] = _skt_mt_udp[k] or v end
for k,v in pairs(_skt_mt_tcp.__index) do _skt_mt_udp.__index[k] = v end

_skt_mt_udp.__index.send        = function(self, ...) return self.socket:send(...) end

_skt_mt_udp.__index.sendto      = function(self, ...) return self.socket:sendto(...) end

_skt_mt_udp.__index.receive =     function (self, size)
                                    return copas.receive (self.socket, (size or UDP_DATAGRAM_MAX))
                                  end

_skt_mt_udp.__index.receivefrom = function (self, size)
                                    return copas.receivefrom (self.socket, (size or UDP_DATAGRAM_MAX))
                                  end

_skt_mt_udp.__index.setpeername = function(self, ...) return self.socket:setpeername(...) end

_skt_mt_udp.__index.setsockname = function(self, ...) return self.socket:setsockname(...) end

_skt_mt_udp.__index.close       = function(self, ...) return true end

_skt_mt_udp.__index.settimeouts = function (self, connect, send, receive)
                                    return copas.settimeouts(self.socket, connect, send, receive)
                                  end

function copas.wrap (skt, sslt)
  if (getmetatable(skt) == _skt_mt_tcp) or (getmetatable(skt) == _skt_mt_udp) then
    return skt
  end

  skt:settimeout(0)

  if isTCP(skt) then
    return setmetatable ({socket = skt, ssl_params = normalize_sslt(sslt)}, _skt_mt_tcp)
  else
    return setmetatable ({socket = skt}, _skt_mt_udp)
  end
end

function copas.handler(handler, sslparams)

  return function (skt, ...)
    skt = copas.wrap(skt, sslparams)
    local sslp = skt.ssl_params
    if sslp.sni then skt:sni(sslp.sni.names, sslp.sni.strict) end
    if sslp.wrap then skt:dohandshake(sslp.wrap) end
    return handler(skt, ...)
  end
end

local _errhandlers = setmetatable({}, { __mode = "k" })

function copas.gettraceback(msg, co, skt)
  local co_str = co == nil and "nil" or copas.getthreadname(co)
  local skt_str = skt == nil and "nil" or copas.getsocketname(skt)
  local msg_str = msg == nil and "" or tostring(msg)
  if msg_str == "" then
    msg_str = ("(coroutine: %s, socket: %s)"):format(msg_str, co_str, skt_str)
  else
    msg_str = ("%s (coroutine: %s, socket: %s)"):format(msg_str, co_str, skt_str)
  end

  if type(co) == "thread" then

    return debug.traceback(co, msg_str)
  end

  return debug.traceback(msg_str, 2)
end

local function _deferror(msg, co, skt)
  print(copas.gettraceback(msg, co, skt))
end

function copas.seterrorhandler(err, default)
  assert(err == nil or type(err) == "function", "Expected the handler to be a function, or nil")
  if default then
    assert(err ~= nil, "Expected the handler to be a function when setting the default")
    _deferror = err
  else
    _errhandlers[coroutine_running()] = err
  end
end
copas.setErrorHandler = copas.seterrorhandler

function copas.geterrorhandler(co)
  co = co or coroutine_running()
  return _errhandlers[co] or _deferror
end

function copas.useSocketTimeoutErrors(bool)
  useSocketTimeoutErrors[coroutine_running()] = not not bool
end

local function _doTick (co, skt, ...)
  if not co then return end

  if _canceled[co] or coroutine_status(co) == "dead" then
    _canceled[co] = nil
    _threads[co] = nil
    return
  end

  local ok, res, new_q = coroutine_resume(co, skt, ...)

  if new_q == _reading or new_q == _writing or new_q == _sleeping then

    new_q:insert (res)
    new_q:push (res, co)
    return
  end

  if ok and coroutine_status(co) ~= "dead" then

    ok = false
    res = "coroutine.yield was called without a resume first, user-code cannot yield to Copas"
  end

  if not ok then
    local k, e = pcall(_errhandlers[co] or _deferror, res, co, skt)
    if not k then
      print("Failed executing error handler: " .. tostring(e))
    end
  end

  local skt_to_close = _autoclose[co]
  if skt_to_close then
    skt_to_close:close()
    _autoclose[co] = nil
    _autoclose_r[skt_to_close] = nil
  end

  _errhandlers[co] = nil
end

local _accept do
  local client_counters = setmetatable({}, { __mode = "k" })

  function _accept(server_skt, handler)
    local client_skt = server_skt:accept()
    if client_skt then
      local count = (client_counters[server_skt] or 0) + 1
      client_counters[server_skt] = count
      object_names[client_skt] = object_names[server_skt] .. ":client_" .. count

      client_skt:settimeout(0)
      copas.settimeouts(client_skt, user_timeouts_connect[server_skt],
        user_timeouts_send[server_skt], user_timeouts_receive[server_skt])

      local co = coroutine_create(handler)
      object_names[co] = object_names[server_skt] .. ":handler_" .. count

      if copas.autoclose then
        _autoclose[co] = client_skt
        _autoclose_r[client_skt] = co
      end

      _doTick(co, client_skt)
    end
  end
end

do
  local function addTCPserver(server, handler, timeout, name)
    server:settimeout(0)
    if name then
      object_names[server] = name
    end
    _servers[server] = handler
    _reading:insert(server)
    if timeout then
      copas.settimeout(server, timeout)
    end
  end

  local function addUDPserver(server, handler, timeout, name)
    server:settimeout(0)
    local co = coroutine_create(handler)
    if name then
      object_names[server] = name
    end
    object_names[co] = object_names[server]..":handler"
    _reading:insert(server)
    if timeout then
      copas.settimeout(server, timeout)
    end
    _doTick(co, server)
  end

  function copas.addserver(server, handler, timeout, name)
    if isTCP(server) then
      addTCPserver(server, handler, timeout, name)
    else
      addUDPserver(server, handler, timeout, name)
    end
  end
end

function copas.removeserver(server, keep_open)
  local skt = server
  local mt = getmetatable(server)
  if mt == _skt_mt_tcp or mt == _skt_mt_udp then
    skt = server.socket
  end

  _servers:remove(skt)
  _reading:remove(skt)

  if keep_open then
    return true
  end
  return server:close()
end

function copas.addnamedthread(name, handler, ...)
  if type(name) == "function" and type(handler) == "string" then

    name, handler = handler, name
  end

  local thread = coroutine_create(function(_, ...)
    copas.pause()
    return handler(...)
  end)
  if name then
    object_names[thread] = name
  end

  _threads[thread] = true
  _doTick (thread, nil, ...)
  return thread
end

function copas.addthread(handler, ...)
  return copas.addnamedthread(nil, handler, ...)
end

function copas.removethread(thread)

  _canceled[thread] = _threads[thread or 0]
  _sleeping:cancel(thread)
end

function copas.sleep(sleeptime)
  coroutine_yield((sleeptime or 0), _sleeping)
end

function copas.pause(sleeptime)
  if sleeptime and sleeptime > 0 then
    coroutine_yield(sleeptime, _sleeping)
  else
    coroutine_yield(0, _sleeping)
  end
end

function copas.pauseforever()
  coroutine_yield(-1, _sleeping)
end

function copas.wakeup(co)
  _sleeping:wakeup(co)
end

do
  local timeout_register = setmetatable({}, { __mode = "k" })
  local time_out_thread
  local timerwheel = require("timerwheel").new({
      precision = TIMEOUT_PRECISION,
      ringsize = math.floor(60*60*24/TIMEOUT_PRECISION),
      err_handler = function(err)
        return _deferror(err, time_out_thread)
      end,
    })

  time_out_thread = copas.addnamedthread("copas_core_timer", function()
    while true do
      copas.pause(TIMEOUT_PRECISION)
      timerwheel:step()
    end
  end)

  function copas.gettimeouts()
    return timerwheel:count()
  end

  function copas.timeout(delay, callback)
    local co = coroutine_running()
    local existing_timer = timeout_register[co]

    if existing_timer then
      timerwheel:cancel(existing_timer)
    end

    if delay > 0 and delay ~= math.huge then
      timeout_register[co] = timerwheel:set(delay, callback, co)
    elseif delay == 0 or delay == math.huge then
      timeout_register[co] = nil
    else
      error("timout value must be greater than or equal to 0, got: "..tostring(delay))
    end

    return true
  end

end

local _tasks = {} do
  function _tasks:add(tsk)
    _tasks[#_tasks + 1] = tsk
  end
end

local _readable_task = {} do

  local function tick(skt)
    local handler = _servers[skt]
    if handler then
      _accept(skt, handler)
    else
      _reading:remove(skt)
      _doTick(_reading:pop(skt), skt)
    end
  end

  function _readable_task:step(budget_ms)
    local events = self._events
    if not events or #events == 0 then return end
    local max_ms = budget_ms or 1.5
    local t0 = os.clock()
    local i = 1
    local n = #events
    while i <= n do
      local skt = events[i]
      events[i] = nil
      tick(skt)
      i = i + 1
      if i <= n and (os.clock() - t0) * 1000.0 >= max_ms then
        local remaining = {}
        for j = i, n do
          remaining[#remaining + 1] = events[j]
        end
        self._events = remaining
        return
      end
    end
    self._events = {}
  end

  _tasks:add(_readable_task)
end

local _writable_task = {} do

  local function tick(skt)
    _writing:remove(skt)
    _doTick(_writing:pop(skt), skt)
  end

  function _writable_task:step(budget_ms)
    local events = self._events
    if not events or #events == 0 then return end
    local max_ms = budget_ms or 1.0
    local t0 = os.clock()
    local i = 1
    local n = #events
    while i <= n do
      local skt = events[i]
      events[i] = nil
      tick(skt)
      i = i + 1
      if i <= n and (os.clock() - t0) * 1000.0 >= max_ms then
        local remaining = {}
        for j = i, n do
          remaining[#remaining + 1] = events[j]
        end
        self._events = remaining
        return
      end
    end
    self._events = {}
  end

  _tasks:add(_writable_task)
end

local _sleeping_task = {} do

  function _sleeping_task:step()
    local now = gettime()

    local co = _sleeping:pop(now)
    while co do

      _resumable:push(co)
      co = _sleeping:pop(now)
    end
  end

  _tasks:add(_sleeping_task)
end

local _resumable_task = {} do

  function _resumable_task:step()

    local resumelist = _resumable:clear_resumelist()

    for _, co in ipairs(resumelist) do
      _doTick(co)
    end
  end

  _tasks:add(_resumable_task)
end

local _select_plain do

  local last_cleansing = 0
  local duration = function(t2, t1) return t2-t1 end

  _select_plain = function(timeout)
    local err
    local now = gettime()

    if _closed[1] then
      for i, skt in ipairs(_closed) do
        _closed[i] = { _reading:remove(skt), _writing:remove(skt) }
      end
    end

    local ok, r, w, select_err = pcall(socket.select, _reading, _writing, timeout)
    if not ok then
      _readable_task._events, _writable_task._events, err = {}, {}, select_err
    else
      _readable_task._events, _writable_task._events, err = r or {}, w or {}, select_err
    end
    local r_events, w_events = _readable_task._events, _writable_task._events

    if _closed[1] then
      for i, skts in ipairs(_closed) do
        _closed[i] = nil
        r_events[#r_events+1] = skts[1]
        w_events[#w_events+1] = skts[2]
      end
    end

    if duration(now, last_cleansing) > WATCH_DOG_TIMEOUT then
      last_cleansing = now

      for skt,time in pairs(_reading_log) do
        if not r_events[skt] and duration(now, time) > WATCH_DOG_TIMEOUT then

          _reading_log[skt] = nil
          r_events[#r_events + 1] = skt
          r_events[skt] = #r_events
        end
      end

      for skt,time in pairs(_writing_log) do
        if not w_events[skt] and duration(now, time) > WATCH_DOG_TIMEOUT then
          _writing_log[skt] = nil
          w_events[#w_events + 1] = skt
          w_events[skt] = #w_events
        end
      end
    end

    if err == "timeout" and #r_events + #w_events > 0 then
      return nil
    else
      return err
    end
  end
end

local copas_stats
local min_ever, max_ever

local _select = _select_plain

local _select_instrumented = function(timeout)
  if copas_stats then
    local step_duration = gettime() - copas_stats.step_start
    copas_stats.duration_max = math.max(copas_stats.duration_max, step_duration)
    copas_stats.duration_min = math.min(copas_stats.duration_min, step_duration)
    copas_stats.duration_tot = copas_stats.duration_tot + step_duration
    copas_stats.steps = copas_stats.steps + 1
  else
    copas_stats = {
      duration_max = -1,
      duration_min = 999999,
      duration_tot = 0,
      steps = 0,
    }
  end

  local err = _select_plain(timeout)

  local now = gettime()
  copas_stats.time_start = copas_stats.time_start or now
  copas_stats.step_start = now

  return err
end

function copas.step(timeout)
  local has_deferred = (_readable_task._events and #_readable_task._events > 0) or
                       (_writable_task._events and #_writable_task._events > 0)
  local err
  if not has_deferred then

    if not _resumable:done() then
      timeout = 0
    else
      timeout = math.min(_sleeping:getnext(), timeout or math.huge)
    end

    err = _select(timeout)
  end

  for _, tsk in ipairs(_tasks) do
    tsk:step(1.5)
  end

  if err then
    if err == "timeout" then
      if timeout + 0.01 > TIMEOUT_PRECISION and math.random(100) > 90 then

        collectgarbage()
      end
      return false
    end
    return nil, err
  end

  return true
end

function copas.finished()
  return #_reading == 0 and #_writing == 0 and _resumable:done() and _sleeping:done(copas.gettimeouts())
end

local _getstats do
  local _getstats_instrumented, _getstats_plain

  function _getstats_plain(enable)

    if enable == true then
      _select = _select_instrumented
      _getstats = _getstats_instrumented

      min_ever = nil
      max_ever = nil
      copas_stats = nil
    end
    return {}
  end

  local function useconds(t)
    return math.floor((t * 1000000) + 0.5) / 1000
  end

  local function mseconds(t)
    return math.floor((t * 1000) + 0.5) / 1000
  end

  function _getstats_instrumented(enable)
    if enable == false then
      _select = _select_plain
      _getstats = _getstats_plain

      return _getstats(enable)
    end
    if (not copas_stats) or (copas_stats.step == 0) then
      return {}
    end
    local stats = copas_stats
    copas_stats = nil
    min_ever = math.min(min_ever or 9999999, stats.duration_min)
    max_ever = math.max(max_ever or 0, stats.duration_max)
    stats.duration_min_ever = min_ever
    stats.duration_max_ever = max_ever
    stats.duration_avg = stats.duration_tot / stats.steps
    stats.step_start = nil
    stats.time_end = gettime()
    stats.time_tot = stats.time_end - stats.time_start
    stats.time_avg = stats.time_tot / stats.steps

    stats.duration_avg = useconds(stats.duration_avg)
    stats.duration_max = useconds(stats.duration_max)
    stats.duration_max_ever = useconds(stats.duration_max_ever)
    stats.duration_min = useconds(stats.duration_min)
    stats.duration_min_ever = useconds(stats.duration_min_ever)
    stats.duration_tot = useconds(stats.duration_tot)
    stats.time_avg = useconds(stats.time_avg)
    stats.time_start = mseconds(stats.time_start)
    stats.time_end = mseconds(stats.time_end)
    stats.time_tot = mseconds(stats.time_tot)
    return stats
  end

  _getstats = _getstats_plain
end

function copas.status(enable_stats)
  local res = _getstats(enable_stats)
  res.running = not not copas.running
  res.timeout = copas.gettimeouts()
  res.timer, res.inactive = _sleeping:status()
  res.read = #_reading
  res.write = #_writing
  res.active = _resumable:count()
  return res
end

function copas.loop(initializer, timeout)
  if type(initializer) == "function" then
    copas.addnamedthread("copas_initializer", initializer)
  else
    timeout = initializer or timeout
  end

  copas.running = true
  while not copas.finished() do copas.step(timeout) end
  copas.running = false
end

do
  local function realsocket(skt)
    local mt = getmetatable(skt)
    if mt == _skt_mt_tcp or mt == _skt_mt_udp then
      return skt.socket
    else
      return skt
    end
  end

  function copas.setsocketname(name, skt)
    assert(type(name) == "string", "expected arg #1 to be a string")
    skt = assert(realsocket(skt), "expected arg #2 to be a socket")
    object_names[skt] = name
  end

  function copas.getsocketname(skt)
    skt = assert(realsocket(skt), "expected arg #1 to be a socket")
    return object_names[skt]
  end
end

function copas.setthreadname(name, coro)
  assert(type(name) == "string", "expected arg #1 to be a string")
  coro = coro or coroutine_running()
  assert(type(coro) == "thread", "expected arg #2 to be a coroutine or nil")
  object_names[coro] = name
end

function copas.getthreadname(coro)
  coro = coro or coroutine_running()
  assert(type(coro) == "thread", "expected arg #1 to be a coroutine or nil")
  return object_names[coro]
end

do
  copas.debug = {}

  local log_core
  local debug_log

  local debug_yield = function(skt, queue)
    local name = object_names[coroutine_running()]

    if log_core or name ~= "copas_core_timer" then
      if queue == _sleeping then
        debug_log("yielding '", name, "' to SLEEP for ", skt," seconds")

      elseif queue == _writing then
        debug_log("yielding '", name, "' to WRITE on '", object_names[skt], "'")

      elseif queue == _reading then
        debug_log("yielding '", name, "' to READ on '", object_names[skt], "'")

      else
        debug_log("thread '", name, "' yielding to unexpected queue; ", tostring(queue), " (", type(queue), ")", debug.traceback())
      end
    end

    return coroutine.yield(skt, queue)
  end

  local debug_resume = function(coro, skt, ...)
    local name = object_names[coro]

    if skt then
      debug_log("resuming '", name, "' for socket '", object_names[skt], "'")
    else
      if log_core or name ~= "copas_core_timer" then
        debug_log("resuming '", name, "'")
      end
    end
    return coroutine.resume(coro, skt, ...)
  end

  local debug_create = function(f)
    local f_wrapped = function(...)
      local results = pack(f(...))
      debug_log("exiting '", object_names[coroutine_running()], "'")
      return unpack(results)
    end

    return coroutine.create(f_wrapped)
  end

  debug_log = fnil

  function copas.debug.start(logger, core)
    log_core = core
    debug_log = logger or print
    coroutine_yield = debug_yield
    coroutine_resume = debug_resume
    coroutine_create = debug_create
  end

  function copas.debug.stop()
    debug_log = fnil
    coroutine_yield = coroutine.yield
    coroutine_resume = coroutine.resume
    coroutine_create = coroutine.create
  end

  do
    local call_id = 0

    local args = {
      settimeout_in = {
        "socket ",
        "seconds",
        "mode   ",
      },
      settimeout_out = {
        "success",
        "error  ",
      },
      connect_in = {
        "socket ",
        "address",
        "port   ",
      },
      connect_out = {
        "success",
        "error  ",
      },
      getfd_in = {
        "socket ",

      },
      getfd_out = {
        "fd",
      },
      send_in = {
        "socket   ",
        "data     ",
        "idx-start",
        "idx-end  ",
      },
      send_out = {
        "last-idx-send    ",
        "error            ",
        "err-last-idx-send",
      },
      receive_in = {
        "socket ",
        "pattern",
        "prefix ",
      },
      receive_out = {
        "received    ",
        "error       ",
        "partial data",
      },
      dirty_in = {
        "socket",

      },
      dirty_out = {
        "data in read-buffer",
      },
      close_in = {
        "socket",

      },
      close_out = {
        "success",
        "error",
      },
    }
    local function print_call(func, msg, ...)
      print(msg)
      local arg = pack(...)
      local desc = args[func] or {}
      for i = 1, math.max(arg.n, #desc) do
        local value = arg[i]
        if type(value) == "string" then
          local xvalue = value:sub(1,30)
          if xvalue ~= value then
            xvalue = xvalue .."(...truncated)"
          end
          print("\t"..(desc[i] or i)..": '"..tostring(xvalue).."' ("..type(value).." #"..#value..")")
        else
          print("\t"..(desc[i] or i)..": '"..tostring(value).."' ("..type(value)..")")
        end
      end
      if desc.callback then
        desc.callback(...)
      end
    end

    local debug_mt = {
      __index = function(self, key)
        local value = self.__original_socket[key]
        if type(value) ~= "function" then
          return value
        end
        return function(self2, ...)
            local my_id = call_id + 1
            call_id = my_id
            local results

            if self2 ~= self then

              print_call(tostring(key).."_in", my_id .. "-calling '"..tostring(key) .. "' with; ", self, ...)
              results = pack(value(self, ...))
            else
              print_call(tostring(key).."_in", my_id .. "-calling '" .. tostring(key) .. "' with; ", self.__original_socket, ...)
              results = pack(value(self.__original_socket, ...))
            end
            print_call(tostring(key).."_out", my_id .. "-results '"..tostring(key) .. "' returned; ", unpack(results))
            return unpack(results)
          end
      end,
      __tostring = function(self)
        return tostring(self.__original_socket)
      end
    }

    function copas.debug.socket(original_skt)
      if (getmetatable(original_skt) == _skt_mt_tcp) or (getmetatable(original_skt) == _skt_mt_udp) then

        original_skt.socket = copas.debug.socket(original_skt.socket)
        return original_skt
      end

      local proxy = setmetatable({
        __original_socket = original_skt
      }, debug_mt)

      return proxy
    end
  end
end

return copas
