local ffi = require("ffi")
local cjson = require("cjson")
local env = require("android.jnienv")
local envu = require("android.jnienv-util")
local jni = require("android.jni-raw")
local socket = require("socket")
local UDP = assert(socket.udp())

local activity = jni.activity
if not activity or (ffi.istype("void*", activity) and activity == nil) then
    error("Android Activity handle is not available for WebViews")
end

local code, class, cldr = envu.InjectJar(getWorkingDirectory() .. "/lib/webviews/WebViews.jar", "WebViews/Main", "init", "(Landroid/app/Activity;)V", activity)
if not code then error(class or "Failed to inject WebViews JAR") end
if not class or not cldr then error("WebViews JAR injection returned incomplete handles") end
envu.LooperPrepare()
local webviews = {
    cldr = ffi.cast('jclass', env.NewGlobalRef(cldr))
}
env.DeleteLocalRef(cldr)

function toboolean(num) return num > 0 end

local async = {}
function webviews.setClickableAsync(id, bool) if bool then table.insert(async, id) else for i, value in ipairs(async) do if value == id then table.remove(async, i) end end end end
function webviews.createBrowserFromFile(id, file)
    local jstr = env.NewStringUTF(file)
    envu.CallStaticVoidMethod(class, "createBrowserFromFile", "(ILjava/lang/String;)V", ffi.cast("jint", id), jstr)
    env.DeleteLocalRef(jstr)
end
function webviews.createBrowser(id, url)
    local jstr = env.NewStringUTF(url)
    envu.CallStaticVoidMethod(class, "createBrowser", "(ILjava/lang/String;)V", ffi.cast("jint", id), jstr)
    env.DeleteLocalRef(jstr)
end
function webviews.executeJS(id, msg)
    local jstr = env.NewStringUTF(msg)
    envu.CallStaticVoidMethod(class, "executeJS", "(ILjava/lang/String;)V", ffi.cast("jint", id), jstr)
    env.DeleteLocalRef(jstr)
end
function webviews.changeUrl(id, url)
    local jstr = env.NewStringUTF(url)
    envu.CallStaticVoidMethod(class, "changeUrl", "(ILjava/lang/String;)V", ffi.cast("jint", id), jstr)
    env.DeleteLocalRef(jstr)
end
function webviews.setClickable(id, bool)
    local args = ffi.new("jvalue[2]")
    args[0].i = id
    args[1].z = bool and 1 or 0
    envu.CallStaticVoidMethodA(class, "setClickable", "(IZ)V", args)
end
function webviews.setVisible(id, bool)
    local args = ffi.new("jvalue[2]")
    args[0].i = id
    args[1].z = bool and 1 or 0
    envu.CallStaticVoidMethodA(class, "setVisible", "(IZ)V", args)
end
function webviews.setPos(id, x, y)
    local args = ffi.new("jvalue[4]")
    args[0].i = id
    args[1].z = 1
    args[2].i = x
    args[3].i = y
    envu.CallStaticVoidMethodA(class, "resizeBrowser", "(IZII)V", args)
end
function webviews.setSize(id, x, y)
    local args = ffi.new("jvalue[4]")
    args[0].i = id
    args[1].z = 0
    args[2].i = x
    args[3].i = y
    envu.CallStaticVoidMethodA(class, "resizeBrowser", "(IZII)V", args)
end
function webviews.deleteBrowser(id) envu.CallStaticVoidMethod(class, "deleteBrowser", "(I)V", ffi.cast("jint", id)) end
function webviews.showCloseButton(id, bool) envu.CallStaticVoidMethod(class, "showCloseButton", "(IZ)V", ffi.cast("jint", id), bool) end
function webviews.setSetting(id, name, bool)
    local jstr = env.NewStringUTF(name)
    envu.CallStaticVoidMethod(class, "setSetting", "(ILjava/lang/String;Z)V", ffi.cast("jint", id), jstr, bool)
    env.DeleteLocalRef(jstr)
end
function webviews.addLog(log)
    local jstr = env.NewStringUTF(log)
    envu.CallStaticVoidMethod(class, "addLog", "(Ljava/lang/String;)V", jstr)
    env.DeleteLocalRef(jstr)
