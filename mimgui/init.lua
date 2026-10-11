local ffi = require("ffi")
local bit = bit or require("bit")
require("mimgui.cimgui")
local enums = require("mimgui.enums")

local script_name = "default"
if thisScript ~= nil then
    local ok, s = pcall(thisScript)
    if ok and type(s) == "userdata" and s.filename then
        script_name = s.filename
    elseif ok and type(s) == "table" and s.filename then
        script_name = s.filename
    elseif type(thisScript) == "table" and thisScript.filename then
        script_name = thisScript.filename
    elseif type(thisScript) == "userdata" and thisScript.filename then
        script_name = thisScript.filename
    end
end

local ok_native = false
local ok_call, ctx = pcall(function()
    return ffi.C.neom_mimgui_create_context(script_name)
end)
if ok_call and ctx ~= nil then
    ok_native = true
else

    if ffi.C.igGetCurrentContext() == nil then
        ffi.C.igCreateContext(nil)
    end
end

local mimgui = {
    _VERSION = "2.0.1"
}

local cdata_lengths = setmetatable({}, { __mode = "k" })

local default_cdata_mt = debug.getmetatable(ffi.new("char[1]"))
if default_cdata_mt then
    local orig_len = default_cdata_mt.__len
    local orig_tostring = default_cdata_mt.__tostring

    default_cdata_mt.__len = function(x)
        local custom_len = cdata_lengths[x]
        if custom_len ~= nil then return custom_len end
        local ok, sz = pcall(ffi.sizeof, x)
        if ok then return sz end
        if orig_len then return orig_len(x) end
        return 0
    end

    default_cdata_mt.__tostring = function(x)
        local custom_len = cdata_lengths[x]
        if custom_len ~= nil then
            local ok, s = pcall(ffi.string, x, custom_len)
            if ok then
                local null_pos = s:find("\0", 1, true)
                if null_pos then return s:sub(1, null_pos - 1) end
                return s
            end
        end
        if ffi.istype("char*", x) or ffi.istype("const char*", x) then
            local ok, s = pcall(ffi.string, x)
            if ok then return s end
        end
        if orig_tostring then return orig_tostring(x) end
        return string.format("cdata: %p", x)
    end
end

local ImVec2
ImVec2 = ffi.metatype("ImVec2", {
    __index = function(self, k)
        if k == 0 then return self.x
        elseif k == 1 then return self.y
        end
        return nil
    end,
    __newindex = function(self, k, v)
        if k == 0 then self.x = v
        elseif k == 1 then self.y = v
        end
    end,
    __call = function(self, x, y)
        if x ~= nil then
            self.x = x
            if y ~= nil then self.y = y end
        else
            return self.x, self.y
        end
    end,
    __add = function(a, b)
        if type(a) == "number" then return ImVec2(a + b.x, a + b.y) end
        if type(b) == "number" then return ImVec2(a.x + b, a.y + b) end
        return ImVec2(a.x + b.x, a.y + b.y)
    end,
    __sub = function(a, b)
        if type(a) == "number" then return ImVec2(a - b.x, a - b.y) end
        if type(b) == "number" then return ImVec2(a.x - b, a.y - b) end
        return ImVec2(a.x - b.x, a.y - b.y)
    end,
    __unm = function(a) return ImVec2(-a.x, -a.y) end,
    __mul = function(a, b)
        if type(b) == "number" then return ImVec2(a.x * b, a.y * b) end
        if type(a) == "number" then return ImVec2(a * b.x, a * b.y) end
        return ImVec2(a.x * b.x, a.y * b.y)
    end,
    __div = function(a, b)
        if type(b) == "number" then return ImVec2(a.x / b, a.y / b) end
        if type(a) == "number" then return ImVec2(a / b.x, a / b.y) end
        return ImVec2(a.x / b.x, a.y / b.y)
    end,
    __tostring = function(v) return string.format("ImVec2(%.2f, %.2f)", v.x, v.y) end,
})

local imvec2_ct = ffi.typeof("ImVec2")

local function ImVec2_ctor(x, y, ...)
    if type(x) == "number" and type(y) == "number" then
        return ImVec2(x, y)
    end
    if x == nil then
        return ImVec2(0, 0)
    end
    if ffi.istype(imvec2_ct, x) and y == nil then
        return ImVec2(x.x, x.y)
    end
    if type(x) == "table" then
        local src = x.Value or x
        local rx = tonumber(src.x or src[1]) or 0
        local ry = tonumber(src.y or src[2]) or 0
        return ImVec2(rx, ry)
    end
    if type(x) == "boolean" then

        local extra = ...
        return ImVec2(tonumber(y) or 0, tonumber(extra) or 0)
    end
    local nx = (type(x) == "number") and x or (tonumber(x) or 0)
    local ny = (type(y) == "number") and y or (tonumber(y) or 0)
    return ImVec2(nx, ny)
end

mimgui.ImVec2 = setmetatable({}, {
    __call = function(_, ...) return ImVec2_ctor(...) end,
    __index = ImVec2
})

local ImVec4
ImVec4 = ffi.metatype("ImVec4", {
    __index = function(self, k)
        if k == 0 or k == "r" then return self.x
        elseif k == 1 or k == "g" then return self.y
        elseif k == 2 or k == "b" then return self.z
        elseif k == 3 or k == "a" then return self.w
        end
        return nil
    end,
    __newindex = function(self, k, v)
        if k == 0 or k == "r" then self.x = v
        elseif k == 1 or k == "g" then self.y = v
        elseif k == 2 or k == "b" then self.z = v
        elseif k == 3 or k == "a" then self.w = v
        end
    end,
    __call = function(self, x, y, z, w)
        if x ~= nil then
            self.x = x
            if y ~= nil then self.y = y end
            if z ~= nil then self.z = z end
            if w ~= nil then self.w = w end
        else
            return self.x, self.y, self.z, self.w
        end
    end,
    __add = function(a, b)
        if type(a) == "number" then return ImVec4(a + b.x, a + b.y, a + b.z, a + b.w) end
        if type(b) == "number" then return ImVec4(a.x + b, a.y + b, a.z + b, a.w + b) end
        return ImVec4(a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w)
    end,
    __sub = function(a, b)
        if type(a) == "number" then return ImVec4(a - b.x, a - b.y, a - b.z, a - b.w) end
        if type(b) == "number" then return ImVec4(a.x - b, a.y - b, a.z - b, a.w - b) end
        return ImVec4(a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w)
    end,
    __unm = function(a) return ImVec4(-a.x, -a.y, -a.z, -a.w) end,
    __mul = function(a, b)
        if type(b) == "number" then return ImVec4(a.x * b, a.y * b, a.z * b, a.w * b) end
        if type(a) == "number" then return ImVec4(a * b.x, a * b.y, a * b.z, a * b.w) end
        return ImVec4(a.x * b.x, a.y * b.y, a.z * b.z, a.w * b.w)
    end,
    __div = function(a, b)
        if type(b) == "number" then return ImVec4(a.x / b, a.y / b, a.z / b, a.w / b) end
        if type(a) == "number" then return ImVec4(a / b.x, a / b.y, a / b.z, a / b.w) end
        return ImVec4(a.x / b.x, a.y / b.y, a.z / b.z, a.w / b.w)
    end,
    __tostring = function(v) return string.format("ImVec4(%.2f, %.2f, %.2f, %.2f)", v.x, v.y, v.z, v.w) end,
})

local imvec4_ct = ffi.typeof("ImVec4")

local function ImVec4_ctor(x, y, z, w)
    if type(x) == "number" and type(y) == "number" and type(z) == "number" and type(w) == "number" then
        return ImVec4(x, y, z, w)
    end
    if x == nil and y == nil and z == nil and w == nil then
        return ImVec4(0, 0, 0, 0)
    end
    if ffi.istype(imvec4_ct, x) and y == nil and z == nil and w == nil then
        return ImVec4(x.x, x.y, x.z, x.w)
    end
    if ffi.istype("ImColor", x) and y == nil and z == nil and w == nil then
        return ImVec4(x.Value.x, x.Value.y, x.Value.z, x.Value.w)
    end
    if type(x) == "table" then
        local src = x.Value or x
        local rx = tonumber(src.x or src[1] or src.r) or 0
        local ry = tonumber(src.y or src[2] or src.g) or 0
        local rz = tonumber(src.z or src[3] or src.b) or 0
        local rw = tonumber(src.w or src[4] or src.a) or 1
        return ImVec4(rx, ry, rz, rw)
    end
    if type(x) == "number" and y == nil and z == nil and w == nil then
        if x > 1.0 then
            local a = bit.band(bit.rshift(x, 24), 0xFF) / 255.0
            local r = bit.band(bit.rshift(x, 16), 0xFF) / 255.0
            local g = bit.band(bit.rshift(x, 8), 0xFF) / 255.0
            local b = bit.band(x, 0xFF) / 255.0
            if a == 0 and x <= 0xFFFFFF then a = 1.0 end
            return ImVec4(r, g, b, a)
        else
            return ImVec4(x, 0, 0, 1.0)
        end
    end
    local nx = (type(x) == "number") and x or 0
    local ny = (type(y) == "number") and y or 0
    local nz = (type(z) == "number") and z or 0
    local nw = (type(w) == "number") and w or 1.0
    return ImVec4(nx, ny, nz, nw)
end

mimgui.ImVec4 = setmetatable({}, {
    __call = function(_, ...) return ImVec4_ctor(...) end
})

local ImColor
local ImColor_mt = {
    __tostring = function(self)
        return string.format("ImColor(%.2f, %.2f, %.2f, %.2f)", self.Value.x, self.Value.y, self.Value.z, self.Value.w)
    end,
    __index = {
        GetVec4 = function(self) return self.Value end,
        GetU32 = function(self) return ffi.C.igColorConvertFloat4ToU32(self.Value) end,
        SetHSV = function(self, h, s, v, a)
            local r = ffi.new("float[1]")
            local g = ffi.new("float[1]")
            local b = ffi.new("float[1]")
            ffi.C.igColorConvertHSVtoRGB(h, s, v, r, g, b)
            self.Value.x = r[0]
            self.Value.y = g[0]
            self.Value.z = b[0]
            self.Value.w = a or 1.0
        end
    }
}
ImColor = ffi.metatype("ImColor", ImColor_mt)

local imcolor_ct = ffi.typeof("ImColor")

local function to_vec4(v)
    if v == nil then return ImVec4(0, 0, 0, 0) end
    if ffi.istype(imvec4_ct, v) then return v end
    if ffi.istype(imcolor_ct, v) then return v.Value end
    if type(v) == "table" then
        local src = v.Value or v
        local rx = tonumber(src.x or src[1] or src.r) or 0
        local ry = tonumber(src.y or src[2] or src.g) or 0
        local rz = tonumber(src.z or src[3] or src.b) or 0
        local rw = tonumber(src.w or src[4] or src.a) or 1
        return ImVec4(rx, ry, rz, rw)
    elseif type(v) == "number" then
        local a = bit.band(bit.rshift(v, 24), 0xFF) / 255.0
        local r = bit.band(bit.rshift(v, 16), 0xFF) / 255.0
        local g = bit.band(bit.rshift(v, 8), 0xFF) / 255.0
        local b = bit.band(v, 0xFF) / 255.0
        if a == 0 and v <= 0xFFFFFF then
            a = 1.0
        end
        return ImVec4(r, g, b, a)
    end
    return ImVec4(0, 0, 0, 0)
end

local function ImColor_ctor(r, g, b, a)
    local c = ffi.new("ImColor")
    if r ~= nil and g == nil and b == nil and a == nil then
        if ffi.istype("ImVec4", r) then
            c.Value = ImVec4(r.x, r.y, r.z, r.w)
        elseif ffi.istype("ImColor", r) then
            c.Value = ImVec4(r.Value.x, r.Value.y, r.Value.z, r.Value.w)
        elseif type(r) == "number" then
            c.Value = to_vec4(r)
        elseif type(r) == "table" then
            local src = r.Value or r
            c.Value.x = tonumber(src.x or src[1] or src.r) or 0
            c.Value.y = tonumber(src.y or src[2] or src.g) or 0
            c.Value.z = tonumber(src.z or src[3] or src.b) or 0
            c.Value.w = tonumber(src.w or src[4] or src.a) or 1
        end
    elseif r ~= nil then
        r = tonumber(r) or 0
        g = tonumber(g) or 0
        b = tonumber(b) or 0
        a = a ~= nil and (tonumber(a) or 1) or 1
        if r > 1.0 or g > 1.0 or b > 1.0 or a > 1.0 then
            r, g, b, a = r / 255.0, g / 255.0, b / 255.0, a / 255.0
        end
        c.Value.x = r
        c.Value.y = g
        c.Value.z = b
        c.Value.w = a
    else
        c.Value.w = 1.0
    end
    return c
end

mimgui.ImColor = setmetatable({
    HSV = function(h, s, v, a)
        local c = ImColor_ctor()
        c:SetHSV(h, s, v, a)
        return c
    end
}, {
    __call = function(_, ...) return ImColor_ctor(...) end
})

function mimgui.U32(r, g, b, a)
    if r and g and b and a then
        if r > 1.0 or g > 1.0 or b > 1.0 or a > 1.0 then
            r = r / 255.0
            g = g / 255.0
            b = b / 255.0
            a = a / 255.0
        end
        return ffi.C.igColorConvertFloat4ToU32(ImVec4(r, g, b, a))
    end
    return 0
end

mimgui.ColorConvertU32ToFloat4 = function(u32)
    return ffi.C.igColorConvertU32ToFloat4(u32)
end

mimgui.ColorConvertFloat4ToU32 = function(f4)
    return ffi.C.igColorConvertFloat4ToU32(to_vec4(f4))
end

local function to_vec2(v)
    if v == nil then return ImVec2(0, 0) end
    if ffi.istype(imvec2_ct, v) then return v end
    if type(v) == "table" then
        local src = v.Value or v
        return ImVec2(src.x or src[1] or 0, src.y or src[2] or 0)
    end
    return v
end

local function to_tex_ref(tex)
    local ref = ffi.new("ImTextureRef_c")
    if tex == nil then
        return ref
    end
    if type(tex) == "number" then
        ref._TexID = ffi.cast("ImTextureID", tex)
        return ref
    end
    if type(tex) == "string" then
        local num = tonumber(tex)
        if num then
            ref._TexID = ffi.cast("ImTextureID", num)
        end
        return ref
    end
    if type(tex) == "table" then
        local raw = tex.id or tex._TexID or tex[0] or tex[1] or tex.texture or tex.tex
        if raw ~= nil then
            return to_tex_ref(raw)
        end
        return ref
    end
    if type(tex) == "cdata" or type(tex) == "userdata" then
        if ffi.istype("ImTextureRef_c", tex) then
            return tex
        end
        local ok_cast, casted = pcall(ffi.cast, "ImTextureID", tex)
        if ok_cast then
            ref._TexID = casted
            return ref
        end
    end
    return ref
end

local function translate_corner_flags(flags)
    if not flags or flags == 0 then
        return 0
    end
    if flags > 0 and flags <= 15 then
        return bit.lshift(flags, 4)
    end
    if bit.band(flags, 15) ~= 0 and bit.band(flags, 240) == 0 then
        local low = bit.band(flags, 15)
        local rest = bit.band(flags, bit.bnot(15))
        return bit.bor(rest, bit.lshift(low, 4))
    end
    return flags
end

