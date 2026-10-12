local socket = require("socket")
local url = require("socket.url")
local ltn12 = require("ltn12")
local mime = require("mime")
local string = require("string")
local headers = require("socket.headers")
local base = _G
local table = require("table")
local copas = require("copas")
copas.http = {}
local _M = copas.http

_M.TIMEOUT = 60

_M.PORT = 80

_M.USERAGENT = socket._VERSION

_M.SSLPORT = 443
_M.SSLPROTOCOL = "any"
_M.SSLOPTIONS  = "all"
_M.SSLVERIFY   = "none"
_M.SSLSNISTRICT = false

local function receiveheaders(sock, headers)
    local line, name, value, err
    headers = headers or {}

    line, err = sock:receive()
    if err then return nil, err end

    while line ~= "" do

        name, value = socket.skip(2, string.find(line, "^(.-):%s*(.*)"))
        if not (name and value) then return nil, "malformed reponse headers" end
        name = string.lower(name)

        line, err  = sock:receive()
        if err then return nil, err end

        while string.find(line, "^%s") do
            value = value .. line
            line, err = sock:receive()
            if err then return nil, err end
        end

        if headers[name] then headers[name] = headers[name] .. ", " .. value
        else headers[name] = value end
    end
    return headers
end

socket.sourcet["http-chunked"] = function(sock, headers)
    return base.setmetatable({
        getfd = function() return sock:getfd() end,
        dirty = function() return sock:dirty() end
    }, {
        __call = function()

            local line, err = sock:receive()
            if err then return nil, err end
            local size = base.tonumber(string.gsub(line, ";.*", ""), 16)
            if not size then return nil, "invalid chunk size" end

            if size > 0 then

                local chunk, err = sock:receive(size)
                if chunk then sock:receive() end
                return chunk, err
            else

                headers, err = receiveheaders(sock, headers)
                if not headers then return nil, err end
            end
        end
    })
end

socket.sinkt["http-chunked"] = function(sock)
    return base.setmetatable({
        getfd = function() return sock:getfd() end,
        dirty = function() return sock:dirty() end
    }, {
        __call = function(self, chunk, err)
            if not chunk then return sock:send("0\r\n\r\n") end
            local size = string.format("%X\r\n", string.len(chunk))
            return sock:send(size ..  chunk .. "\r\n")
        end
    })
end

local metat = { __index = {} }

function _M.open(reqt)

    local c = socket.try(reqt:create())
    local h = base.setmetatable({ c = c }, metat)

    h.try = socket.newtry(function() h:close() end)

    local to = reqt.timeout or _M.TIMEOUT
    if type(to) == "table" then
      h.try(c:settimeouts(
        to.connect or _M.TIMEOUT,
        to.send or _M.TIMEOUT,
        to.receive or _M.TIMEOUT))
    else
      h.try(c:settimeout(to))
    end
    h.try(c:connect(reqt.host, reqt.port or _M.PORT))

    return h
end

function metat.__index:sendrequestline(method, uri)
    local reqline = string.format("%s %s HTTP/1.1\r\n", method or "GET", uri)
    return self.try(self.c:send(reqline))
end

function metat.__index:sendheaders(tosend)
    local canonic = headers.canonic
    local h = "\r\n"
    for f, v in base.pairs(tosend) do
        h = (canonic[f] or f) .. ": " .. v .. "\r\n" .. h
    end
    self.try(self.c:send(h))
    return 1
end

function metat.__index:sendbody(headers, source, step)
    source = source or ltn12.source.empty()
    step = step or ltn12.pump.step

    local mode = "http-chunked"
    if headers["content-length"] then mode = "keep-open" end
    return self.try(ltn12.pump.all(source, socket.sink(mode, self.c), step))
end

function metat.__index:receivestatusline()
    local status = self.try(self.c:receive(5))

    if status ~= "HTTP/" then return nil, status end

    status = self.try(self.c:receive("*l", status))
    local code = socket.skip(2, string.find(status, "HTTP/%d*%.%d* (%d%d%d)"))
    return self.try(base.tonumber(code), status)
end

function metat.__index:receiveheaders()
    return self.try(receiveheaders(self.c))
end

function metat.__index:receivebody(headers, sink, step)
    sink = sink or ltn12.sink.null()
    step = step or ltn12.pump.step
    local length = base.tonumber(headers["content-length"])
    local t = headers["transfer-encoding"]
    local mode = "default"
    if t and t ~= "identity" then mode = "http-chunked"
    elseif base.tonumber(headers["content-length"]) then mode = "by-length" end
    return self.try(ltn12.pump.all(socket.source(mode, self.c, length),
        sink, step))
end

function metat.__index:receive09body(status, sink, step)
    local source = ltn12.source.rewind(socket.source("until-closed", self.c))
    source(status)
    return self.try(ltn12.pump.all(source, sink, step))
end

function metat.__index:close()
    return self.c:close()
end

local function adjusturi(reqt)
    local u = reqt

    if not reqt.proxy and not _M.PROXY then
        u = {
           path = socket.try(reqt.path, "invalid path 'nil'"),
           params = reqt.params,
           query = reqt.query,
           fragment = reqt.fragment
        }
    end
    return url.build(u)
end

local function adjustproxy(reqt)
    local proxy = reqt.proxy or _M.PROXY
    if proxy then
        proxy = url.parse(proxy)
        return proxy.host, proxy.port or 3128
    else
        return reqt.host, reqt.port
    end
end

local function adjustheaders(reqt)

    local host = string.gsub(reqt.authority, "^.-@", "")
    local lower = {
        ["user-agent"] = _M.USERAGENT,
        ["host"] = host,
        ["connection"] = "close, TE",
        ["te"] = "trailers"
    }

    if reqt.user and reqt.password then
        lower["authorization"] =
            "Basic " ..  (mime.b64(reqt.user .. ":" .. reqt.password))
    end

    for i,v in base.pairs(reqt.headers or lower) do
        lower[string.lower(i)] = v
    end
    return lower