end
function webviews.sendClick(id, type, clickid, x, y) envu.CallStaticVoidMethod(class, "sendClick", "(IIIII)V", ffi.cast("jint", id), ffi.cast("jint", type), ffi.cast("jint", clickid), ffi.cast("jint", x), ffi.cast("jint", y)) end
function webviews.resetPort() return envu.CallStaticIntMethod(class, "resetUDPPort", "()I") end
function webviews.getPort() return envu.CallStaticIntMethod(class, "getUDPPort", "()I") end
function webviews.canGoForward(id) return toboolean(envu.CallStaticBooleanMethod(class, "goPage", "(IZZ)Z", ffi.cast("jint", id), true, true)) end
function webviews.canGoBack(id) return toboolean(envu.CallStaticBooleanMethod(class, "goPage", "(IZZ)Z", ffi.cast("jint", id), false, true)) end
function webviews.goForward(id) return toboolean(envu.CallStaticBooleanMethod(class, "goPage", "(IZZ)Z", ffi.cast("jint", id), true, false)) end
function webviews.goBack(id) return toboolean(envu.CallStaticBooleanMethod(class, "goPage", "(IZZ)Z", ffi.cast("jint", id), false, false)) end
function webviews.getJSValue(id, msg)
    local jstr = env.NewStringUTF(msg)
    local jobj = envu.CallStaticObjectMethod(class, "getJSValue", "(ILjava/lang/String;)Ljava/lang/String;", ffi.cast("jint", id), jstr)
    env.DeleteLocalRef(jstr)
    if jobj ~= nil then
        local res = envu.FromJString(jobj)
        env.DeleteLocalRef(jobj)
        return res
    end
    return nil
end
function webviews.getStatus(id) return toboolean(envu.CallStaticBooleanMethod(class, "getStatus", "(I)Z", ffi.cast("jint", id))) end
function webviews.getVersion()
    local jobj = envu.CallStaticObjectMethod(class, "getVersion", "()Ljava/lang/String;")
    if jobj ~= nil then
        local str = envu.FromJString(jobj)
        env.DeleteLocalRef(jobj)
        return cjson.decode(str)
    end
    return nil
end
function webviews.getBrowsers()
    local jobj = envu.CallStaticObjectMethod(class, "getBrowsers", "()Ljava/lang/String;")
    if jobj ~= nil then
        local str = envu.FromJString(jobj)
        env.DeleteLocalRef(jobj)
        return cjson.decode(str)
    end
    return nil
end
function webviews.getBrowser(id) return envu.CallStaticObjectMethod(class, "getBrowser", "(I)LWebViews/TransparentWebView;", ffi.cast("jint", id)) end
function webviews.getScreen(id)
    local jobj = envu.CallStaticObjectMethod(class, "getScreen", "(I)Ljava/lang/String;", ffi.cast("jint", id))
    if jobj ~= nil then
        local str = envu.FromJString(jobj)
        env.DeleteLocalRef(jobj)
        return str
    end
    return nil
end
function webviews.onAction(action) return action end
local udpCallback

function webviews.restartCallback()
    if udpCallback ~= nil then udpCallback:terminate() end
	udpCallback = lua_thread.create(function()
	    webviews.resetPort()
		UDP:settimeout(0)
		wait(500)
		UDP:setpeername("127.0.0.1", webviews.getPort())
		wait(500)
		UDP:send('CONNECT')
		while true do
		    wait(0)
		    local data = UDP:receive()
		    if data ~= nil then
		      local success, data = pcall(cjson.decode, data)
		      if success then webviews.onAction(data) end
		    end
		end
	end)
end

function onTouch(type, id, x, y)
	for i, value in ipairs(async) do
	    print("value still alive", value)
	    webviews.sendClick(value, type, id, x, y)
	end
end

udpCallback = lua_thread.create(function()
	UDP:settimeout(0)
	wait(500)
	UDP:setpeername("127.0.0.1", webviews.getPort())
	wait(500)
	UDP:send('CONNECT')
	while true do
	    wait(0)
	    local data = UDP:receive()
	    if data ~= nil then
	      local success, data = pcall(cjson.decode, data)
		  if success then webviews.onAction(data)
		  else print("failed to decode: ", data) end
	    end
	end
end)

return webviews