local ImGuiListClipper_mt = {
    __index = {
        Begin = function(self, count, height)
            if self.TempData ~= nil then
                pcall(ffi.C.ImGuiListClipper_End, self)
            end
            local has_win = false
            local ok, win = pcall(ffi.C.igGetCurrentWindowRead)
            if ok and win ~= nil and win ~= ffi.null then has_win = true end
            if has_win then
                ffi.C.ImGuiListClipper_Begin(self, count or 0, height or -1.0)
            else
                self.ItemsCount = count or 0
                self.ItemsHeight = height or -1.0
                self.DisplayStart = -1
                self.DisplayEnd = 0
            end
        end,
        End = function(self)
            if self.TempData ~= nil then
                ffi.C.ImGuiListClipper_End(self)
            else
                self.ItemsCount = -1
                self.ItemsHeight = -1.0
                self.DisplayStart = 0
                self.DisplayEnd = 0
            end
        end,
        Step = function(self)
            if self.TempData ~= nil then
                return ffi.C.ImGuiListClipper_Step(self)
            end
            if self.DisplayStart < 0 and self.ItemsCount > 0 then
                self.DisplayStart = 0
                self.DisplayEnd = self.ItemsCount
                return true
            end
            return false
        end,
        IncludeItemByIndex = function(self, item_index)
            if self.TempData ~= nil then
                ffi.C.ImGuiListClipper_IncludeItemByIndex(self, item_index)
            end
        end,
        IncludeItemsByIndex = function(self, item_begin, item_end)
            if self.TempData ~= nil then
                ffi.C.ImGuiListClipper_IncludeItemsByIndex(self, item_begin, item_end)
            end
        end,
        SeekCursorForItem = function(self, item_index)
            if self.TempData ~= nil then
                ffi.C.ImGuiListClipper_SeekCursorForItem(self, item_index)
            end
        end,
    }
}
ffi.metatype("ImGuiListClipper", ImGuiListClipper_mt)

local function ImGuiListClipper_ctor(count, height)
    local clipper = ffi.new("ImGuiListClipper")
    ffi.gc(clipper, function(self)
        if self.TempData ~= nil then
            pcall(ffi.C.ImGuiListClipper_End, self)
        end
    end)
    if count ~= nil then
        clipper:Begin(count, height or -1.0)
    end
    return clipper
end

mimgui.ImGuiListClipper = setmetatable({}, {
    __call = function(_, ...) return ImGuiListClipper_ctor(...) end
})

local ImGuiTextFilter_mt = {
    __index = {
        Build = function(self)
            ffi.C.ImGuiTextFilter_Build(self)
        end,
        Clear = function(self)
            ffi.C.ImGuiTextFilter_Clear(self)
        end,
        Draw = function(self, label, width)
            return ffi.C.ImGuiTextFilter_Draw(self, label or "Filter", width or 0.0)
        end,
        PassFilter = function(self, text, text_end)
            return ffi.C.ImGuiTextFilter_PassFilter(self, text, text_end)
        end,
        IsActive = function(self)
            return ffi.C.ImGuiTextFilter_IsActive(self)
        end,
    }
}
ffi.metatype("ImGuiTextFilter", ImGuiTextFilter_mt)

local function ImGuiTextFilter_ctor(default_filter)
    local ptr = ffi.C.ImGuiTextFilter_ImGuiTextFilter(default_filter and tostring(default_filter) or "")
    if ptr ~= nil then
        return ffi.gc(ptr, ffi.C.ImGuiTextFilter_destroy)
    end
    return nil
end

mimgui.ImGuiTextFilter = setmetatable({}, {
    __call = function(_, ...) return ImGuiTextFilter_ctor(...) end
})

local ImFontConfig_mt = {
    __index = function(self, k)
        if k == "FontBuilderFlags" then
            return self.FontLoaderFlags
        elseif k == "GlyphExtraSpacing" then
            return setmetatable({}, {
                __index = function(_, ax)
                    if ax == "x" then return self.GlyphExtraAdvanceX end
                    return 0
                end,
                __newindex = function(_, ax, val)
                    if ax == "x" then self.GlyphExtraAdvanceX = tonumber(val) or 0 end
                end
            })
        end
    end,
    __newindex = function(self, k, v)
        if k == "FontBuilderFlags" then
            self.FontLoaderFlags = v
        elseif k == "GlyphExtraSpacing" then
            if type(v) == "table" or type(v) == "cdata" then
                self.GlyphExtraAdvanceX = tonumber(v.x) or 0
            end
        end
    end
}
ffi.metatype("ImFontConfig", ImFontConfig_mt)

local function ImFontConfig_ctor()
    local raw = ffi.C.ImFontConfig_ImFontConfig()
    return ffi.gc(raw, ffi.C.ImFontConfig_destroy)
end

mimgui.ImFontConfig = function()
    return ImFontConfig_ctor()
end

local ImFont_methods = {
    CalcTextSizeA = function(self, size, max_width, wrap_width, text, text_end, out_remaining)
        local max_w = tonumber(max_width) or 3.402823466e+38
        local wrap_w = tonumber(wrap_width) or 0.0
        local sz = tonumber(size) or (self.FontSize > 0 and self.FontSize or 14.0)
        local text_str = tostring(text or "")
        local res = ffi.C.ImFont_CalcTextSizeA(self, sz, max_w, wrap_w, text_str, text_end or ffi.null, out_remaining or ffi.null)
        return ImVec2(res.x, res.y)
    end,
    FindGlyph = function(self, c)
        return ffi.C.ImFont_FindGlyph(self, c)
    end,
    FindGlyphNoFallback = function(self, c)
        return ffi.C.ImFont_FindGlyphNoFallback(self, c)
    end,
    GetCharAdvance = function(self, c)
        return ffi.C.ImFont_GetCharAdvance(self, c)
    end,
    IsLoaded = function(self)
        return ffi.C.ImFont_IsLoaded(self)
    end,
    GetDebugName = function(self)
        local str = ffi.C.ImFont_GetDebugName(self)
        return str ~= ffi.null and ffi.string(str) or ""
    end,
}

ffi.metatype("ImFont", {
    __index = function(self, k)
        if k == "ConfigData" then
            return self.Sources
        elseif k == "ConfigDataCount" then
            return self.Sources ~= nil and self.Sources.Size or 0
        end
        return ImFont_methods[k]
    end,
})

local function to_u32_color(c)
    if type(c) == "number" then
        return c
    elseif type(c) == "cdata" then
        if ffi.istype("ImVec4", c) then
            return ffi.C.igColorConvertFloat4ToU32(c)
        elseif ffi.istype("ImColor", c) then
            return ffi.C.igColorConvertFloat4ToU32(c.Value)
        end
        return ffi.cast("uint32_t", c)
    elseif type(c) == "table" then
        return ffi.C.igColorConvertFloat4ToU32(to_vec4(c))
    end
    return 0xFFFFFFFF
end

local ImDrawList_methods = {
    AddLine = function(self, p1, p2, col, thickness)
        local r = ffi.C.ImDrawList_AddLine(self, to_vec2(p1), to_vec2(p2), to_u32_color(col), thickness or 1.0)
        return r
    end,
    AddRect = function(self, p_min, p_max, col, rounding, flags, thickness)
        flags = translate_corner_flags(flags or 0)
        local r = ffi.C.ImDrawList_AddRect(self, to_vec2(p_min), to_vec2(p_max), to_u32_color(col), rounding or 0.0, flags, thickness or 1.0)
        return r
    end,
    AddRectFilled = function(self, p_min, p_max, col, rounding, flags)
        flags = translate_corner_flags(flags or 0)
        local r = ffi.C.ImDrawList_AddRectFilled(self, to_vec2(p_min), to_vec2(p_max), to_u32_color(col), rounding or 0.0, flags)
        return r
    end,
    AddCircle = function(self, center, radius, col, num_segments, thickness)
        local r = ffi.C.ImDrawList_AddCircle(self, to_vec2(center), radius, to_u32_color(col), num_segments or 0, thickness or 1.0)
        return r
    end,
    AddCircleFilled = function(self, center, radius, col, num_segments)
        local r = ffi.C.ImDrawList_AddCircleFilled(self, to_vec2(center), radius, to_u32_color(col), num_segments or 0)
        return r
    end,
    AddText = function(self, arg1, arg2, arg3, arg4, arg5, arg6, arg7)
        if type(arg1) == "cdata" and ffi.istype("ImFont*", arg1) then
            local clip_rect = nil
            if arg7 ~= nil then
                if type(arg7) == "cdata" and ffi.istype("ImVec4", arg7) then
                    clip_rect = arg7
                elseif type(arg7) == "table" then
                    clip_rect = ffi.new("ImVec4[1]", to_vec4(arg7))
                end
            end
            local r = ffi.C.ImDrawList_AddText_FontPtr(self, arg1, arg2, to_vec2(arg3), to_u32_color(arg4), tostring(arg5 or ""), nil, arg6 or 0.0, clip_rect)
            return r
        else
            local r = ffi.C.ImDrawList_AddText_Vec2(self, to_vec2(arg1), to_u32_color(arg2), tostring(arg3 or ""), nil)
            return r
        end
    end,
    AddTextFontPtr = function(self, font, font_size, pos, col, text_begin, text_end, wrap_width, cpu_fine_clip_rect)
        local clip_rect = nil
        if cpu_fine_clip_rect ~= nil then
            if type(cpu_fine_clip_rect) == "cdata" and ffi.istype("ImVec4", cpu_fine_clip_rect) then
                clip_rect = cpu_fine_clip_rect
            elseif type(cpu_fine_clip_rect) == "table" then
                clip_rect = ffi.new("ImVec4[1]", to_vec4(cpu_fine_clip_rect))
            end
        end
        local text_str = tostring(text_begin or "")
        return ffi.C.ImDrawList_AddText_FontPtr(self, font, font_size or 14.0, to_vec2(pos), to_u32_color(col), text_str, text_end or ffi.null, wrap_width or 0.0, clip_rect)
    end,
    AddTextVec2 = function(self, pos, col, text_begin, text_end)
        return ffi.C.ImDrawList_AddText_Vec2(self, to_vec2(pos), to_u32_color(col), tostring(text_begin or ""), text_end or ffi.null)
    end,
    AddImage = function(self, tex, p_min, p_max, uv_min, uv_max, col)
        local ref = to_tex_ref(tex)
        local c = to_u32_color(col or 0xFFFFFFFF)
        local r = ffi.C.ImDrawList_AddImage(self, ref, to_vec2(p_min), to_vec2(p_max), to_vec2(uv_min or {0, 0}), to_vec2(uv_max or {1, 1}), c)
        return r
    end,
    PathClear = function(self)
        local r = ffi.C.ImDrawList_PathClear(self)
        return r
    end,
    PathLineTo = function(self, pos)
        local r = ffi.C.ImDrawList_PathLineTo(self, to_vec2(pos))
        return r
    end,
    PathLineToMergeDuplicate = function(self, pos)
        local r = ffi.C.ImDrawList_PathLineToMergeDuplicate(self, to_vec2(pos))
        return r
    end,
    PathFillConvex = function(self, col)
        local r = ffi.C.ImDrawList_PathFillConvex(self, to_u32_color(col))
        return r
    end,
    PathFillConcave = function(self, col)
        local r = ffi.C.ImDrawList_PathFillConcave(self, to_u32_color(col))
        return r
    end,
    PathStroke = function(self, col, flags, thickness)
        local r = ffi.C.ImDrawList_PathStroke(self, to_u32_color(col), flags or 0, thickness or 1.0)
        return r
    end,
    PathArcTo = function(self, center, radius, a_min, a_max, num_segments)
        local r = ffi.C.ImDrawList_PathArcTo(self, to_vec2(center), radius, a_min, a_max, num_segments or 0)
        return r
    end,
    PathArcToFast = function(self, center, radius, a_min_of_12, a_max_of_12)
        local r = ffi.C.ImDrawList_PathArcToFast(self, to_vec2(center), radius, a_min_of_12, a_max_of_12)
        return r
    end,
    PathEllipticalArcTo = function(self, center, radius, rot, a_min, a_max, num_segments)
        local r = ffi.C.ImDrawList_PathEllipticalArcTo(self, to_vec2(center), to_vec2(radius), rot or 0.0, a_min, a_max, num_segments or 0)
        return r
    end,
    PathBezierCubicCurveTo = function(self, p2, p3, p4, num_segments)
        local r = ffi.C.ImDrawList_PathBezierCubicCurveTo(self, to_vec2(p2), to_vec2(p3), to_vec2(p4), num_segments or 0)
        return r
    end,
    PathBezierQuadraticCurveTo = function(self, p2, p3, num_segments)
        local r = ffi.C.ImDrawList_PathBezierQuadraticCurveTo(self, to_vec2(p2), to_vec2(p3), num_segments or 0)
        return r
    end,
    PathRect = function(self, rect_min, rect_max, rounding, flags)
        local r = ffi.C.ImDrawList_PathRect(self, to_vec2(rect_min), to_vec2(rect_max), rounding or 0.0, flags or 0)
        return r
    end,
    PushClipRect = function(self, clip_rect_min, clip_rect_max, intersect_with_current_clip_rect)
        local r = ffi.C.ImDrawList_PushClipRect(self, to_vec2(clip_rect_min), to_vec2(clip_rect_max), intersect_with_current_clip_rect or false)
        return r
    end,
    PushClipRectFullScreen = function(self)
        local r = ffi.C.ImDrawList_PushClipRectFullScreen(self)
        return r
    end,
    PopClipRect = function(self)
        local r = ffi.C.ImDrawList_PopClipRect(self)
        return r
    end,
    AddPolyline = function(self, points, num_points, col, flags, thickness)
        num_points = num_points or #points
        local pArr = ffi.new("ImVec2[?]", num_points)
        for i = 0, num_points - 1 do
            pArr[i] = to_vec2(points[i + 1])
        end
        local r = ffi.C.ImDrawList_AddPolyline(self, pArr, num_points, to_u32_color(col), flags or 0, thickness or 1.0)
        return r
    end,
    AddConvexPolyFilled = function(self, points, num_points, col)
        num_points = num_points or #points
        local pArr = ffi.new("ImVec2[?]", num_points)
        for i = 0, num_points - 1 do
            pArr[i] = to_vec2(points[i + 1])
        end
        local r = ffi.C.ImDrawList_AddConvexPolyFilled(self, pArr, num_points, to_u32_color(col))
        return r
    end,
    AddBezierQuadratic = function(self, p1, p2, p3, col, thickness, num_segments)
        local r = ffi.C.ImDrawList_AddBezierQuadratic(self, to_vec2(p1), to_vec2(p2), to_vec2(p3), to_u32_color(col), thickness or 1.0, num_segments or 0)
        return r
    end,
    PathBezierQuadraticCurveTo = function(self, p2, p3, num_segments)
        local r = ffi.C.ImDrawList_PathBezierQuadraticCurveTo(self, to_vec2(p2), to_vec2(p3), num_segments or 0)
        return r
    end,
    ShadeVertsLinearUV = function(self, vert_start_idx, vert_end_idx, a, b, uv_a, uv_b, clamp)
        local r = ffi.C.igShadeVertsLinearUV(self, vert_start_idx, vert_end_idx, to_vec2(a), to_vec2(b), to_vec2(uv_a), to_vec2(uv_b), clamp or false)
        return r
    end,
    ShadeVertsTransformPos = function(self, vert_start_idx, vert_end_idx, pivot_in, cos_a, sin_a, pivot_out)
        local r = ffi.C.igShadeVertsTransformPos(self, vert_start_idx, vert_end_idx, to_vec2(pivot_in), cos_a, sin_a, to_vec2(pivot_out))
        return r
    end,
    AddRectFilledMultiColor = function(self, p_min, p_max, col_upr_left, col_upr_right, col_bot_right, col_bot_left)
        local r = ffi.C.ImDrawList_AddRectFilledMultiColor(self, to_vec2(p_min), to_vec2(p_max), to_u32_color(col_upr_left), to_u32_color(col_upr_right), to_u32_color(col_bot_right), to_u32_color(col_bot_left))
        return r
    end,
    AddQuad = function(self, p1, p2, p3, p4, col, thickness)
        local r = ffi.C.ImDrawList_AddQuad(self, to_vec2(p1), to_vec2(p2), to_vec2(p3), to_vec2(p4), to_u32_color(col), thickness or 1.0)
        return r
    end,
    AddQuadFilled = function(self, p1, p2, p3, p4, col)
        local r = ffi.C.ImDrawList_AddQuadFilled(self, to_vec2(p1), to_vec2(p2), to_vec2(p3), to_vec2(p4), to_u32_color(col))
        return r
    end,
    AddTriangle = function(self, p1, p2, p3, col, thickness)
        local r = ffi.C.ImDrawList_AddTriangle(self, to_vec2(p1), to_vec2(p2), to_vec2(p3), to_u32_color(col), thickness or 1.0)
        return r
    end,
    AddTriangleFilled = function(self, p1, p2, p3, col)
        local r = ffi.C.ImDrawList_AddTriangleFilled(self, to_vec2(p1), to_vec2(p2), to_vec2(p3), to_u32_color(col))
        return r
    end,
    AddNgon = function(self, center, radius, col, num_segments, thickness)
        local r = ffi.C.ImDrawList_AddNgon(self, to_vec2(center), radius, to_u32_color(col), num_segments or 0, thickness or 1.0)
        return r
    end,
    AddNgonFilled = function(self, center, radius, col, num_segments)
        local r = ffi.C.ImDrawList_AddNgonFilled(self, to_vec2(center), radius, to_u32_color(col), num_segments or 0)
        return r
    end,
    AddBezierCubic = function(self, p1, p2, p3, p4, col, thickness, num_segments)
        local r = ffi.C.ImDrawList_AddBezierCubic(self, to_vec2(p1), to_vec2(p2), to_vec2(p3), to_vec2(p4), to_u32_color(col), thickness or 1.0, num_segments or 0)
        return r
    end,
    PathRect = function(self, p_min, p_max, rounding, flags)
        flags = translate_corner_flags(flags or 0)
        local r = ffi.C.ImDrawList_PathRect(self, to_vec2(p_min), to_vec2(p_max), rounding or 0.0, flags)
        return r
    end,
    PathFillConvex = function(self, col)
        local r = ffi.C.ImDrawList_PathFillConvex(self, to_u32_color(col))
        return r
    end,
    PrimReserve = function(self, idx_count, vtx_count)
        local r = ffi.C.ImDrawList_PrimReserve(self, idx_count, vtx_count)
        return r
    end,
    PrimRect = function(self, a, b, col)
        local r = ffi.C.ImDrawList_PrimRect(self, to_vec2(a), to_vec2(b), to_u32_color(col))
        return r
    end,
    PrimUnreserve = function(self, idx_count, vtx_count)
        local r = ffi.C.ImDrawList_PrimUnreserve(self, idx_count, vtx_count)
        return r
    end,
    PrimWriteVtx = function(self, pos, uv, col)
        if not uv or (uv.x == 0 and uv.y == 0) then
            if self._Data ~= nil and self._Data ~= ffi.null and self._Data.TexUvWhitePixel ~= nil then
                uv = self._Data.TexUvWhitePixel
            else
                uv = ffi.C.igGetFontTexUvWhitePixel()
            end
        end
        local c = to_u32_color(col)
        local r = ffi.C.ImDrawList_PrimWriteVtx(self, to_vec2(pos), to_vec2(uv), c)
        return r
    end,
    PrimWriteIdx = function(self, idx)
        local r = ffi.C.ImDrawList_PrimWriteIdx(self, idx)
        return r
    end,
    PushTextureID = function(self, tex)
        local r = ffi.C.ImDrawList_PushTexture(self, to_tex_ref(tex))
        return r
    end,
    PopTextureID = function(self)
        local r = ffi.C.ImDrawList_PopTexture(self)
        return r
    end,
    PushTexture = function(self, tex)
        local r = ffi.C.ImDrawList_PushTexture(self, to_tex_ref(tex))
        return r
    end,
    PopTexture = function(self)
        local r = ffi.C.ImDrawList_PopTexture(self)
        return r
    end
}