end

local default = {
    host = "",
    port = _M.PORT,
    path ="/",
    scheme = "http"
}

local function adjustrequest(reqt)

    local nreqt = reqt.url and url.parse(reqt.url, default) or {}

    for i,v in base.pairs(reqt) do nreqt[i] = v end
    if nreqt.port == "" then nreqt.port = 80 end
    socket.try(nreqt.host and nreqt.host ~= "",
        "invalid host '" .. base.tostring(nreqt.host) .. "'")

    nreqt.uri = reqt.uri or adjusturi(nreqt)

    nreqt.host, nreqt.port = adjustproxy(nreqt)

    nreqt.headers = adjustheaders(nreqt)
    return nreqt
end

local function shouldredirect(reqt, code, headers)
    return headers.location and
           string.gsub(headers.location, "%s", "") ~= "" and
           (reqt.redirect ~= false) and
           (code == 301 or code == 302 or code == 303 or code == 307) and
           (not reqt.method or reqt.method == "GET" or reqt.method == "HEAD")
           and (not reqt.nredirects or reqt.nredirects < 5)
end

local function shouldreceivebody(reqt, code)
    if reqt.method == "HEAD" then return nil end
    if code == 204 or code == 304 then return nil end
    if code >= 100 and code < 200 then return nil end
    return 1
end

local trequest, tredirect

 function tredirect(reqt, location)
    local result, code, headers, status = trequest {

        url = url.absolute(reqt.url, location),
        source = reqt.source,
        sink = reqt.sink,
        headers = reqt.headers,
        proxy = reqt.proxy,
        nredirects = (reqt.nredirects or 0) + 1,
        create = reqt.create,
        timeout = reqt.timeout,
    }

    headers = headers or {}
    headers.location = headers.location or location
    return result, code, headers, status
end

 function trequest(reqt)

    local nreqt = adjustrequest(reqt)
    local h = _M.open(nreqt)

    h:sendrequestline(nreqt.method, nreqt.uri)
    h:sendheaders(nreqt.headers)

    if nreqt.source then
        h:sendbody(nreqt.headers, nreqt.source, nreqt.step)
    end
    local code, status = h:receivestatusline()

    if not code then
        h:receive09body(status, nreqt.sink, nreqt.step)
        return 1, 200
    end
    local headers

    while code == 100 do
        h:receiveheaders()
        code, status = h:receivestatusline()
    end
    headers = h:receiveheaders()

    if shouldredirect(nreqt, code, headers) and not nreqt.source then
        h:close()
        return tredirect(reqt, headers.location)
    end

    if shouldreceivebody(nreqt, code) then
        h:receivebody(headers, nreqt.sink, nreqt.step)
    end
    h:close()
    return 1, code, headers, status
end

function _M.getcreatefunc(params)
   params = params or {}
   local ssl_params = params.sslparams or {}
   ssl_params.wrap = ssl_params.wrap or {

      protocol = params.protocol,
      options = params.options,
      verify = params.verify,
   }
   ssl_params.sni = ssl_params.sni or {
      strict = _M.SSLSNISTRICT
   }

   ssl_params.wrap.protocol = ssl_params.wrap.protocol or _M.SSLPROTOCOL
   ssl_params.wrap.options = ssl_params.wrap.options or _M.SSLOPTIONS
   if ssl_params.wrap.verify == nil then
      ssl_params.wrap.verify = _M.SSLVERIFY
   end
   ssl_params.wrap.mode = "client"

   if not ssl_params.sni.names then

      local old_params = ssl_params
      ssl_params = {}
      for k,v in pairs(old_params) do
        ssl_params[k] = v
      end
      ssl_params.sni = { strict = old_params.sni.strict }
   end

   local washttps = false

   return function (reqt)
      local u = url.parse(reqt.url)
      if (reqt.scheme or u.scheme) == "https" then

        ssl_params.sni.names = ssl_params.sni.names or u.host

        local conn = copas.wrap(socket.tcp(), ssl_params)

        if not u.port then
           u.port = _M.SSLPORT
           reqt.url = url.build(u)
           reqt.port = _M.SSLPORT
        end
        washttps = true
        return conn
      else

        if washttps and params.redirect ~= "all" then
          socket.try(nil, "Unallowed insecure redirect https to http")
        end
        return copas.wrap(socket.tcp())
      end
   end
end

_M.parseRequest = function(u, b)
    local reqt = {
        url = u,
        target = {},
    }
    reqt.sink = ltn12.sink.table(reqt.target)
    if b then
        reqt.source = ltn12.source.string(b)
        reqt.headers = {
            ["content-length"] = string.len(b),
            ["content-type"] = "application/x-www-form-urlencoded"
        }
        reqt.method = "POST"
    end
    return reqt
end

_M.request = socket.protect(function(reqt, body)
    if base.type(reqt) == "string" then
        reqt = _M.parseRequest(reqt, body)
        local ok, code, headers, status = _M.request(reqt)

        if ok then
            return table.concat(reqt.target), code, headers, status
        else
            return nil, code
        end
    else

        if type(reqt.timeout) == "table" then
          local allowed = { connect = true, send = true, receive = true }
          for k in pairs(reqt.timeout) do
            assert(allowed[k], "'"..tostring(k).."' is not a valid timeout option. Valid: 'connect', 'send', 'receive'")
          end
        end
        reqt.create = reqt.create or _M.getcreatefunc(reqt)
        return trequest(reqt)
    end
end)

return _M
