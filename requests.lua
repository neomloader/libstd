local http_socket = require('socket.http')
local has_https, https_socket = pcall(require, 'ssl.https')
if not has_https then
  https_socket = nil
end
local url_parser = require('socket.url')
local ltn12 = require('ltn12')
local json = require('cjson.safe')
local has_xml, xml = pcall(require, 'xml')
if not has_xml then
  xml = nil
end
local md5sum = require('md5')
local base64 = require('base64')

local requests = {
  _DESCRIPTION = 'Http requests made simpler',
  http_socket = http_socket,
  https_socket = https_socket
}

local _requests = {}

function requests.HTTPDigestAuth(user, password)
  return { _type = 'digest', user = user, password = password}
end

function requests.HTTPBasicAuth(user, password)
  return { _type = 'basic', user = user, password = password}
end

function requests.post(url, args)
  return requests.request("POST", url, args)
end

function requests.get(url, args)
  return requests.request("GET", url, args)
end

function requests.delete(url, args)
  return requests.request("DELETE", url, args)
end

function requests.patch(url, args)
  return requests.request("PATCH", url, args)
end

function requests.put(url, args)
  return requests.request("PUT", url, args)
end

function requests.options(url, args)
  return requests.request("OPTIONS", url, args)
end

function requests.head(url, args)
  return requests.request("HEAD", url, args)
end

function requests.trace(url, args)
  return requests.request("TRACE", url, args)
end

function requests.request(method, url, args)
  local request

  if type(url) == "table" then
    request = url
  else
    request = args or {}
    request.url = url
  end

  request.method = method
  _requests.parse_args(request)

  if request.auth and request.auth._type == 'digest' then
    local response = _requests.make_request(request)
    return _requests.use_digest(response, request)
  else
    return _requests.make_request(request)
  end
end

function _requests.make_request(request)
  local max_redirects = request.max_redirects or 5
  local allow_redirects = (request.allow_redirects ~= false)
  local current_url = request.url
  local current_method = request.method or "GET"
  local current_data = request.data or ""
  local current_headers = {}
  if request.headers then
    for k, v in pairs(request.headers) do
      current_headers[k] = v
    end
  end

  local history = {}
  local redirect_count = 0

  while true do
    local response_body = {}
    local full_request = {
      method = current_method,
      url = current_url,
      headers = current_headers,
      source = (current_data ~= "" and ltn12.source.string(current_data)) or nil,
      sink = ltn12.sink.table(response_body),
      redirect = false,
      proxy = request.proxy
    }

    local want_https = string.find(current_url, '^https:') ~= nil
    local socket

    if not want_https or request.proxy then
      socket = requests.http_socket
    elseif want_https and not requests.https_socket then
      full_request.url = string.gsub(current_url, '^https:', 'http:', 1)
      socket = requests.http_socket
    else
      socket = requests.https_socket
    end

    if not socket then
      error('no HTTP transport available for '..current_url)
    end

    local ok, status_code, headers, status = socket.request(full_request)
    if not ok then
      local transport_error = status_code or status or 'unknown transport error'
      error('error in '..current_method..' request: '..tostring(transport_error))
    end

    local response = {
      status_code = status_code or 0,
      headers = headers or {},
      status = status or ""
    }

    local code = response.status_code
    local location = response.headers and (response.headers.location or response.headers.Location)

    if allow_redirects and location and (code == 301 or code == 302 or code == 303 or code == 307 or code == 308) and redirect_count < max_redirects then
      redirect_count = redirect_count + 1
      table.insert(history, {
        url = current_url,
        status_code = code,
        headers = response.headers
      })

      current_url = url_parser.absolute(current_url, location)

      if code == 303 or ((code == 301 or code == 302) and current_method ~= "HEAD") then
        current_method = "GET"
        current_data = ""
        current_headers["Content-Length"] = nil
        current_headers["content-length"] = nil
        current_headers["Content-Type"] = nil
        current_headers["content-type"] = nil
      end

      current_headers["Host"] = nil
      current_headers["host"] = nil

      local set_cookie = response.headers["set-cookie"] or response.headers["Set-Cookie"]
      if set_cookie then
        if current_headers["Cookie"] then
          current_headers["Cookie"] = current_headers["Cookie"] .. "; " .. set_cookie
        else
          current_headers["Cookie"] = set_cookie
        end
      end
    else
      response.text = table.concat(response_body)
      response.url = current_url
      response.history = history
      response.ok = (response.status_code >= 200 and response.status_code < 400)
      response.json = function()
        if not response.text or #response.text == 0 then return nil end
        return json.decode(response.text)
      end
      if xml ~= nil then
        response.xml = function() return xml.load(response.text) end
      end
      return response
    end
  end
end

function _requests.parse_args(request)
  _requests.check_url(request)
  _requests.check_data(request)
  _requests.create_header(request)
  _requests.check_timeout(request.timeout)
  _requests.check_redirect(request.allow_redirects)