local dummy_draw_vert = ffi.new("ImDrawVert")

local cur_vert_vec = nil
local vert_data_proxy_meta = {
    __index = function(_, idx)
        if type(idx) == "number" then
            if cur_vert_vec ~= nil and cur_vert_vec._Data ~= nil and idx >= 0 and idx < cur_vert_vec.Size then
                return cur_vert_vec._Data[idx]
            end
        else
            local num = tonumber(idx)
            if num and cur_vert_vec ~= nil and cur_vert_vec._Data ~= nil and num >= 0 and num < cur_vert_vec.Size then
                return cur_vert_vec._Data[num]
            end
        end
        return dummy_draw_vert
    end,
    __newindex = function(_, idx, val)
        if type(idx) == "number" then
            if cur_vert_vec ~= nil and cur_vert_vec._Data ~= nil and idx >= 0 and idx < cur_vert_vec.Size then
                cur_vert_vec._Data[idx] = val
                return
            end
        else
            local num = tonumber(idx)
            if num and cur_vert_vec ~= nil and cur_vert_vec._Data ~= nil and num >= 0 and num < cur_vert_vec.Size then
                cur_vert_vec._Data[num] = val
                return
            end
        end
    end,
    __tostring = function() return "ImDrawVertDataProxy" end
}

local cur_idx_vec = nil
local idx_data_proxy_meta = {
    __index = function(_, idx)
        if type(idx) == "number" then
            if cur_idx_vec ~= nil and cur_idx_vec._Data ~= nil and idx >= 0 and idx < cur_idx_vec.Size then
                return cur_idx_vec._Data[idx]
            end
        else
            local num = tonumber(idx)
            if num and cur_idx_vec ~= nil and cur_idx_vec._Data ~= nil and num >= 0 and num < cur_idx_vec.Size then
                return cur_idx_vec._Data[num]
            end
        end
        return 0
    end,
    __newindex = function(_, idx, val)
        if type(idx) == "number" then
            if cur_idx_vec ~= nil and cur_idx_vec._Data ~= nil and idx >= 0 and idx < cur_idx_vec.Size then
                cur_idx_vec._Data[idx] = val
                return
            end
        else
            local num = tonumber(idx)
            if num and cur_idx_vec ~= nil and cur_idx_vec._Data ~= nil and num >= 0 and num < cur_idx_vec.Size then
                cur_idx_vec._Data[num] = val
                return
            end
        end
    end,
    __tostring = function() return "ImDrawIdxDataProxy" end
}

local vert_proxy = setmetatable({}, vert_data_proxy_meta)
local idx_proxy = setmetatable({}, idx_data_proxy_meta)

ffi.metatype("ImVector_ImDrawVert", {
    __index = function(self, k)
        if k == "Data" then
            cur_vert_vec = self
            return vert_proxy
        end
    end
})

ffi.metatype("ImVector_ImDrawIdx", {
    __index = function(self, k)
        if k == "Data" then
            cur_idx_vec = self
            return idx_proxy
        end
    end
})

local function get_drawlist_c_fn(name)
    return ffi.C["ImDrawList_" .. name]
end

local function dl_index(self, k)
    local m = ImDrawList_methods[k]
    if m ~= nil then return m end
    local ok, fn = pcall(get_drawlist_c_fn, k)
    if ok and fn ~= nil then
        ImDrawList_methods[k] = fn
        return fn
    end
    return nil
end

ffi.metatype("ImDrawList", {
    __index = dl_index
})

ffi.metatype("ImVector_ImDrawListPtr", {
    __index = function(self, k)
        if type(k) == "number" then
            if self.Data ~= nil and k >= 0 and k < self.Size then
                return self.Data[k]
            end
            return nil
        end
        return nil
    end
})

ffi.metatype("struct ImDrawData", {
    __index = function(self, k)
        if k == "CmdListsCount" then
            return self.CmdLists.Size
        end
        return nil
    end
})

mimgui.ShadeVertsLinearUV = function(dl, vert_start_idx, vert_end_idx, a, b, uv_a, uv_b, clamp)
    return ffi.C.igShadeVertsLinearUV(dl, vert_start_idx, vert_end_idx, to_vec2(a), to_vec2(b), to_vec2(uv_a), to_vec2(uv_b), clamp or false)
end

mimgui.ShadeVertsTransformPos = function(dl, vert_start_idx, vert_end_idx, pivot_in, cos_a, sin_a, pivot_out)
    return ffi.C.igShadeVertsTransformPos(dl, vert_start_idx, vert_end_idx, to_vec2(pivot_in), cos_a, sin_a, to_vec2(pivot_out))
end

local pinned_font_resources = {}