end

function _requests.format_params(url, params)
  if not params or next(params) == nil then return url end

  url = url..'?'
  for key, value in pairs(params) do
    if tostring(value) then
      url = url..tostring(key)..'='

      if type(value) == 'table' then
        local val_string = ''

        for _, val in ipairs(value) do
          val_string = val_string..tostring(val)..','
        end

        url = url..val_string:sub(0, -2)
      else
        url = url..tostring(value)
      end

      url = url..'&'
    end
  end

  return url:sub(0, -2)
end

function _requests.check_url(request)
  assert(request.url, 'No url specified for request')
  request.url = _requests.format_params(request.url, request.params)
end

function _requests.create_header(request)
  request.headers = request.headers or {}

  local has_ua = false
  local has_accept = false
  for k, _ in pairs(request.headers) do
    local lk = string.lower(k)
    if lk == 'user-agent' then has_ua = true end
    if lk == 'accept' then has_accept = true end
  end

  if not has_ua then
    request.headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 NeoMLoader/1.0'
  end

  if not has_accept then
    request.headers['Accept'] = '*/*'
  end

  if request.data and #request.data > 0 then
    request.headers['Content-Length'] = #request.data
  end

  if request.cookies then
    if request.headers.cookie then
      request.headers.cookie = request.headers.cookie..'; '..request.cookies
    else
      request.headers.cookie = request.cookies
    end
  end

  if request.auth then
    _requests.add_auth_headers(request)
  end
end

function _requests.check_data(request)
  request.data = request.data or ''

  if type(request.data) == "table" then
    request.data = json.encode(request.data)
  end
end

function _requests.check_timeout(timeout)
  local t = timeout or 15
  requests.http_socket.TIMEOUT = t
  if requests.https_socket ~= nil then
    requests.https_socket.TIMEOUT = t
  end
end

function _requests.check_redirect(allow_redirects)
  if allow_redirects and type(allow_redirects) ~= "boolean" then
    error("allow_redirects expects a boolean value. received type = "..type(allow_redirects))
  end
end

function _requests.basic_auth_header(request)
  local encoded = base64.encode(request.auth.user..':'..request.auth.password)
  request.headers.Authorization = 'Basic '..encoded
end

function _requests.digest_create_header_string(auth)
  local authorization = ''
  authorization = 'Digest username="'..auth.user..'", realm="'..auth.realm..'", nonce="'..auth.nonce
  authorization = authorization..'", uri="'..auth.uri..'", qop='..auth.qop..', nc='..auth.nc
  authorization = authorization..', cnonce="'..auth.cnonce..'", response="'..auth.response..'"'

  if auth.opaque then
    authorization = authorization..', opaque="'..auth.opaque..'"'
  end

  return authorization
end

local function md5_hash(...)
  return md5sum.sumhexa(table.concat({...}, ":"))
end

function _requests.digest_hash_response(auth_table)
  return md5_hash(
    md5_hash(auth_table.user, auth_table.realm, auth_table.password),
    auth_table.nonce,
    auth_table.nc,
    auth_table.cnonce,
    auth_table.qop,
    md5_hash(auth_table.method, auth_table.uri)
  )
end

function _requests.digest_auth_header(request)
  if not request.auth.nonce then return end

  request.auth.cnonce = request.auth.cnonce or string.format("%08x", os.time())

  request.auth.nc_count = request.auth.nc_count or 0
  request.auth.nc_count = request.auth.nc_count + 1

  request.auth.nc = string.format("%08x", request.auth.nc_count)

  local url = url_parser.parse(request.url)
  request.auth.uri = url_parser.build{path = url.path, query = url.query}
  request.auth.method = request.method
  request.auth.qop = 'auth'

  request.auth.response = _requests.digest_hash_response(request.auth)

  request.headers.Authorization = _requests.digest_create_header_string(request.auth)
end

function _requests.use_digest(response, request)
  if response.status_code == 401 then
    _requests.parse_digest_response_header(response,request)
    _requests.create_header(request)
    response = _requests.make_request(request)
    response.auth = request.auth
    response.cookies = request.headers.cookie
    return response
  else
    response.auth = request.auth
    response.cookies = request.headers.cookie
    return response
  end
end

function _requests.parse_digest_response_header(response, request)
  for key, value in response.headers['www-authenticate']:gmatch('(%w+)="(%S+)"') do
    request.auth[key] = value
  end

  if request.headers.cookie then
    request.headers.cookie = request.headers.cookie..'; '..response.headers['set-cookie']
  else
    request.headers.cookie = response.headers['set-cookie']
  end

  request.auth.nc_count = 0
end

function _requests.add_auth_headers(request)
  local auth_func = {
    basic = _requests.basic_auth_header,
    digest = _requests.digest_auth_header
  }

  auth_func[request.auth._type](request)
end

requests._private = _requests
return requests