local function pin_font_resource(res)
    if res ~= nil and res ~= ffi.null then
        pinned_font_resources[#pinned_font_resources + 1] = res
    end
end

local function normalize_glyph_ranges(glyph_ranges)
    if glyph_ranges == nil or glyph_ranges == ffi.null then
        return ffi.null
    end
    if type(glyph_ranges) == "table" and mimgui and mimgui.ImGlyphRanges then
        return mimgui.ImGlyphRanges(glyph_ranges)
    end
    if type(glyph_ranges) == "cdata" then
        if ffi.istype("ImVector_ImWchar", glyph_ranges) or ffi.istype("ImVector_ImWchar*", glyph_ranges) then
            return glyph_ranges.Data
        end
        local ok, data = pcall(function() return glyph_ranges.Data end)
        if ok and data ~= nil then
            return data
        end
    end
    return glyph_ranges
end

local function ensure_base_font(self, font_cfg)
    if font_cfg and font_cfg.MergeMode and (self.Fonts.Size == 0 or self.Fonts.Data == nil) then
        ffi.C.ImFontAtlas_AddFontDefault(self, nil)
    end
end

local atlas_methods = {
    AddFontDefault = function(self, font_cfg)
        pin_font_resource(font_cfg)
        return ffi.C.ImFontAtlas_AddFontDefault(self, font_cfg)
    end,
    AddFontFromFileTTF = function(self, filename, size_pixels, font_cfg, glyph_ranges)
        ensure_base_font(self, font_cfg)
        glyph_ranges = normalize_glyph_ranges(glyph_ranges)
        pin_font_resource(filename)
        pin_font_resource(font_cfg)
        pin_font_resource(glyph_ranges)
        return ffi.C.ImFontAtlas_AddFontFromFileTTF(self, filename, size_pixels, font_cfg, glyph_ranges)
    end,
    AddFontFromMemoryTTF = function(self, font_data, font_size, size_pixels, font_cfg, glyph_ranges)
        ensure_base_font(self, font_cfg)
        glyph_ranges = normalize_glyph_ranges(glyph_ranges)
        pin_font_resource(font_data)
        pin_font_resource(font_cfg)
        pin_font_resource(glyph_ranges)
        return ffi.C.ImFontAtlas_AddFontFromMemoryTTF(self, font_data, font_size, size_pixels, font_cfg, glyph_ranges)
    end,
    AddFontFromMemoryCompressedTTF = function(self, compressed_font_data, compressed_font_size, size_pixels, font_cfg, glyph_ranges)
        ensure_base_font(self, font_cfg)
        glyph_ranges = normalize_glyph_ranges(glyph_ranges)
        pin_font_resource(compressed_font_data)
        pin_font_resource(font_cfg)
        pin_font_resource(glyph_ranges)
        return ffi.C.ImFontAtlas_AddFontFromMemoryCompressedTTF(self, compressed_font_data, compressed_font_size, size_pixels, font_cfg, glyph_ranges)
    end,
    AddFontFromMemoryCompressedBase85TTF = function(self, compressed_font_data_base85, size_pixels, font_cfg, glyph_ranges)
        ensure_base_font(self, font_cfg)
        glyph_ranges = normalize_glyph_ranges(glyph_ranges)
        pin_font_resource(compressed_font_data_base85)
        pin_font_resource(font_cfg)
        pin_font_resource(glyph_ranges)
        return ffi.C.ImFontAtlas_AddFontFromMemoryCompressedBase85TTF(self, compressed_font_data_base85, size_pixels, font_cfg, glyph_ranges)
    end,
    ClearTexData = function(self)
        ffi.C.ImFontAtlas_ClearTexData(self)
    end,
    ClearFonts = function(self)
        ffi.C.ImFontAtlas_ClearFonts(self)
        local ok_io, io = pcall(ffi.C.igGetIO_Nil)
        if ok_io and io ~= nil and io ~= ffi.null then
            io.FontDefault = nil
        end
    end,
    ClearInputData = function(self)
        ffi.C.ImFontAtlas_ClearInputData(self)
    end,
    Clear = function(self)
        ffi.C.ImFontAtlas_Clear(self)
        pinned_font_resources = {}
        local ok_io, io = pcall(ffi.C.igGetIO_Nil)
        if ok_io and io ~= nil and io ~= ffi.null then
            io.FontDefault = nil
        end
    end,
    Build = function(self)
        local res = ffi.C.ImFontAtlas_Build(self)
        local ok_io, io = pcall(ffi.C.igGetIO_Nil)
        if ok_io and io ~= nil and io ~= ffi.null then
            if (io.FontDefault == nil or io.FontDefault == ffi.null) and self.Fonts.Size > 0 then
                io.FontDefault = self.Fonts.Data[0]
            end
        end
        return res
    end,
    IsBuilt = function(self)
        return ffi.C.ImFontAtlas_IsBuilt(self)
    end,
    GetGlyphRangesDefault = function(self)
        return ffi.C.ImFontAtlas_GetGlyphRangesDefault(self)
    end,
    GetGlyphRangesKorean = function(self)
        return ffi.C.ImFontAtlas_GetGlyphRangesKorean(self)
    end,
    GetGlyphRangesJapanese = function(self)
        return ffi.C.ImFontAtlas_GetGlyphRangesJapanese(self)
    end,
    GetGlyphRangesChineseFull = function(self)
        return ffi.C.ImFontAtlas_GetGlyphRangesChineseFull(self)
    end,
    GetGlyphRangesChineseSimplifiedCommon = function(self)
        return ffi.C.ImFontAtlas_GetGlyphRangesChineseSimplifiedCommon(self)
    end,
    GetGlyphRangesCyrillic = function(self)
        return ffi.C.ImFontAtlas_GetGlyphRangesCyrillic(self)
    end,
    GetGlyphRangesThai = function(self)
        return ffi.C.ImFontAtlas_GetGlyphRangesThai(self)
    end,
    GetGlyphRangesGreek = function(self)
        return ffi.C.ImFontAtlas_GetGlyphRangesGreek(self)
    end,
    GetGlyphRangesVietnamese = function(self)
        return ffi.C.ImFontAtlas_GetGlyphRangesVietnamese(self)
    end,
    GetFont = function(self, idx)
        idx = idx or 0
        if self.Fonts ~= nil and self.Fonts.Size > idx and idx >= 0 then
            return self.Fonts.Data[idx]
        end
        return nil
    end,
}

ffi.metatype("ImFontAtlas", {
    __index = function(self, k)
        if k == "FontsCount" then
            return self.Fonts ~= nil and self.Fonts.Size or 0
        elseif k == "ConfigData" then
            if self.Sources ~= nil and self.Sources.Size > 0 and self.Sources.Data ~= nil then
                return self.Sources
            end
            local default_ranges = ffi.C.ImFontAtlas_GetGlyphRangesDefault(self)
            local fallback_cfg = imgui.ImFontConfig()
            fallback_cfg.GlyphRanges = default_ranges
            local proxy = {
                Size = 1,
                Data = setmetatable({}, {
                    __index = function(d, idx)
                        return fallback_cfg
                    end
                })
            }
            return setmetatable(proxy, {
                __index = function(t, idx)
                    if type(idx) == "number" then return fallback_cfg end
                    return rawget(t, idx)
                end
            })
        end
        return atlas_methods[k]
    end
})

local ImFontGlyphRangesBuilder_methods = {
    Clear = function(self)
        ffi.C.ImFontGlyphRangesBuilder_Clear(self)
    end,
    GetBit = function(self, n)
        return ffi.C.ImFontGlyphRangesBuilder_GetBit(self, n)
    end,
    SetBit = function(self, n)
        ffi.C.ImFontGlyphRangesBuilder_SetBit(self, n)
    end,
    AddChar = function(self, c)
        if type(c) == "string" then
            c = c:byte(1) or 0
        end
        ffi.C.ImFontGlyphRangesBuilder_AddChar(self, c or 0)
    end,
    AddText = function(self, text, text_end)
        text = tostring(text or "")
        ffi.C.ImFontGlyphRangesBuilder_AddText(self, text, text_end or ffi.null)
    end,
    AddRanges = function(self, ranges)
        ranges = normalize_glyph_ranges(ranges)
        if ranges ~= nil and ranges ~= ffi.null then
            pin_font_resource(ranges)
            ffi.C.ImFontGlyphRangesBuilder_AddRanges(self, ranges)
        end
    end,
    BuildRanges = function(self, out_ranges)
        if out_ranges ~= nil and out_ranges ~= ffi.null then
            if ffi.istype("ImVector_ImWchar*", out_ranges) or ffi.istype("ImVector_ImWchar", out_ranges) then
                ffi.C.ImFontGlyphRangesBuilder_BuildRanges(self, out_ranges)
            end
        end
    end,
}

ffi.metatype("ImFontGlyphRangesBuilder", {
    __index = ImFontGlyphRangesBuilder_methods
})

local function ImFontGlyphRangesBuilder_ctor()
    local ptr = ffi.C.ImFontGlyphRangesBuilder_ImFontGlyphRangesBuilder()
    if ptr == nil or ptr == ffi.null then return nil end
    return ffi.gc(ptr, ffi.C.ImFontGlyphRangesBuilder_destroy)
end

mimgui.ImFontGlyphRangesBuilder = setmetatable({
    __call = function(_, ...) return ImFontGlyphRangesBuilder_ctor(...) end
}, {
    __call = function(_, ...) return ImFontGlyphRangesBuilder_ctor(...) end
})

ffi.metatype("ImVector_ImWchar", {
    __index = function(self, k)
        if type(k) == "number" then
            if k == 0 then
                return self
            end
            if self.Data ~= nil and k >= 0 and k < self.Size then
                return self.Data[k]
            end
            return nil
        end
        return nil
    end,
    __len = function(self)
        return self.Size
    end
})

local function ImVector_ImWchar_ctor()
    local ptr = ffi.C.ImVector_ImWchar_create()
    if ptr == nil or ptr == ffi.null then return nil end
    return ffi.gc(ptr, ffi.C.ImVector_ImWchar_destroy)
end

mimgui.ImVector_ImWchar = setmetatable({
    __call = function(_, ...) return ImVector_ImWchar_ctor(...) end
}, {
    __call = function(_, ...) return ImVector_ImWchar_ctor(...) end
})

local abs_drag_cache = {}
for i = 0, 4 do
    abs_drag_cache[i] = ImVec2(0, 0)
end

local io_compat = {
    MouseDragMaxDistanceAbs = setmetatable({}, {
        __index = function(_, btn)
            local b = tonumber(btn) or 0
            if b < 0 or b > 4 then b = 0 end
            local dist = 0
            local ok, io = pcall(ffi.C.igGetIO_Nil)
            if ok and io ~= nil and io ~= ffi.null then
                local ok_sqr, sqr = pcall(function() return io.MouseDragMaxDistanceSqr[b] end)
                if ok_sqr and sqr and sqr > 0 then
                    dist = math.sqrt(sqr)
                end
            end
            local ok_delta, delta = pcall(ffi.C.igGetMouseDragDelta, b, -1.0)
            local vx = dist
            local vy = dist
            if ok_delta and delta then
                vx = math.max(vx, math.abs(delta.x))
                vy = math.max(vy, math.abs(delta.y))
            end
            abs_drag_cache[b].x = vx
            abs_drag_cache[b].y = vy
            return abs_drag_cache[b]
        end
    }),
    KeysDown = setmetatable({}, {
        __index = function(_, k)
            if type(k) == "number" then
                local ok, res = pcall(ffi.C.igIsKeyDown_Nil, k)
                return ok and res or false
            end
            return false
        end
    }),
    KeyMap = {},
    NavInputs = ffi.new("float[64]"),
    AddInputCharacter = function(self, c)
        ffi.C.ImGuiIO_AddInputCharacter(self, c)
    end,
    AddInputCharactersUTF8 = function(self, str)
        ffi.C.ImGuiIO_AddInputCharactersUTF8(self, str)
    end,
}

ffi.metatype("ImGuiIO", {
    __index = function(self, k)
        if k == "FontGlobalScale" then
            local ok_style, style = pcall(ffi.C.igGetStyle)
            if ok_style and style ~= nil and style ~= ffi.null then
                return style.FontScaleMain
            end
            return io_compat.FontGlobalScale or 1.0
        end
        return io_compat[k]
    end,
    __newindex = function(self, k, v)
        if k == "FontGlobalScale" then
            io_compat.FontGlobalScale = v
            local ok_style, style = pcall(ffi.C.igGetStyle)
            if ok_style and style ~= nil and style ~= ffi.null then
                style.FontScaleMain = v
            end
            return
        end
        io_compat[k] = v
    end
})

local function make_vec_type(base_type)
    return setmetatable({}, {
        __call = function(_, val)
            local c = ffi.new(base_type .. "[1]")
            if val ~= nil then c[0] = val end
            return c
        end,
        __index = function(_, size)
            size = tonumber(size)
            return function(...)
                local c
                if base_type == "char" then
                    c = ffi.new("char[?]", size)
                    cdata_lengths[c] = size
                    local init = ...
                    if type(init) == "string" then
                        ffi.copy(c, init, math.min(#init, size - 1))
                    end
                else
                    c = ffi.new(base_type .. "[?]", size)
                    cdata_lengths[c] = size
                    local n = select("#", ...)
                    if n == 1 and type(...) == "table" then
                        local t = ...
                        for i = 0, math.min(#t, size) - 1 do c[i] = t[i + 1] end
                    else
                        for i = 0, math.min(n, size) - 1 do c[i] = select(i + 1, ...) end
                    end
                end
                return c
            end
        end
    })
end

local new_allocator = {
    bool = make_vec_type("bool"),
    int = make_vec_type("int"),
    uint = make_vec_type("unsigned int"),
    float = make_vec_type("float"),
    double = make_vec_type("double"),
    short = make_vec_type("short"),
    char = make_vec_type("char"),
    ImColor = mimgui.ImColor,
    ImVec2 = mimgui.ImVec2,
    ImVec4 = mimgui.ImVec4,
}

setmetatable(new_allocator, {
    __call = function(_, type_str, ...)
        if type(type_str) ~= "string" then
            if type_str == nil then return nil end
            local ok, res = pcall(ffi.new, type_str, ...)
            if ok then return res end
            return nil
        end
        if type_str == "const char*" then
            return ...
        end
        local base, sz = type_str:match("^(.-)%[(%d+)%]$")
        if base and sz then
            sz = tonumber(sz)
            local creator = new_allocator[base] or make_vec_type(base)
            return creator[sz](...)
        else
            local creator = new_allocator[type_str] or make_vec_type(type_str)
            return creator(...)
        end
    end,
    __index = function(_, key)
        if key == nil then return nil end
        return make_vec_type(tostring(key))
    end
})

mimgui.new = new_allocator

local cachedRawColors = nil
local enums_Col = enums.Col

local staticColorsProxy = setmetatable({}, {
    __index = function(_, k)
        local colors = cachedRawColors
        if colors == nil then
            local rawStyle = ffi.C.igGetStyle()
            if rawStyle == nil or rawStyle == ffi.null then return nil end
            colors = rawStyle.Colors
            cachedRawColors = colors
        end
        local idx = (type(k) == "number") and k or enums_Col[k]
        if idx and idx >= 0 and idx < 64 then
            return colors[idx]
        end
        return nil
    end,
    __newindex = function(_, k, v)
        local colors = cachedRawColors
        if colors == nil then
            local rawStyle = ffi.C.igGetStyle()
            if rawStyle == nil or rawStyle == ffi.null then return end
            colors = rawStyle.Colors
            cachedRawColors = colors
        end
        local idx = (type(k) == "number") and k or enums_Col[k]
        if idx and idx >= 0 and idx < 64 then
            if type(v) == "number" then

                local a = bit.band(bit.rshift(v, 24), 0xFF) / 255.0
                local r = bit.band(bit.rshift(v, 16), 0xFF) / 255.0
                local g = bit.band(bit.rshift(v, 8), 0xFF) / 255.0
                local b = bit.band(v, 0xFF) / 255.0
                if a == 0 and v <= 0xFFFFFF then a = 1.0 end
                colors[idx].x = r
                colors[idx].y = g
                colors[idx].z = b
                colors[idx].w = a
            elseif type(v) == "cdata" or type(v) == "table" then
                local src = v
                if ffi.istype(imcolor_ct, v) then
                    src = v.Value
                else
                    local ok, val = pcall(function() return src.Value end)
                    if ok and val ~= nil then src = val end
                end
                colors[idx].x = tonumber(src.x or src[1] or src.r) or 0
                colors[idx].y = tonumber(src.y or src[2] or src.g) or 0
                colors[idx].z = tonumber(src.z or src[3] or src.b) or 0
                colors[idx].w = tonumber(src.w or src[4] or src.a) or 1
            end
        end
    end,
    __tostring = function() return "ImGuiStyleColors" end
})

local staticStyleProxy = setmetatable({
    Colors = staticColorsProxy,
}, {
    __index = function(_, k)
        if k == "Colors" then return staticColorsProxy end
        local rawStyle = ffi.C.igGetStyle()
        if rawStyle == nil or rawStyle == ffi.null then return nil end
        if k == "ScaleAllSizes" then
            return function(self_or_scale, maybe_scale)
                local s = (type(self_or_scale) == "number") and self_or_scale or maybe_scale
                if s then
                    ffi.C.ImGuiStyle_ScaleAllSizes(rawStyle, s)
                end
            end
        end
        local val = rawStyle[k]
        if type(val) == "cdata" then
            local ok, num = pcall(tonumber, val)
            if ok and num ~= nil then
                return num
            end
        end
        return val
    end,
    __newindex = function(_, k, v)
        if k == "Colors" then return end
        local rawStyle = ffi.C.igGetStyle()
        if rawStyle == nil or rawStyle == ffi.null then return end
        if type(v) == "table" then
            local ok = pcall(function()
                rawStyle[k].x = v.x or v[1] or 0
                rawStyle[k].y = v.y or v[2] or 0
            end)
            if not ok then rawStyle[k] = v end
        else
            rawStyle[k] = v
        end
    end
})

function mimgui.GetStyle()
    return staticStyleProxy
end

mimgui.ImGuiStyle = setmetatable({}, {
    __index = function(_, k)
        if k == "Colors" then
            local s = mimgui.GetStyle()
            return s and s.Colors
        end
    end
})

function mimgui.GetStyleColorVec4(idx)
    return ffi.C.igGetStyleColorVec4(idx)
end

function mimgui.GetColorVec4(idx)
    local col = ffi.C.igGetStyleColorVec4(idx)
    return col.x, col.y, col.z, col.w
end

function mimgui.Begin(name, p_open, flags)
    if type(p_open) == "number" and flags == nil then
        flags = p_open
        p_open = nil
    elseif type(p_open) == "boolean" then
        p_open = nil
    elseif type(p_open) ~= "cdata" then
        p_open = nil
    end

    local sname = tostring(name or "")
    if sname == "" then
        sname = "###unnamed_window"
    end

    return ffi.C.igBegin(sname, p_open, flags or 0)
end

function mimgui.End()
    return ffi.C.igEnd()
end

function mimgui.BeginChild(id, size, child_flags, window_flags)
    if size == nil then
        size = ImVec2(0, 0)
    elseif type(size) == "boolean" then
        window_flags = child_flags
        child_flags = size and 1 or 0
        size = ImVec2(0, 0)
    else
        size = to_vec2(size)
    end

    if type(child_flags) == "boolean" then
        child_flags = child_flags and 1 or 0
    elseif type(child_flags) == "number" and window_flags == nil then
        if bit.band(child_flags, bit.bnot(511)) ~= 0 or child_flags == 8 or child_flags == 16 or child_flags == 32 or child_flags == 64 then
            window_flags = child_flags
            child_flags = 0
        end
    end

    child_flags = child_flags or 0
    window_flags = window_flags or 0

    if type(id) == "number" then
        ffi.C.igBeginChild_ID(id, size, child_flags, window_flags)
    else
        local sid = type(id) == "string" and id or tostring(id or "")
        if sid == "" then
            sid = "###unnamed_child"
        end
        ffi.C.igBeginChild_Str(sid, size, child_flags, window_flags)
    end
    return true
end

function mimgui.EndChild()
    return ffi.C.igEndChild()
end

function mimgui.BeginGroup()
    return ffi.C.igBeginGroup()
end

function mimgui.EndGroup()
    return ffi.C.igEndGroup()
end

function mimgui.SetNextWindowPos(pos, cond, pivot)
    return ffi.C.igSetNextWindowPos(to_vec2(pos), cond or 0, to_vec2(pivot))
end

function mimgui.SetNextWindowSize(size, cond)
    return ffi.C.igSetNextWindowSize(to_vec2(size), cond or 0)
end

function mimgui.SetNextWindowContentSize(size)
    return ffi.C.igSetNextWindowContentSize(to_vec2(size))
end

function mimgui.SetNextWindowSizeConstraints(size_min, size_max, custom_callback, custom_callback_data)
    return ffi.C.igSetNextWindowSizeConstraints(to_vec2(size_min), to_vec2(size_max), custom_callback, custom_callback_data)
end

function mimgui.SetNextWindowFocus()
    return ffi.C.igSetNextWindowFocus()
end

function mimgui.SetNextWindowCollapsed(collapsed, cond)
    return ffi.C.igSetNextWindowCollapsed(collapsed or false, cond or 0)
end

function mimgui.SetNextWindowBgAlpha(alpha)
    return ffi.C.igSetNextWindowBgAlpha(alpha or 1.0)
end

function mimgui.SetCursorPos(pos)
    local ok, win = pcall(ffi.C.igGetCurrentWindowRead)
    if not ok or win == nil then return end
    return ffi.C.igSetCursorPos(to_vec2(pos))
end

function mimgui.SetCursorPosX(x)
    return ffi.C.igSetCursorPosX(x or 0.0)
end

function mimgui.SetCursorPosY(y)
    return ffi.C.igSetCursorPosY(y or 0.0)
end

function mimgui.GetCursorPosX()
    return ffi.C.igGetCursorPosX()
end

function mimgui.GetCursorPosY()
    return ffi.C.igGetCursorPosY()
end

function mimgui.SetCursorScreenPos(pos)
    return ffi.C.igSetCursorScreenPos(to_vec2(pos))
end

function mimgui.GetCursorPos()
    local p = ffi.C.igGetCursorPos()
    return ImVec2(p.x, p.y)
end

function mimgui.GetCursorScreenPos()
    local p = ffi.C.igGetCursorScreenPos()
    return ImVec2(p.x, p.y)
end

function mimgui.GetCursorStartPos()
    local p = ffi.C.igGetCursorStartPos()
    return ImVec2(p.x, p.y)
end

function mimgui.GetWindowPos()
    local p = ffi.C.igGetWindowPos()
    return ImVec2(p.x, p.y)
end

function mimgui.GetWindowSize()
    local p = ffi.C.igGetWindowSize()
    return ImVec2(p.x, p.y)
end

function mimgui.GetWindowWidth()
    return ffi.C.igGetWindowWidth()
end

function mimgui.GetWindowHeight()
    return ffi.C.igGetWindowHeight()
end

function mimgui.GetItemRectMin()
    local p = ffi.C.igGetItemRectMin()
    return ImVec2(p.x, p.y)
end

function mimgui.GetItemRectMax()
    local p = ffi.C.igGetItemRectMax()
    return ImVec2(p.x, p.y)
end

function mimgui.GetItemRectSize()
    local p = ffi.C.igGetItemRectSize()
    return ImVec2(p.x, p.y)
end

function mimgui.GetFontTexUvWhitePixel()
    local uv = ffi.C.igGetFontTexUvWhitePixel()
    return ImVec2(uv.x, uv.y)
end

function mimgui.GetMousePos()
    local p = ffi.C.igGetMousePos()
    if p.x < -1000 or p.x ~= p.x then
        local ok_io, io = pcall(ffi.C.igGetIO_Nil)
        if ok_io and io ~= nil and io ~= ffi.null then
            if io.MouseClickedPos[0].x >= 0 and io.MouseClickedPos[0].y >= 0 then
                return ImVec2(io.MouseClickedPos[0].x, io.MouseClickedPos[0].y)
            end
        end
    end
    return ImVec2(p.x, p.y)
end

function mimgui.IsItemHovered(flags)
    return ffi.C.igIsItemHovered(flags or 0)
end

function mimgui.IsItemClicked(mouse_button)
    return ffi.C.igIsItemClicked(mouse_button or 0)
end

function mimgui.IsItemActive()
    return ffi.C.igIsItemActive()
end

function mimgui.IsItemFocused()
    return ffi.C.igIsItemFocused()
end

function mimgui.IsItemVisible()
    return ffi.C.igIsItemVisible()
end

function mimgui.IsItemEdited()
    return ffi.C.igIsItemEdited()
end

function mimgui.IsItemActivated()
    return ffi.C.igIsItemActivated()
end

function mimgui.IsItemDeactivated()
    return ffi.C.igIsItemDeactivated()
end

function mimgui.IsItemDeactivatedAfterEdit()
    return ffi.C.igIsItemDeactivatedAfterEdit()
end

function mimgui.IsItemToggledOpen()
    return ffi.C.igIsItemToggledOpen()
end

function mimgui.IsAnyItemHovered()
    return ffi.C.igIsAnyItemHovered()
end

function mimgui.IsAnyItemActive()
    return ffi.C.igIsAnyItemActive()
end

function mimgui.IsAnyItemFocused()
    return ffi.C.igIsAnyItemFocused()
end

function mimgui.IsWindowHovered(flags)
    return ffi.C.igIsWindowHovered(flags or 0)
end

function mimgui.IsWindowFocused(flags)
    return ffi.C.igIsWindowFocused(flags or 0)
end

function mimgui.IsWindowAppearing()
    return ffi.C.igIsWindowAppearing()
end

function mimgui.IsWindowCollapsed()
    return ffi.C.igIsWindowCollapsed()
end

function mimgui.IsMouseDown(button)
    return ffi.C.igIsMouseDown_Nil(button or 0)
end

function mimgui.IsMouseClicked(button, repeat_click)
    return ffi.C.igIsMouseClicked_Bool(button or 0, repeat_click or false)
end

function mimgui.IsMouseReleased(button)
    return ffi.C.igIsMouseReleased_Nil(button or 0)
end

function mimgui.IsMouseDoubleClicked(button)
    return ffi.C.igIsMouseDoubleClicked_Nil(button or 0)
end

function mimgui.SameLine(offset_from_start_x, spacing)
    return ffi.C.igSameLine(offset_from_start_x or 0.0, spacing or -1.0)
end

function mimgui.Separator()
    return ffi.C.igSeparator()
end

function mimgui.Spacing()
    return ffi.C.igSpacing()
end

function mimgui.NewLine()
    return ffi.C.igNewLine()
end

function mimgui.Dummy(size)
    return ffi.C.igDummy(to_vec2(size))
end

function mimgui.ProgressBar(fraction, size_arg, overlay)
    return ffi.C.igProgressBar(fraction or 0.0, to_vec2(size_arg or {-1, 0}), overlay and tostring(overlay) or nil)
end

function mimgui.SetWindowFontScale(scale)
    local ok, win = pcall(ffi.C.igGetCurrentWindowRead)
    if ok and win ~= nil and win ~= ffi.null then
        pcall(function() win.FontWindowScale = tonumber(scale) or 1.0 end)
    end
end

function mimgui.PushItemWidth(item_width)
    return ffi.C.igPushItemWidth(item_width or 0.0)
end

function mimgui.PopItemWidth()
    return ffi.C.igPopItemWidth()
end

function mimgui.SetNextItemWidth(item_width)
    return ffi.C.igSetNextItemWidth(item_width or 0.0)
end

function mimgui.CalcItemWidth()
    return ffi.C.igCalcItemWidth()
end

function mimgui.ImBool(init_val)
    local v = ffi.new("bool[1]")
    if init_val ~= nil then v[0] = (init_val == true) end
    return v
end

function mimgui.ImInt(init_val)
    local v = ffi.new("int[1]")
    if init_val ~= nil then v[0] = tonumber(init_val) or 0 end
    return v
end

function mimgui.ImFloat(init_val)
    local v = ffi.new("float[1]")
    if init_val ~= nil then v[0] = tonumber(init_val) or 0.0 end
    return v
end

function mimgui.ImBuffer(str_or_size, size)
    local cap = 256
    local init_str = ""
    if type(str_or_size) == "number" then
        cap = str_or_size
    elseif type(str_or_size) == "string" then
        init_str = str_or_size
        cap = type(size) == "number" and size or math.max(256, #init_str + 1)
    end
    local buf = ffi.new("char[?]", cap)
    cdata_lengths[buf] = cap
    if #init_str > 0 then
        local copy_len = math.min(#init_str, cap - 1)
        ffi.copy(buf, init_str, copy_len)
        buf[copy_len] = 0
    else
        buf[0] = 0
    end
    return buf
end

function mimgui.Indent(indent_w)
    return ffi.C.igIndent(indent_w or 0.0)
end

function mimgui.Unindent(indent_w)
    return ffi.C.igUnindent(indent_w or 0.0)
end

function mimgui.PushFont(font, size)
    if font == nil or font == ffi.null then
        return ffi.C.igPushFont(nil, size or 0.0)
    end
    local ok = pcall(function() ffi.C.neom_mimgui_push_font(font, size or 0.0) end)
    if not ok then
        pcall(function() ffi.C.igPushFont(font, size or 0.0) end)
    end
end

function mimgui.PopFont()
    local ok = pcall(function() ffi.C.neom_mimgui_pop_font() end)
    if not ok then
        pcall(function() ffi.C.igPopFont() end)
    end
end

function mimgui.CalcTextSize(text, text_end, hide_text_after_double_hash, wrap_width)
    if text == nil then return ImVec2(0, 0) end
    text = tostring(text)
    if text == "" then return ImVec2(0, 0) end
    if type(text_end) == "boolean" then
        hide_text_after_double_hash = text_end
        text_end = nil
    elseif type(text_end) == "number" then
        wrap_width = text_end
        text_end = nil
    end
    local ok, v = pcall(function()
        return ffi.C.igCalcTextSize(text, text_end or ffi.null, hide_text_after_double_hash or false, wrap_width or -1.0)
    end)
    if ok and v ~= nil then
        return ImVec2(v.x, v.y)
    end
    return ImVec2(0, 0)
end

function mimgui.GetFrameRate()
    local ok, io = pcall(mimgui.GetIO)
    if ok and io ~= nil and io ~= ffi.null then
        return io.Framerate
    end
    return 60.0
end

function mimgui.PushStyleColor(idx, col)
    if type(idx) == "string" then
        idx = enums.Col[idx] or 0
    end
    idx = idx or 0
    return ffi.C.igPushStyleColor_Vec4(idx, to_vec4(col))
end

function mimgui.PopStyleColor(count)
    local ok = pcall(function() ffi.C.neom_mimgui_pop_style_color(count or 1) end)
    if not ok then
        return ffi.C.igPopStyleColor(count or 1)
    end
end

function mimgui.PushStyleVar(idx, val, val_y)
    if val_y ~= nil then
        return ffi.C.igPushStyleVar_Vec2(idx, ImVec2(val, val_y))
    elseif type(val) == "table" or ffi.istype("ImVec2", val) then
        return ffi.C.igPushStyleVar_Vec2(idx, to_vec2(val))
    else
        return ffi.C.igPushStyleVar_Float(idx, val)
    end
end

function mimgui.PopStyleVar(count)
    local ok = pcall(function() ffi.C.neom_mimgui_pop_style_var(count or 1) end)
    if not ok then
        return ffi.C.igPopStyleVar(count or 1)
    end
end

local function get_buffer_capacity(buf, default_cap)
    if buf == nil then return default_cap or 256 end
    local cap = cdata_lengths[buf]
    if cap and cap > 0 then return cap end
    local ok, sz = pcall(ffi.sizeof, buf)
    if ok and sz and sz > 8 then return sz end
    return default_cap or 256
end

function mimgui.InputText(label, buf, buf_size, flags, cb, ud)
    buf_size = (buf_size and buf_size > 0) and buf_size or get_buffer_capacity(buf, 256)
    return ffi.C.igInputText(label, buf, buf_size, flags or 0, cb, ud)
end

function mimgui.InputTextMultiline(label, buf, buf_size, size, flags, cb, ud)
    buf_size = (buf_size and buf_size > 0) and buf_size or get_buffer_capacity(buf, 256)
    return ffi.C.igInputTextMultiline(label, buf, buf_size, to_vec2(size), flags or 0, cb, ud)
end

function mimgui.InputTextWithHint(label, hint, buf, buf_size, flags, cb, ud)
    buf_size = (buf_size and buf_size > 0) and buf_size or get_buffer_capacity(buf, 256)
    return ffi.C.igInputTextWithHint(label, hint, buf, buf_size, flags or 0, cb, ud)
end

function mimgui.InputInt(label, v, step, step_fast, flags)
    return ffi.C.igInputInt(label, v, step or 1, step_fast or 100, flags or 0)
end

function mimgui.InputFloat(label, v, step, step_fast, format, flags)
    return ffi.C.igInputFloat(label, v, step or 0.0, step_fast or 0.0, format or "%.3f", flags or 0)
end

function mimgui.InputDouble(label, v, step, step_fast, format, flags)
    return ffi.C.igInputDouble(label, v, step or 0.0, step_fast or 0.0, format or "%.6f", flags or 0)
end

function mimgui.SliderInt(label, v, v_min, v_max, format, flags)
    return ffi.C.igSliderInt(label, v, v_min, v_max, format or "%d", flags or 0)
end

function mimgui.SliderFloat(label, v, v_min, v_max, format, flags)
    return ffi.C.igSliderFloat(label, v, v_min, v_max, format or "%.3f", flags or 0)
end

function mimgui.DragInt(label, v, v_speed, v_min, v_max, format, flags)
    return ffi.C.igDragInt(label, v, v_speed or 1.0, v_min or 0, v_max or 0, format or "%d", flags or 0)
end

function mimgui.DragFloat(label, v, v_speed, v_min, v_max, format, flags)
    return ffi.C.igDragFloat(label, v, v_speed or 1.0, v_min or 0.0, v_max or 0.0, format or "%.3f", flags or 0)
end

function mimgui.Button(label, size)
    return ffi.C.igButton(tostring(label or ""), to_vec2(size))
end

function mimgui.InvisibleButton(id, size, flags)
    return ffi.C.igInvisibleButton(id, to_vec2(size), flags or 0)
end

function mimgui.Checkbox(label, v)
    if type(v) == "cdata" then
        return ffi.C.igCheckbox(label, v)
    elseif type(v) == "table" then
        local b = ffi.new("bool[1]", v[1] or false)
        local changed = ffi.C.igCheckbox(label, b)
        v[1] = b[0]
        return changed, b[0]
    elseif type(v) == "boolean" then
        local b = ffi.new("bool[1]", v)
        local changed = ffi.C.igCheckbox(label, b)
        return changed, b[0]
    end
    return ffi.C.igCheckbox(label, v)
end

function mimgui.RadioButton(label, arg2, arg3)
    if arg3 ~= nil then
        if type(arg2) == "cdata" then
            return ffi.C.igRadioButton_IntPtr(label, arg2, arg3)
        elseif type(arg2) == "table" then
            local i = ffi.new("int[1]", arg2[1] or 0)
            local res = ffi.C.igRadioButton_IntPtr(label, i, arg3)
            arg2[1] = i[0]
            return res
        end
    end
    return ffi.C.igRadioButton_Bool(label, arg2 == true)
end
mimgui.RadioButtonIntPtr = ffi.C.igRadioButton_IntPtr
mimgui.RadioButtonBool = ffi.C.igRadioButton_Bool
mimgui.RadioButton_IntPtr = ffi.C.igRadioButton_IntPtr
mimgui.RadioButton_Bool = ffi.C.igRadioButton_Bool

function mimgui.ComboStr(label, current_item, items, popup_max_height_in_items)
    local pItem = type(current_item) == "cdata" and current_item or ffi.new("int[1]", current_item or 0)
    local res = ffi.C.igCombo_Str(label, pItem, items, popup_max_height_in_items or -1)
    if type(current_item) == "table" then current_item[1] = pItem[0] end
    return res
end
mimgui.Combo_Str = mimgui.ComboStr

function mimgui.ComboStr_arr(label, current_item, items, items_count, popup_max_height_in_items)
    return mimgui.Combo(label, current_item, items, items_count, popup_max_height_in_items)
end
mimgui.Combo_Str_arr = mimgui.ComboStr_arr
mimgui.ComboStrArr = mimgui.ComboStr_arr

function mimgui.Combo(label, current_item, items, items_count, popup_max_height_in_items)
    if type(items) == "table" then
        local count = items_count or #items
        local arr = ffi.new("const char*[?]", count)
        for i = 0, count - 1 do
            arr[i] = tostring(items[i + 1])
        end
        local pItem = type(current_item) == "cdata" and current_item or ffi.new("int[1]", current_item or 0)
        local res = ffi.C.igCombo_Str_arr(label, pItem, arr, count, popup_max_height_in_items or -1)
        if type(current_item) == "table" then current_item[1] = pItem[0] end
        return res
    elseif type(items) == "string" then
        local max_h = popup_max_height_in_items or (type(items_count) == "number" and items_count) or -1
        local pItem = type(current_item) == "cdata" and current_item or ffi.new("int[1]", current_item or 0)
        local res = ffi.C.igCombo_Str(label, pItem, items, max_h)
        if type(current_item) == "table" then current_item[1] = pItem[0] end
        return res
    end
    return ffi.C.igCombo_Str_arr(label, current_item, items, items_count or 0, popup_max_height_in_items or -1)
end

function mimgui.ListBoxStr(label, current_item, items, items_count, height_in_items)
    return mimgui.ListBox(label, current_item, items, items_count, height_in_items)
end
mimgui.ListBox_Str = mimgui.ListBoxStr

function mimgui.ListBoxStr_arr(label, current_item, items, items_count, height_in_items)
    return mimgui.ListBox(label, current_item, items, items_count, height_in_items)
end
mimgui.ListBox_Str_arr = mimgui.ListBoxStr_arr

function mimgui.ListBox(label, current_item, items, items_count, height_in_items)
    if type(items) == "table" then
        local count = items_count or #items
        local arr = ffi.new("const char*[?]", count)
        for i = 0, count - 1 do
            arr[i] = tostring(items[i + 1])
        end
        local pItem = type(current_item) == "cdata" and current_item or ffi.new("int[1]", current_item or 0)
        local res = ffi.C.igListBox_Str_arr(label, pItem, arr, count, height_in_items or -1)
        if type(current_item) == "table" then current_item[1] = pItem[0] end
        return res
    end
    return ffi.C.igListBox_Str_arr(label, current_item, items, items_count or 0, height_in_items or -1)
end

function mimgui.ListBoxHeader(label, size_or_count, height_in_items)
    if type(size_or_count) == "number" then
        local lh = ffi.C.igGetTextLineHeightWithSpacing()
        local h = (height_in_items or -1) > 0 and ((height_in_items) * lh) or 0
        return ffi.C.igBeginListBox(label, to_vec2({0, h}))
    end
    return ffi.C.igBeginListBox(label, to_vec2(size_or_count))
end
mimgui.ListBoxHeaderVec2 = mimgui.ListBoxHeader
mimgui.ListBoxHeader_Vec2 = mimgui.ListBoxHeader
mimgui.ListBoxHeader2 = mimgui.ListBoxHeader

function mimgui.ListBoxFooter()
    return ffi.C.igEndListBox()
end

function mimgui.Selectable(label, selected, flags, size)
    if type(selected) == "cdata" then
        return ffi.C.igSelectable_BoolPtr(label, selected, flags or 0, to_vec2(size))
    end
    return ffi.C.igSelectable_Bool(label, selected == true, flags or 0, to_vec2(size))
end

function mimgui.ColorEdit3(label, col, flags)
    if type(col) == "cdata" and ffi.istype(ImVec4, col) then
        return ffi.C.igColorEdit3(label, ffi.cast("float*", col), flags or 0)
    end
    return ffi.C.igColorEdit3(label, col, flags or 0)
end

function mimgui.ColorEdit4(label, col, flags)
    if type(col) == "cdata" and ffi.istype(ImVec4, col) then
        return ffi.C.igColorEdit4(label, ffi.cast("float*", col), flags or 0)
    end
    return ffi.C.igColorEdit4(label, col, flags or 0)
end

function mimgui.ColorPicker3(label, col, flags)
    return ffi.C.igColorPicker3(label, col, flags or 0)
end

function mimgui.ColorPicker4(label, col, flags, ref_col)
    return ffi.C.igColorPicker4(label, col, flags or 0, ref_col)
end

function mimgui.PushID(id)
    if type(id) == "number" then
        return ffi.C.igPushID_Int(id)
    elseif type(id) == "string" then
        return ffi.C.igPushID_Str(id)
    elseif type(id) == "cdata" or type(id) == "userdata" then
        return ffi.C.igPushID_Ptr(id)
    else
        return ffi.C.igPushID_Str(tostring(id))
    end
end

function mimgui.GetID(id)
    if type(id) == "number" then
        return ffi.C.igGetID_Int(id)
    elseif type(id) == "string" then
        return ffi.C.igGetID_Str(id)
    elseif type(id) == "cdata" or type(id) == "userdata" then
        return ffi.C.igGetID_Ptr(id)
    else
        return ffi.C.igGetID_Str(tostring(id))
    end
end

function mimgui.GetIDStr(id)
    return ffi.C.igGetID_Str(tostring(id))
end

function mimgui.GetIDInt(id)
    return ffi.C.igGetID_Int(tonumber(id) or 0)
end

function mimgui.GetIDPtr(ptr)
    return ffi.C.igGetID_Ptr(ptr)
end

function mimgui.CollapsingHeader(label, arg2, arg3)
    if type(arg2) == "cdata" then
        return ffi.C.igCollapsingHeader_BoolPtr(label, arg2, arg3 or 0)
    end
    return ffi.C.igCollapsingHeader_TreeNodeFlags(label, arg2 or 0)
end

function mimgui.TreeNode(label, ...)
    if select("#", ...) == 0 then
        return ffi.C.igTreeNode_Str(label)
    else
        return ffi.C.igTreeNode_StrStr(label, "%s", string.format(...))
    end
end

function mimgui.TreeNodeEx(label, flags, ...)
    flags = flags or 0
    if select("#", ...) == 0 then
        return ffi.C.igTreeNodeEx_Str(label, flags)
    else
        return ffi.C.igTreeNodeEx_StrStr(label, flags, "%s", string.format(...))
    end
end

mimgui.TreeNodeStr = mimgui.TreeNode

function mimgui.TreePop()
    return ffi.C.igTreePop()
end

function mimgui.Image(tex, size, uv0, uv1, tint_col, border_col)
    local ref = to_tex_ref(tex)
    local u0 = to_vec2(uv0 or {0, 0})
    local u1 = to_vec2(uv1 or {1, 1})
    if tint_col or border_col then
        return ffi.C.igImageWithBg(ref, to_vec2(size), u0, u1, to_vec4(border_col or {0, 0, 0, 0}), to_vec4(tint_col or {1, 1, 1, 1}))
    else
        return ffi.C.igImage(ref, to_vec2(size), u0, u1)
    end
end

function mimgui.ImageButton(id, tex, size, uv0, uv1, bg_col, tint_col)
    local ref = to_tex_ref(tex)
    local u0 = to_vec2(uv0 or {0, 0})
    local u1 = to_vec2(uv1 or {1, 1})
    local bg = to_vec4(bg_col or {0, 0, 0, 0})
    local tint = to_vec4(tint_col or {1, 1, 1, 1})
    return ffi.C.igImageButton(id, ref, to_vec2(size), u0, u1, bg, tint)
end

function mimgui.OpenPopup(str_id, flags)
    if type(str_id) == "number" then
        return ffi.C.igOpenPopup_ID(str_id, flags or 0)
    else
        return ffi.C.igOpenPopup_Str(tostring(str_id), flags or 0)
    end
end

function mimgui.CloseCurrentPopup()
    return ffi.C.igCloseCurrentPopup()
end

function mimgui.BeginPopup(str_id, flags)
    return ffi.C.igBeginPopup(tostring(str_id), flags or 0)
end

function mimgui.BeginPopupModal(name, p_open, flags)
    if type(p_open) == "number" and flags == nil then
        flags = p_open
        p_open = nil
    elseif type(p_open) == "boolean" then
        p_open = nil
    elseif type(p_open) ~= "cdata" then
        p_open = nil
    end

    return ffi.C.igBeginPopupModal(tostring(name), p_open, flags or 0)
end

function mimgui.BeginPopupContextItem(str_id, popup_flags)
    return ffi.C.igBeginPopupContextItem(str_id and tostring(str_id) or nil, popup_flags or 1)
end

function mimgui.BeginPopupContextWindow(str_id, popup_flags)
    return ffi.C.igBeginPopupContextWindow(str_id and tostring(str_id) or nil, popup_flags or 1)
end

function mimgui.BeginPopupContextVoid(str_id, popup_flags)
    return ffi.C.igBeginPopupContextVoid(str_id and tostring(str_id) or nil, popup_flags or 1)
end

function mimgui.EndPopup()
    return ffi.C.igEndPopup()
end

function mimgui.IsPopupOpen(str_id, flags)
    if type(str_id) == "number" then
        return ffi.C.igIsPopupOpen_ID(str_id, flags or 0)
    else
        return ffi.C.igIsPopupOpen_Str(tostring(str_id), flags or 0)
    end
end

function mimgui.BeginCombo(label, preview_value, flags)
    return ffi.C.igBeginCombo(tostring(label), preview_value and tostring(preview_value) or nil, flags or 0)
end

function mimgui.EndCombo()
    return ffi.C.igEndCombo()
end

function mimgui.MenuItem(label, shortcut, selected, enabled)
    if enabled == nil then enabled = true end
    if type(selected) == "boolean" or selected == nil then
        return ffi.C.igMenuItem_Bool(label, shortcut or nil, selected or false, enabled)
    else
        return ffi.C.igMenuItem_BoolPtr(label, shortcut or nil, selected, enabled)
    end
end

function mimgui.BeginMainMenuBar()
    return ffi.C.igBeginMainMenuBar()
end

function mimgui.EndMainMenuBar()
    return ffi.C.igEndMainMenuBar()
end

function mimgui.BeginMenuBar()
    return ffi.C.igBeginMenuBar()
end

function mimgui.EndMenuBar()
    return ffi.C.igEndMenuBar()
end

function mimgui.BeginMenu(label, enabled)
    if enabled == nil then enabled = true end
    return ffi.C.igBeginMenu(tostring(label), enabled)
end

function mimgui.EndMenu()
    return ffi.C.igEndMenu()
end

function mimgui.BeginTooltip()
    return ffi.C.igBeginTooltip()
end

function mimgui.EndTooltip()
    return ffi.C.igEndTooltip()
end

function mimgui.SetTooltip(...)
    if select("#", ...) == 1 then
        return ffi.C.igSetTooltip("%s", tostring((...)))
    else
        return ffi.C.igSetTooltip(string.format(...))
    end
end

function mimgui.GetIO()
    return ffi.C.igGetIO_Nil()
end

function mimgui.ShowDemoWindow(p_open)
    return ffi.C.igShowDemoWindow(p_open)
end
mimgui.ShowTestWindow = mimgui.ShowDemoWindow

function mimgui.GetContentRegionAvail()
    local v = ffi.C.igGetContentRegionAvail()
    return ImVec2(v.x, v.y)
end

function mimgui.GetWindowContentRegionMin()
    return ImVec2(0, 0)
end

function mimgui.GetWindowContentRegionMax()
    local size = mimgui.GetWindowSize()
    return ImVec2(size.x, size.y)
end

function mimgui.GetWindowContentRegionWidth()
    return mimgui.GetWindowWidth()
end

function mimgui.BeginTable(str_id, columns, flags, outer_size, inner_width)
    return ffi.C.igBeginTable(str_id, columns, flags or 0, to_vec2(outer_size), inner_width or 0.0)
end

function mimgui.EndTable()
    return ffi.C.igEndTable()
end

function mimgui.TableSetupColumn(label, flags, init_width_or_weight, user_data)
    return ffi.C.igTableSetupColumn(label, flags or 0, init_width_or_weight or 0.0, user_data or 0)
end

function mimgui.TableNextRow(row_flags, min_row_height)
    return ffi.C.igTableNextRow(row_flags or 0, min_row_height or 0.0)
end

function mimgui.BeginTabBar(str_id, flags)
    return ffi.C.igBeginTabBar(tostring(str_id), flags or 0)
end

function mimgui.EndTabBar()
    return ffi.C.igEndTabBar()
end

function mimgui.BeginTabItem(label, p_open, flags)
    if type(p_open) == "number" and flags == nil then
        flags = p_open
        p_open = nil
    elseif type(p_open) == "boolean" then
        if not p_open then return false end
        p_open = nil
    elseif type(p_open) ~= "cdata" then
        p_open = nil
    end
    return ffi.C.igBeginTabItem(tostring(label), p_open, flags or 0)
end

function mimgui.EndTabItem()
    return ffi.C.igEndTabItem()
end

function mimgui.TabItemButton(label, flags)
    return ffi.C.igTabItemButton(tostring(label), flags or 0)
end

function mimgui.SetTabItemClosed(tab_or_docked_window_label)
    return ffi.C.igSetTabItemClosed(tostring(tab_or_docked_window_label))
end

function mimgui.Columns(count, id, border)
    if border == nil then border = true end
    return ffi.C.igColumns(count or 1, id and tostring(id) or nil, border)
end

function mimgui.NextColumn()
    return ffi.C.igNextColumn()
end

function mimgui.GetColorU32(idx_or_col, alpha_mul)
    if type(idx_or_col) == "number" then
        if idx_or_col >= 0 and idx_or_col < (enums.Col and enums.Col.COUNT or 55) then
            local r = ffi.C.igGetColorU32_Col(idx_or_col, alpha_mul or 1.0)
            return r
        else
            local r = ffi.C.igGetColorU32_U32(idx_or_col)
            return r
        end
    elseif type(idx_or_col) == "cdata" or type(idx_or_col) == "table" then
        local r = ffi.C.igGetColorU32_Vec4(to_vec4(idx_or_col))
        return r
    end
    return 0xFFFFFFFF
end
mimgui.GetColorU32_Col = ffi.C.igGetColorU32_Col
mimgui.GetColorU32_U32 = ffi.C.igGetColorU32_U32

function mimgui.GetContentRegionMax()
    return mimgui.GetWindowContentRegionMax()
end

function mimgui.GetVersion()
    return ffi.string(ffi.C.igGetVersion())
end

function mimgui.TreeAdvanceToLabelPos()
    local ok, spacing = pcall(ffi.C.igGetTreeNodeToLabelSpacing)
    if ok then
        mimgui.SetCursorPosX(mimgui.GetCursorPosX() + spacing)
    end
end

function mimgui.SetItemAllowOverlap()
    pcall(ffi.C.igSetNextItemAllowOverlap)
end

function mimgui.GetForegroundDrawList(w)
    if w then return ffi.C.igGetForegroundDrawList_ViewportPtr(w) end
    return ffi.C.igGetForegroundDrawList_Nil()
end

function mimgui.GetBackgroundDrawList(w)
    if w then return ffi.C.igGetBackgroundDrawList(w) end
    return ffi.C.igGetBackgroundDrawList_Nil()
end

function mimgui.GetOverlayDrawList()
    return ffi.C.igGetForegroundDrawList_Nil()
end

function mimgui.GetWindowDrawList()
    return ffi.C.igGetWindowDrawList()
end

function mimgui.CreateTextureFromFile(filename)
    return ffi.C.neom_mimgui_create_texture_from_file(filename)
end

function mimgui.CreateTextureFromMemory(data, size)
    if data == nil then return 0 end
    local ptr = data
    if type(data) == "number" then
        ptr = ffi.cast("const unsigned char*", ffi.cast("uintptr_t", data))
    elseif type(data) == "string" then
        size = size or #data
        ptr = ffi.cast("const unsigned char*", data)
    elseif type(data) == "cdata" then
        ptr = ffi.cast("const unsigned char*", data)
    end
    size = size or 0
    return ffi.C.neom_mimgui_create_texture_from_memory(ptr, size)
end

mimgui.CreateTextureFromFileInMemory = mimgui.CreateTextureFromMemory

function mimgui.ReleaseTexture(texture)
    if not texture then return end
    if type(texture) == "number" then
        ffi.C.neom_mimgui_release_texture(texture)
    elseif type(texture) == "cdata" then
        local ok, val = pcall(function() return tonumber(ffi.cast("uintptr_t", texture)) end)
        if ok and val then
            ffi.C.neom_mimgui_release_texture(val)
        else
            ffi.C.neom_mimgui_release_texture(texture)
        end
    end
end

function mimgui.SwitchContext()
    return ffi.C.neom_mimgui_switch_context(script_name)
end

function mimgui.GetDpiScale()
    local ok, scale = pcall(function() return ffi.C.neom_mimgui_get_dpi_scale() end)
    if ok and scale and scale > 0 then return tonumber(scale) end
    return 1.0
end

local g_dpiScalingMode = 1
function mimgui.GetDpiScalingMode()
    return g_dpiScalingMode
end

function mimgui.SetDpiScalingMode(mode)
    g_dpiScalingMode = mode
end

if not _G.MONET_DPI_SCALE then
    _G.MONET_DPI_SCALE = mimgui.GetDpiScale()
end
if not _G.MONET_VERSION then
    _G.MONET_VERSION = "2.0.0"
end

function mimgui.GetRenderer()
    return "OpenGL3"
end

function mimgui.InvalidateFontsTexture()
    pcall(function() ffi.C.neom_mimgui_invalidate_fonts_texture() end)
end

function mimgui.CreateFontsTexture()
    return true
end

function mimgui.ImGlyphRanges(values)
    local count = type(values) == "table" and #values or 0
    local arr = ffi.new("ImWchar[?]", count + 1)
    if type(values) == "table" then
        for i = 1, count do
            arr[i - 1] = values[i]
        end
    end
    arr[count] = 0
    return arr
end

if not _G.getScreenResolution then
    _G.getScreenResolution = function()
        local vp = ffi.C.igGetMainViewport()
        if vp ~= nil and vp.Size.x > 0 and vp.Size.y > 0 then
            return vp.Size.x, vp.Size.y
        end
        local ok_io, io = pcall(ffi.C.igGetIO_Nil)
        if ok_io and io ~= nil and io ~= ffi.null and io.DisplaySize.x > 0 and io.DisplaySize.y > 0 then
            return io.DisplaySize.x, io.DisplaySize.y
        end
        return 1920, 1080
    end
end

local function get_io_fonts()
    local io = ffi.C.igGetIO_Nil()
    return io and io.Fonts or nil
end

function mimgui.GetGlyphRangesDefault()
    local fonts = get_io_fonts()
    return fonts and ffi.C.ImFontAtlas_GetGlyphRangesDefault(fonts) or nil
end

function mimgui.GetGlyphRangesKorean()
    local fonts = get_io_fonts()
    return fonts and ffi.C.ImFontAtlas_GetGlyphRangesKorean(fonts) or nil
end

function mimgui.GetGlyphRangesJapanese()
    local fonts = get_io_fonts()
    return fonts and ffi.C.ImFontAtlas_GetGlyphRangesJapanese(fonts) or nil
end

function mimgui.GetGlyphRangesChineseFull()
    local fonts = get_io_fonts()
    return fonts and ffi.C.ImFontAtlas_GetGlyphRangesChineseFull(fonts) or nil
end

function mimgui.GetGlyphRangesChineseSimplifiedCommon()
    local fonts = get_io_fonts()
    return fonts and ffi.C.ImFontAtlas_GetGlyphRangesChineseSimplifiedCommon(fonts) or nil
end

function mimgui.GetGlyphRangesCyrillic()
    local fonts = get_io_fonts()
    return fonts and ffi.C.ImFontAtlas_GetGlyphRangesCyrillic(fonts) or nil
end

function mimgui.GetGlyphRangesThai()
    local fonts = get_io_fonts()
    return fonts and ffi.C.ImFontAtlas_GetGlyphRangesThai(fonts) or nil
end

function mimgui.GetGlyphRangesGreek()
    local fonts = get_io_fonts()
    return fonts and ffi.C.ImFontAtlas_GetGlyphRangesGreek(fonts) or nil
end

function mimgui.GetGlyphRangesVietnamese()
    local fonts = get_io_fonts()
    return fonts and ffi.C.ImFontAtlas_GetGlyphRangesVietnamese(fonts) or nil
end

local function Link(text, col_normal, col_hovered, underline)
    if not text or text == "" then return false end
    local style = ffi.C.igGetStyle()
    local c_norm = col_normal or style.Colors[enums.Col.TextDisabled]
    local c_hov = col_hovered or style.Colors[enums.Col.Text]
    if type(c_norm) == "number" and c_norm >= 0 and c_norm < 64 then
        c_norm = style.Colors[c_norm]
    end
    if type(c_hov) == "number" and c_hov >= 0 and c_hov < 64 then
        c_hov = style.Colors[c_hov]
    end
    c_norm = to_vec4(c_norm)
    c_hov = to_vec4(c_hov)
    local size = mimgui.CalcTextSize(text)
    local pos = ffi.C.igGetCursorScreenPos()
    ffi.C.igDummy(size)
    local hovered = ffi.C.igIsItemHovered(0)
    local clicked = hovered and ffi.C.igIsItemClicked(0)
    local final_col = hovered and c_hov or c_norm
    local u32_col = ffi.C.igColorConvertFloat4ToU32(final_col)
    local dl = ffi.C.igGetWindowDrawList()
    ffi.C.ImDrawList_AddText_Vec2(dl, pos, u32_col, text, nil)
    local do_underline = (hovered and underline ~= false) or (underline == true)
    if do_underline then
        local p1 = ffi.new("ImVec2", pos.x, pos.y + size.y)
        local p2 = ffi.new("ImVec2", pos.x + size.x, pos.y + size.y)
        ffi.C.ImDrawList_AddLine(dl, p1, p2, u32_col, 1.0)
    end
    return clicked
end

mimgui.Link = Link

local function has_current_window()
    local ok, win = pcall(ffi.C.igGetCurrentWindowRead)
    return ok and win ~= nil and win ~= ffi.null
end

function mimgui.PushStyleVarVec2(idx, vec)
    return ffi.C.igPushStyleVar_Vec2(idx, to_vec2(vec))
end

function mimgui.PushStyleVarFloat(idx, val)
    return ffi.C.igPushStyleVar_Float(idx, val)
end

function mimgui.GetColumnWidth(column_index)
    if not has_current_window() then return 0.0 end
    return ffi.C.igGetColumnWidth(column_index or -1)
end

function mimgui.GetColumnOffset(column_index)
    if not has_current_window() then return 0.0 end
    return ffi.C.igGetColumnOffset(column_index or -1)
end

function mimgui.SetColumnWidth(column_index, width)
    if not has_current_window() then return end
    if width == nil and type(column_index) == "number" then
        return ffi.C.igSetColumnWidth(-1, column_index)
    end
    return ffi.C.igSetColumnWidth(column_index or -1, width or 0.0)
end

function mimgui.SetColumnOffset(column_index, offset_x)
    if not has_current_window() then return end
    if offset_x == nil and type(column_index) == "number" then
        return ffi.C.igSetColumnOffset(-1, column_index)
    end
    return ffi.C.igSetColumnOffset(column_index or -1, offset_x or 0.0)
end

function mimgui.GetColumnsCount()
    if not has_current_window() then return 1 end
    return ffi.C.igGetColumnsCount()
end

function mimgui.GetColumnIndex()
    if not has_current_window() then return 0 end
    return ffi.C.igGetColumnIndex()
end

function mimgui.SetWindowPos(pos, cond)
    return ffi.C.igSetWindowPos_Vec2(to_vec2(pos), cond or 0)
end
mimgui.SetWindowPosVec2 = mimgui.SetWindowPos

function mimgui.SetWindowSize(size, cond)
    return ffi.C.igSetWindowSize_Vec2(to_vec2(size), cond or 0)
end
mimgui.SetWindowSizeVec2 = mimgui.SetWindowSize

mimgui.SetNextWindowPosVec2 = mimgui.SetNextWindowPos
mimgui.SetNextWindowSizeVec2 = mimgui.SetNextWindowSize

function mimgui.GetColorU32Vec4(col)
    return ffi.C.igGetColorU32_Vec4(to_vec4(col))
end
mimgui.GetColorU32_Vec4 = mimgui.GetColorU32Vec4

mimgui.ImVec = mimgui.ImVec2

function mimgui.InfinitySpinner(label, radius, thickness, color, bg_color)
    local r = radius or 20
    local size = to_vec2({r * 2, r * 2})
    ffi.C.igDummy(size)
    local dl = ffi.C.igGetWindowDrawList()
    if dl ~= nil and dl ~= ffi.null then
        local pos = ffi.C.igGetItemRectMin()
        local center = to_vec2({pos.x + r, pos.y + r})
        local time = os.clock() * 4.0
        local c = type(color) == "table" and mimgui.GetColorU32Vec4(color) or 0xFFFFFFFF
        ffi.C.ImDrawList_PathClear(dl)
        ffi.C.ImDrawList_PathArcTo(dl, center, r * 0.8, time, time + 4.5, 24)
        ffi.C.ImDrawList_PathStroke(dl, c, 0, thickness or 3.0)
    end
end

function mimgui.GetContentRegionAvailWidth()
    if not has_current_window() then return 0.0 end
    return ffi.C.igGetContentRegionAvail().x
end

function mimgui.GetWindowContentRegionWidth()
    if not has_current_window() then return 0.0 end
    local ok, avail = pcall(ffi.C.igGetContentRegionAvail)
    if ok and avail ~= nil then
        local ok2, curX = pcall(ffi.C.igGetCursorPosX)
        local ok3, padX = pcall(function() return ffi.C.igGetStyle().WindowPadding.x end)
        if ok2 and ok3 then
            return avail.x + curX - padX
        end
        return avail.x
    end
    local ok_w, w = pcall(ffi.C.igGetWindowWidth)
    local ok_s, style = pcall(ffi.C.igGetStyle)
    if ok_w and ok_s and style ~= nil then
        return w - style.WindowPadding.x * 2
    end
    return ok_w and w or 0
end

function mimgui.GetTextLineHeightWithSpacing()
    return ffi.C.igGetTextLineHeightWithSpacing()
end

function mimgui.GetFrameHeightWithSpacing()
    return ffi.C.igGetFrameHeightWithSpacing()
end

function mimgui.CenterText(text)
    if not has_current_window() then return end
    text = tostring(text or "")
    local width = ffi.C.igGetWindowWidth()
    local calc = mimgui.CalcTextSize(text)
    local style = ffi.C.igGetStyle()
    local x = (width - calc.x) / 2
    if style and x < style.WindowPadding.x then
        x = style.WindowPadding.x
    end
    ffi.C.igSetCursorPosX(x)
    ffi.C.igTextUnformatted(text, nil)
end

function mimgui.CenterTextDisabled(text)
    if not has_current_window() then return end
    text = tostring(text or "")
    local width = ffi.C.igGetWindowWidth()
    local calc = mimgui.CalcTextSize(text)
    local style = ffi.C.igGetStyle()
    local x = (width - calc.x) / 2
    if style and x < style.WindowPadding.x then
        x = style.WindowPadding.x
    end
    ffi.C.igSetCursorPosX(x)
    ffi.C.igTextDisabled("%s", text)
end

function mimgui.CenterColorText(arg1, arg2)
    if not has_current_window() then return end
    local col, text
    if type(arg1) == "string" or (type(arg2) == "cdata" or type(arg2) == "number" or (type(arg2) == "table" and arg2.x)) then
        text, col = arg1, arg2
    else
        col, text = arg1, arg2
    end
    text = tostring(text or "")
    local width = ffi.C.igGetWindowWidth()
    local calc = mimgui.CalcTextSize(text)
    local style = ffi.C.igGetStyle()
    local x = (width - calc.x) / 2
    if style and x < style.WindowPadding.x then
        x = style.WindowPadding.x
    end
    ffi.C.igSetCursorPosX(x)
    ffi.C.igTextColored(to_vec4(col), "%s", text)
end
mimgui.CenterColoredText = mimgui.CenterColorText

function mimgui.CenterColumnText(text)
    if not has_current_window() then return end
    text = tostring(text or "")
    local width = mimgui.GetColumnWidth()
    local calc = mimgui.CalcTextSize(text)
    mimgui.SetCursorPosX(mimgui.GetColumnOffset() + (width - calc.x) / 2)
    ffi.C.igTextUnformatted(text, nil)
end

function mimgui.CenterColumnTextDisabled(text)
    if not has_current_window() then return end
    text = tostring(text or "")
    local width = mimgui.GetColumnWidth()
    local calc = mimgui.CalcTextSize(text)
    mimgui.SetCursorPosX(mimgui.GetColumnOffset() + (width - calc.x) / 2)
    ffi.C.igTextDisabled("%s", text)
end

function mimgui.CenterColumnColorText(arg1, arg2)
    if not has_current_window() then return end
    local col, text
    if type(arg1) == "string" or (type(arg2) == "cdata" or type(arg2) == "number" or (type(arg2) == "table" and arg2.x)) then
        text, col = arg1, arg2
    else
        col, text = arg1, arg2
    end
    text = tostring(text or "")
    local width = mimgui.GetColumnWidth()
    local calc = mimgui.CalcTextSize(text)
    mimgui.SetCursorPosX(mimgui.GetColumnOffset() + (width - calc.x) / 2)
    ffi.C.igTextColored(to_vec4(col), "%s", text)
end
mimgui.CenterColumnColoredText = mimgui.CenterColumnColorText

function mimgui.CenterButton(label, size)
    if not has_current_window() then return false end
    label = tostring(label or "")
    local width = ffi.C.igGetWindowWidth()
    local calc = mimgui.CalcTextSize(label)
    local btn_w = calc.x
    if size ~= nil then
        local sz = to_vec2(size)
        if sz.x > 0 then
            btn_w = sz.x
        end
    end
    local style = ffi.C.igGetStyle()
    local pad = (size == nil and style) and (style.FramePadding.x * 2) or 0
    local x = (width - (btn_w + pad)) / 2
    if style and x < style.WindowPadding.x then
        x = style.WindowPadding.x
    end
    ffi.C.igSetCursorPosX(x)
    if size ~= nil then
        return ffi.C.igButton(label, to_vec2(size))
    else
        return ffi.C.igButton(label, ImVec2(0, 0))
    end
end

function mimgui.CenterSmallButton(label)
    if not has_current_window() then return false end
    label = tostring(label or "")
    local width = ffi.C.igGetWindowWidth()
    local calc = mimgui.CalcTextSize(label)
    local style = ffi.C.igGetStyle()
    local pad = style and (style.FramePadding.x * 2) or 0
    local x = (width - (calc.x + pad)) / 2
    if style and x < style.WindowPadding.x then
        x = style.WindowPadding.x
    end
    ffi.C.igSetCursorPosX(x)
    return ffi.C.igSmallButton(label)
end

function mimgui.CenterColumnButton(label, size)
    if not has_current_window() then return false end
    label = tostring(label or "")
    local display_text = label:match('^(.-)##') or label
    local calc = mimgui.CalcTextSize(display_text)
    local btn_w = calc.x
    if size ~= nil then
        local sz = to_vec2(size)
        if sz.x > 0 then
            btn_w = sz.x
        end
    end
    local style = ffi.C.igGetStyle()
    local pad = (size == nil and style) and (style.FramePadding.x * 2) or 0
    local width = mimgui.GetColumnWidth()
    mimgui.SetCursorPosX(mimgui.GetColumnOffset() + (width - (btn_w + pad)) / 2)
    if size ~= nil then
        return ffi.C.igButton(label, to_vec2(size))
    else
        return ffi.C.igButton(label, ImVec2(0, 0))
    end
end

function mimgui.CenterColumnSmallButton(label)
    if not has_current_window() then return false end
    label = tostring(label or "")
    local display_text = label:match('^(.-)##') or label
    local calc = mimgui.CalcTextSize(display_text)
    local style = ffi.C.igGetStyle()
    local pad = style and (style.FramePadding.x * 2) or 0
    local width = mimgui.GetColumnWidth()
    mimgui.SetCursorPosX(mimgui.GetColumnOffset() + (width - (calc.x + pad)) / 2)
    return ffi.C.igSmallButton(label)
end

function mimgui.GetMiddleButtonX(count_or_label)
    if not has_current_window() then return 0.0 end
    if type(count_or_label) == "string" then
        local width = ffi.C.igGetWindowWidth()
        local calc = mimgui.CalcTextSize(count_or_label)
        return (width - calc.x) / 2
    else
        local count = tonumber(count_or_label) or 1
        local width = mimgui.GetWindowContentRegionWidth()
        local style = ffi.C.igGetStyle()
        local space = style and style.ItemSpacing.x or 8.0
        return count == 1 and width or (width / count - ((space * (count - 1)) / count))
    end
end

function mimgui.AddCursorPos(x_or_offset, y)
    if not has_current_window() then return end
    local cur = ffi.C.igGetCursorPos()
    local dx, dy = 0, 0
    if y ~= nil then
        dx = tonumber(x_or_offset) or 0
        dy = tonumber(y) or 0
    else
        local off = to_vec2(x_or_offset)
        dx = off.x or 0
        dy = off.y or 0
    end
    ffi.C.igSetCursorPos(ImVec2(cur.x + dx, cur.y + dy))
end

function mimgui.StrCopy(dst, src, len)
    if dst == nil then return end
    src = tostring(src or "")
    local maxlen = len or cdata_lengths[dst]
    if not maxlen then
        local ok, sz = pcall(ffi.sizeof, dst)
        if ok and sz and sz > 1 then
            maxlen = sz
        else
            maxlen = 256
        end
    end
    local copylen = math.min(#src, maxlen - 1)
    ffi.copy(dst, src, copylen)
    dst[copylen] = 0
end

function mimgui.HelpMark(text)
    if not has_current_window() then return end
    ffi.C.igTextDisabled("(?)")
    if ffi.C.igIsItemHovered(0) then
        ffi.C.igBeginTooltip()
        ffi.C.igPushTextWrapPos(ffi.C.igGetFontSize() * 35.0)
        ffi.C.igTextUnformatted(tostring(text or ""), nil)
        ffi.C.igPopTextWrapPos()
        ffi.C.igEndTooltip()
    end
end

function mimgui.Tooltip(text)
    if not has_current_window() then return end
    if ffi.C.igIsItemHovered(0) then
        ffi.C.igBeginTooltip()
        ffi.C.igTextUnformatted(tostring(text or ""), nil)
        ffi.C.igEndTooltip()
    end
end

local subscriptions = {}
local initSubscriptions = {}
local isInitialized = false

function mimgui.OnInitialize(func)
    local sub = {
        callback = func,
        active = true,
        Unsubscribe = function(self)
            self.active = false
        end
    }
    table.insert(initSubscriptions, sub)
    if isInitialized and func then
        pcall(func)
    end
    return sub
end

function mimgui.IsInitialized()
    return isInitialized
end

function mimgui.OnFrame(arg1, arg2, arg3)
    local condFn, beforeDrawFn, drawFn
    if arg3 ~= nil then
        condFn, beforeDrawFn, drawFn = arg1, arg2, arg3
    elseif arg2 ~= nil then
        condFn, drawFn = arg1, arg2
    else
        drawFn = arg1
    end

    local sub = {
        cond = condFn,
        before = beforeDrawFn,
        draw = drawFn,
        active = true,
        HideCursor = false,
        LockPlayer = false,
        Unsubscribe = function(self)
            self.active = false
        end
    }
    table.insert(subscriptions, sub)
    return sub
end

local function get_cdata_zero(c)
    return c[0]
end

local function stopScriptOnError(contextName, err)
    local errMsg = tostring(err or "Unknown error")
    print(string.format("[mimgui] %s: %s", contextName, errMsg))
    local s = nil
    if type(thisScript) == "function" then
        s = thisScript()
    end
    if s then
        if type(s.die) == "function" then
            s:die(errMsg)
        elseif type(s.unload) == "function" then
            s:unload()
        end
    end
    error(errMsg)
end

local function evalCond(cond)
    if cond == nil then return true end
    local val = cond
    if type(cond) == "function" then
        local ok, res = pcall(cond)
        if not ok then
            stopScriptOnError("Error in condition callback", res)
            return false
        end
        if res == nil or res == false then return false end
        val = res
    end
    if type(val) == "cdata" then
        local ok0, v0 = pcall(get_cdata_zero, val)
        if ok0 and v0 ~= nil then return v0 == true or v0 == 1 end
        return true
    elseif type(val) == "table" then
        local v0 = val[0]
        if v0 ~= nil then return v0 == true or v0 == 1 end
        local v1 = val[1]
        if v1 ~= nil then return v1 == true or v1 == 1 end
        return true
    end
    return (val ~= nil and val ~= false and val ~= 0)
end

function mimgui.__beforeDrawFrame()
    local rawStyle = ffi.C.igGetStyle()
    if rawStyle ~= nil and rawStyle ~= ffi.null then
        cachedRawColors = rawStyle.Colors
    else
        cachedRawColors = nil
    end

    if not isInitialized then
        isInitialized = true
        local initCount = #initSubscriptions
        for i = 1, initCount do
            local sub = initSubscriptions[i]
            if sub and sub.active and sub.callback then
                local ok, err = pcall(sub.callback)
                if not ok and err then
                    sub.active = false
                    stopScriptOnError("Error in OnInitialize callback", err)
                end
            end
        end
        local ok_io, io = pcall(ffi.C.igGetIO_Nil)
        if ok_io and io ~= nil and io ~= ffi.null then
            io.BackendFlags = bit.bor(io.BackendFlags, enums.BackendFlags and enums.BackendFlags.RendererHasTextures or 1024)
            if io.Fonts ~= nil and io.Fonts ~= ffi.null then
                if io.Fonts.Fonts.Size == 0 then
                    ffi.C.ImFontAtlas_AddFontDefault(io.Fonts, nil)
                end
                ffi.C.ImFontAtlas_Build(io.Fonts)
                if (io.FontDefault == nil or io.FontDefault == ffi.null) and io.Fonts.Fonts.Size > 0 then
                    io.FontDefault = io.Fonts.Fonts.Data[0]
                end
            end
        end
    end

    local anyActive = false
    local showCursor = false
    local lockPlayer = false

    local subCount = #subscriptions
    for i = 1, subCount do
        local sub = subscriptions[i]
        if sub and sub.active then
            local cond = evalCond(sub.cond)
            sub._currentActive = cond
            if cond then
                anyActive = true
                if sub.before then
                    local ok, err = pcall(sub.before, sub)
                    if not ok and err then
                        sub.active = false
                        sub._currentActive = false
                        stopScriptOnError("Error in before callback", err)
                    end
                end
                if sub.HideCursor ~= true then
                    showCursor = true
                end
                if sub.LockPlayer == true then
                    lockPlayer = true
                end
            end
        end
    end

    if mimgui.ShowCursor ~= nil then
        showCursor = (mimgui.ShowCursor == true)
    end
    if mimgui.LockPlayer ~= nil then
        lockPlayer = (mimgui.LockPlayer == true)
    end

    return anyActive, showCursor, lockPlayer
end

function mimgui.__onDrawFrame()
    local subCount = #subscriptions
    local showCursor = false
    local lockPlayer = false
    for i = 1, subCount do
        local sub = subscriptions[i]
        if sub and sub.active and sub._currentActive and sub.draw then
            local ok, err = pcall(sub.draw, sub)
            if not ok and err then
                sub.active = false
                sub._currentActive = false
                stopScriptOnError("Error in draw callback", err)
            end
            if sub.HideCursor ~= true then
                showCursor = true
            end
            if sub.LockPlayer == true then
                lockPlayer = true
            end
        end
    end
    if mimgui.ShowCursor ~= nil then
        showCursor = (mimgui.ShowCursor == true)
    end
    if mimgui.LockPlayer ~= nil then
        lockPlayer = (mimgui.LockPlayer == true)
    end
    return showCursor, lockPlayer
end

function mimgui.PushID(id)
    if type(id) == "number" then
        return ffi.C.igPushID_Int(id)
    elseif type(id) == "string" then
        return ffi.C.igPushID_Str(id)
    elseif type(id) == "cdata" then
        return ffi.C.igPushID_Ptr(id)
    else
        return ffi.C.igPushID_Str(tostring(id or ""))
    end
end

function mimgui.PopID()
    return ffi.C.igPopID()
end

function mimgui.PushIDInt(id)
    return ffi.C.igPushID_Int(id or 0)
end

function mimgui.SetKeyboardFocusHere(offset)
    return ffi.C.igSetKeyboardFocusHere(offset or 0)
end

function mimgui.SetScrollHereX(ratio)
    return ffi.C.igSetScrollHereX(ratio or 0.5)
end

function mimgui.SetScrollHereY(ratio)
    return ffi.C.igSetScrollHereY(ratio or 0.5)
end

function mimgui.SetScrollX(scroll_x)
    return ffi.C.igSetScrollX_Float(scroll_x or 0.0)
end

function mimgui.SetScrollY(scroll_y)
    return ffi.C.igSetScrollY_Float(scroll_y or 0.0)
end

function mimgui.GetScrollX()
    return ffi.C.igGetScrollX()
end

function mimgui.GetScrollY()
    return ffi.C.igGetScrollY()
end

function mimgui.GetScrollMaxX()
    return ffi.C.igGetScrollMaxX()
end

function mimgui.GetScrollMaxY()
    return ffi.C.igGetScrollMaxY()
end

function mimgui.SetMouseCursor(cursor_type)
    return ffi.C.igSetMouseCursor(cursor_type or 0)
end

function mimgui.GetTime()
    return ffi.C.igGetTime()
end

function mimgui.PushTextWrapPos(wrap_pos_x)
    return ffi.C.igPushTextWrapPos(wrap_pos_x or 0.0)
end

function mimgui.PopTextWrapPos()
    return ffi.C.igPopTextWrapPos()
end

function mimgui.ColorButton(desc_id, col, flags, size)
    return ffi.C.igColorButton(tostring(desc_id), to_vec4(col), flags or 0, to_vec2(size))
end

function mimgui.IsMouseHoveringRect(r_min, r_max, clip)
    if clip == nil then clip = true end
    return ffi.C.igIsMouseHoveringRect(to_vec2(r_min), to_vec2(r_max), clip)
end

function mimgui.PushButtonRepeat(repeat_btn)
    pcall(ffi.C.neom_mimgui_push_button_repeat, repeat_btn == true)
end

function mimgui.PopButtonRepeat()
    pcall(ffi.C.neom_mimgui_pop_button_repeat)
end

function mimgui.MenuItemBoolPtr(label, shortcut, p_selected, enabled)
    if enabled == nil then enabled = true end
    local sc = (shortcut and tostring(shortcut) ~= "") and tostring(shortcut) or nil
    if type(shortcut) == "boolean" and p_selected == nil then
        p_selected = shortcut
        sc = nil
    end
    if type(p_selected) == "cdata" then
        return ffi.C.igMenuItem_BoolPtr(tostring(label), sc, p_selected, enabled)
    elseif type(p_selected) == "table" then
        local val = p_selected[0] or p_selected[1]
        local b = ffi.new("bool[1]", val == true)
        local pressed = ffi.C.igMenuItem_BoolPtr(tostring(label), sc, b, enabled)
        if p_selected[0] ~= nil then p_selected[0] = b[0] else p_selected[1] = b[0] end
        return pressed
    else
        return ffi.C.igMenuItem_Bool(tostring(label), sc, p_selected == true, enabled)
    end
end

local function format_text(fmt, ...)
    local n = select("#", ...)
    if n == 0 then
        if fmt == nil then return "" end
        return tostring(fmt)
    end
    local ok, res = pcall(string.format, tostring(fmt), ...)
    if ok then
        return res
    end
    return tostring(fmt)
end

function mimgui.Text(fmt, ...)
    local s = format_text(fmt, ...)
    return ffi.C.igTextUnformatted(s, ffi.null)
end

function mimgui.TextUnformatted(text)
    if text == nil then text = "" else text = tostring(text) end
    return ffi.C.igTextUnformatted(text, ffi.null)
end

function mimgui.TextColored(col, fmt, ...)
    local s = format_text(fmt, ...)
    ffi.C.igPushStyleColor_Vec4(enums.Col.Text, to_vec4(col))
    ffi.C.igTextUnformatted(s, ffi.null)
    ffi.C.igPopStyleColor(1)
end

function mimgui.TextDisabled(fmt, ...)
    local s = format_text(fmt, ...)
    local disCol = (staticColorsProxy and staticColorsProxy[enums.Col.TextDisabled]) or ImVec4(0.5, 0.5, 0.5, 1.0)
    ffi.C.igPushStyleColor_Vec4(enums.Col.Text, disCol)
    ffi.C.igTextUnformatted(s, ffi.null)
    ffi.C.igPopStyleColor(1)
end

function mimgui.TextWrapped(fmt, ...)
    local s = format_text(fmt, ...)
    ffi.C.igPushTextWrapPos(0.0)
    ffi.C.igTextUnformatted(s, ffi.null)
    ffi.C.igPopTextWrapPos()
end

function mimgui.Bullet()
    return ffi.C.igBullet()
end

function mimgui.BulletText(fmt, ...)
    local s = format_text(fmt, ...)
    ffi.C.igBullet()
    return ffi.C.igTextUnformatted(s, ffi.null)
end

function mimgui.GetClipboardText()
    if getClipboardText then
        local ok, res = pcall(getClipboardText)
        if ok and res and res ~= "" then return res end
    end
    local str = ffi.C.igGetClipboardText()
    if str ~= nil and str ~= ffi.null then return ffi.string(str) end
    return ""
end

function mimgui.SetClipboardText(text)
    local s = tostring(text or "")
    if setClipboardText then
        pcall(setClipboardText, s)
    end
    return ffi.C.igSetClipboardText(s)
end

function mimgui.SetWindowPosStr(name, pos, cond)
    return ffi.C.igSetWindowPos_Str(tostring(name), to_vec2(pos), cond or 0)
end

function mimgui.SetWindowSizeStr(name, size, cond)
    return ffi.C.igSetWindowSize_Str(tostring(name), to_vec2(size), cond or 0)
end

function mimgui.DragFloat3(label, v, v_speed, v_min, v_max, format, flags)
    return ffi.C.igDragFloat3(tostring(label), v, v_speed or 1.0, v_min or 0.0, v_max or 0.0, format or "%.3f", flags or 0)
end

function mimgui.InputFloat3(label, v, format, flags)
    return ffi.C.igInputFloat3(tostring(label), v, format or "%.3f", flags or 0)
end

local symbol_cache = {}

local function wrap_fn(fn, name)
    if type(fn) ~= "function" and type(fn) ~= "cdata" then
        return fn
    end
    if type(fn) == "cdata" and not tostring(ffi.typeof(fn)):find("(*)(", 1, true) then
        return fn
    end
    return function(...)
        local ok, r1, r2, r3, r4 = pcall(fn, ...)
        if not ok then
            print(string.format("[mimgui] FFI call failed in '%s': %s", tostring(name), tostring(r1)))
            return nil
        end
        return r1, r2, r3, r4
    end
end

local function resolve_symbol(k)
    local cached = symbol_cache[k]
    if cached ~= nil then return cached end

    if enums[k] ~= nil then
        symbol_cache[k] = enums[k]
        return enums[k]
    end

    -- Check for EnumName_Value pattern (e.g. Cond_Always, WindowFlags_NoResize, Col_Button)
    local enum_group, enum_val = tostring(k):match("^([^_]+)_(.+)$")
    if enum_group and enum_val then
        if enums[enum_group] and enums[enum_group][enum_val] ~= nil then
            symbol_cache[k] = enums[enum_group][enum_val]
            return enums[enum_group][enum_val]
        end
    end

    local ok, fn = pcall(function() return ffi.C["ig" .. k] end)
    if ok and fn ~= nil then
        local wrapped = wrap_fn(fn, k)
        symbol_cache[k] = wrapped
        return wrapped
    end

    local suffixes = { "_Nil", "_Str", "_Bool", "_ID", "_Float", "_Int", "_FloatPtr" }
    for _, suffix in ipairs(suffixes) do
        ok, fn = pcall(function() return ffi.C["ig" .. k .. suffix] end)
        if ok and fn ~= nil then
            local wrapped = wrap_fn(fn, k)
            symbol_cache[k] = wrapped
            return wrapped
        end
    end

    ok, fn = pcall(function() return ffi.C[k] end)
    if ok and fn ~= nil then
        local wrapped = wrap_fn(fn, k)
        symbol_cache[k] = wrapped
        return wrapped
    end

    ok, fn = pcall(function() return ffi.C["ImGui" .. k] end)
    if ok and fn ~= nil then
        local wrapped = wrap_fn(fn, k)
        symbol_cache[k] = wrapped
        return wrapped
    end

    ok, fn = pcall(function() return ffi.C["ImDrawList_" .. k] end)
    if ok and fn ~= nil then
        local wrapped = wrap_fn(fn, k)
        symbol_cache[k] = wrapped
        return wrapped
    end

    symbol_cache[k] = false
    return nil
end

setmetatable(mimgui, {
    __index = function(t, k)
        local fn = resolve_symbol(k)
        if fn ~= false and fn ~= nil then
            return fn
        end
        return nil
    end,
    __newindex = function(t, k, v)
        if k == "Link" then
            return
        end
        rawset(t, k, v)
    end
})

for k, v in pairs(enums) do
    if rawget(mimgui, k) == nil then
        mimgui[k] = v
    end
end

return mimgui
