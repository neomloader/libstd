local cp1251_to_utf8 = {
	["\128"] = "\208\130",
	["\129"] = "\208\131",
	["\130"] = "\226\128\154",
	["\131"] = "\209\147",
	["\132"] = "\226\128\158",
	["\133"] = "\226\128\166",
	["\134"] = "\226\128\160",
	["\135"] = "\226\128\161",
	["\136"] = "\226\130\172",
	["\137"] = "\226\128\176",
	["\138"] = "\208\137",
	["\139"] = "\226\128\185",
	["\140"] = "\208\138",
	["\141"] = "\208\140",
	["\142"] = "\208\139",
	["\143"] = "\208\143",
	["\144"] = "\209\146",
	["\145"] = "\226\128\152",
	["\146"] = "\226\128\153",
	["\147"] = "\226\128\156",
	["\148"] = "\226\128\157",
	["\149"] = "\226\128\162",
	["\150"] = "\226\128\147",
	["\151"] = "\226\128\148",
	["\152"] = "\127",
	["\153"] = "\226\132\162",
	["\154"] = "\209\153",
	["\155"] = "\226\128\186",
	["\156"] = "\209\154",
	["\157"] = "\209\156",
	["\158"] = "\209\155",
	["\159"] = "\209\159",
	["\160"] = "\194\160",
	["\161"] = "\208\142",
	["\162"] = "\209\158",
	["\163"] = "\208\136",
	["\164"] = "\194\164",
	["\165"] = "\210\144",
	["\166"] = "\194\166",
	["\167"] = "\194\167",
	["\168"] = "\208\129",
	["\169"] = "\194\169",
	["\170"] = "\208\132",
	["\171"] = "\194\171",
	["\172"] = "\194\172",
	["\173"] = "\194\173",
	["\174"] = "\194\174",
	["\175"] = "\208\135",
	["\176"] = "\194\176",
	["\177"] = "\194\177",
	["\178"] = "\208\134",
	["\179"] = "\209\150",
	["\180"] = "\210\145",
	["\181"] = "\194\181",
	["\182"] = "\194\182",
	["\183"] = "\194\183",
	["\184"] = "\209\145",
	["\185"] = "\226\132\150",
	["\186"] = "\209\148",
	["\187"] = "\194\187",
	["\188"] = "\209\152",
	["\189"] = "\208\133",
	["\190"] = "\209\149",
	["\191"] = "\209\151",
	["\192"] = "\208\144",
	["\193"] = "\208\145",
	["\194"] = "\208\146",
	["\195"] = "\208\147",
	["\196"] = "\208\148",
	["\197"] = "\208\149",
	["\198"] = "\208\150",
	["\199"] = "\208\151",
	["\200"] = "\208\152",
	["\201"] = "\208\153",
	["\202"] = "\208\154",
	["\203"] = "\208\155",
	["\204"] = "\208\156",
	["\205"] = "\208\157",
	["\206"] = "\208\158",
	["\207"] = "\208\159",
	["\208"] = "\208\160",
	["\209"] = "\208\161",
	["\210"] = "\208\162",
	["\211"] = "\208\163",
	["\212"] = "\208\164",
	["\213"] = "\208\165",
	["\214"] = "\208\166",
	["\215"] = "\208\167",
	["\216"] = "\208\168",
	["\217"] = "\208\169",
	["\218"] = "\208\170",
	["\219"] = "\208\171",
	["\220"] = "\208\172",
	["\221"] = "\208\173",
	["\222"] = "\208\174",
	["\223"] = "\208\175",
	["\224"] = "\208\176",
	["\225"] = "\208\177",
	["\226"] = "\208\178",
	["\227"] = "\208\179",
	["\228"] = "\208\180",
	["\229"] = "\208\181",
	["\230"] = "\208\182",
	["\231"] = "\208\183",
	["\232"] = "\208\184",
	["\233"] = "\208\185",
	["\234"] = "\208\186",
	["\235"] = "\208\187",
	["\236"] = "\208\188",
	["\237"] = "\208\189",
	["\238"] = "\208\190",
	["\239"] = "\208\191",
	["\240"] = "\209\128",
	["\241"] = "\209\129",
	["\242"] = "\209\130",
	["\243"] = "\209\131",
	["\244"] = "\209\132",
	["\245"] = "\209\133",
	["\246"] = "\209\134",
	["\247"] = "\209\135",
	["\248"] = "\209\136",
	["\249"] = "\209\137",
	["\250"] = "\209\138",
	["\251"] = "\209\139",
	["\252"] = "\209\140",
	["\253"] = "\209\141",
	["\254"] = "\209\142",
	["\255"] = "\209\143"
}

local utf8_to_cp1251 = {
	["\208\130"] = "\128",
	["\208\131"] = "\129",
	["\226\128\154"] = "\130",
	["\209\147"] = "\131",
	["\226\128\158"] = "\132",
	["\226\128\166"] = "\133",
	["\226\128\160"] = "\134",
	["\226\128\161"] = "\135",
	["\226\130\172"] = "\136",
	["\226\128\176"] = "\137",
	["\208\137"] = "\138",
	["\226\128\185"] = "\139",
	["\208\138"] = "\140",
	["\208\140"] = "\141",
	["\208\139"] = "\142",
	["\208\143"] = "\143",
	["\209\146"] = "\144",
	["\226\128\152"] = "\145",
	["\226\128\153"] = "\146",
	["\226\128\156"] = "\147",
	["\226\128\157"] = "\148",
	["\226\128\162"] = "\149",
	["\226\128\147"] = "\150",
	["\226\128\148"] = "\151",
	["\226\132\162"] = "\153",
	["\209\153"] = "\154",
	["\226\128\186"] = "\155",
	["\209\154"] = "\156",
	["\209\156"] = "\157",
	["\209\155"] = "\158",
	["\209\159"] = "\159",
	["\194\160"] = "\160",
	["\208\142"] = "\161",
	["\209\158"] = "\162",
	["\208\136"] = "\163",
	["\194\164"] = "\164",
	["\210\144"] = "\165",
	["\194\166"] = "\166",
	["\194\167"] = "\167",
	["\208\129"] = "\168",
	["\194\169"] = "\169",
	["\208\132"] = "\170",
	["\194\171"] = "\171",
	["\194\172"] = "\172",
	["\194\173"] = "\173",
	["\194\174"] = "\174",
	["\208\135"] = "\175",
	["\194\176"] = "\176",
	["\194\177"] = "\177",
	["\208\134"] = "\178",
	["\209\150"] = "\179",
	["\210\145"] = "\180",
	["\194\181"] = "\181",
	["\194\182"] = "\182",
	["\194\183"] = "\183",
	["\209\145"] = "\184",
	["\226\132\150"] = "\185",
	["\209\148"] = "\186",
	["\194\187"] = "\187",
	["\209\152"] = "\188",
	["\208\133"] = "\189",
	["\209\149"] = "\190",
	["\209\151"] = "\191",
	["\208\144"] = "\192",
	["\208\145"] = "\193",
	["\208\146"] = "\194",
	["\208\147"] = "\195",
	["\208\148"] = "\196",
	["\208\149"] = "\197",
	["\208\150"] = "\198",
	["\208\151"] = "\199",
	["\208\152"] = "\200",
	["\208\153"] = "\201",
	["\208\154"] = "\202",
	["\208\155"] = "\203",
	["\208\156"] = "\204",
	["\208\157"] = "\205",
	["\208\158"] = "\206",
	["\208\159"] = "\207",
	["\208\160"] = "\208",
	["\208\161"] = "\209",
	["\208\162"] = "\210",
	["\208\163"] = "\211",
	["\208\164"] = "\212",
	["\208\165"] = "\213",
	["\208\166"] = "\214",
	["\208\167"] = "\215",
	["\208\168"] = "\216",
	["\208\169"] = "\217",
	["\208\170"] = "\218",
	["\208\171"] = "\219",
	["\208\172"] = "\220",
	["\208\173"] = "\221",
	["\208\174"] = "\222",
	["\208\175"] = "\223",
	["\208\176"] = "\224",
	["\208\177"] = "\225",
	["\208\178"] = "\226",
	["\208\179"] = "\227",
	["\208\180"] = "\228",
	["\208\181"] = "\229",
	["\208\182"] = "\230",
	["\208\183"] = "\231",
	["\208\184"] = "\232",
	["\208\185"] = "\233",
	["\208\186"] = "\234",
	["\208\187"] = "\235",
	["\208\188"] = "\236",
	["\208\189"] = "\237",
	["\208\190"] = "\238",
	["\208\191"] = "\239",
	["\209\128"] = "\240",
	["\209\129"] = "\241",
	["\209\130"] = "\242",
	["\209\131"] = "\243",
	["\209\132"] = "\244",
	["\209\133"] = "\245",
	["\209\134"] = "\246",
	["\209\135"] = "\247",
	["\209\136"] = "\248",
	["\209\137"] = "\249",
	["\209\138"] = "\250",
	["\209\139"] = "\251",
	["\209\140"] = "\252",
	["\209\141"] = "\253",
	["\209\142"] = "\254",
	["\209\143"] = "\255"
}

local u8_cache = {}
local u8_cache_count = 0
local s_native_u8 = nil
local function is_valid_utf8_multibyte(s)
	local i, len = 1, #s
	local has_high = false
	while i <= len do
		local c = s:byte(i)
		if c <= 0x7F then
			i = i + 1
		elseif c >= 0xC2 and c <= 0xDF then
			if i + 1 > len then return false end
			local c2 = s:byte(i + 1)
			if c2 < 0x80 or c2 > 0xBF then return false end
			has_high = true
			i = i + 2
		elseif c >= 0xE0 and c <= 0xEF then
			if i + 2 > len then return false end
			local c2, c3 = s:byte(i + 1), s:byte(i + 2)
			if c2 < 0x80 or c2 > 0xBF or c3 < 0x80 or c3 > 0xBF then return false end
			has_high = true
			i = i + 3
		elseif c >= 0xF0 and c <= 0xF4 then
			if i + 3 > len then return false end
			local c2, c3, c4 = s:byte(i + 1), s:byte(i + 2), s:byte(i + 3)
			if c2 < 0x80 or c2 > 0xBF or c3 < 0x80 or c3 > 0xBF or c4 < 0x80 or c4 > 0xBF then return false end
			has_high = true
			i = i + 4
		else
			return false
		end
	end
	return has_high
end

local function cp1251_to_u8(s)
	if type(s) ~= "string" or s == "" then return s or "" end
	local cached = u8_cache[s]
	if cached then return cached end
	if not s:find("[\128-\255]") or is_valid_utf8_multibyte(s) then
		if u8_cache_count < 32768 then
			u8_cache[s] = s
			u8_cache_count = u8_cache_count + 1
		end
		return s
	end
	if s_native_u8 == nil then
		s_native_u8 = rawget(_G, "monet_cp1251_to_utf8") or rawget(_G, "ansiToUtf8") or false
	end
	local res
	if s_native_u8 then
		res = s_native_u8(s)
	else
		local len = #s
		local i = 1
		local parts = {}
		local part_start = 1
		while i <= len do
			local c = s:byte(i)
			if c <= 0x7F then
				i = i + 1
			elseif c >= 0xC2 and c <= 0xDF and i + 1 <= len and s:byte(i + 1) >= 0x80 and s:byte(i + 1) <= 0xBF then
				i = i + 2
			elseif c >= 0xE0 and c <= 0xEF and i + 2 <= len and s:byte(i + 1) >= 0x80 and s:byte(i + 1) <= 0xBF and s:byte(i + 2) >= 0x80 and s:byte(i + 2) <= 0xBF then
				i = i + 3
			elseif c >= 0xF0 and c <= 0xF4 and i + 3 <= len and s:byte(i + 1) >= 0x80 and s:byte(i + 1) <= 0xBF and s:byte(i + 2) >= 0x80 and s:byte(i + 2) <= 0xBF and s:byte(i + 3) >= 0x80 and s:byte(i + 3) <= 0xBF then
				i = i + 4
			else
				if i > part_start then
					table.insert(parts, s:sub(part_start, i - 1))
				end
				table.insert(parts, cp1251_to_utf8[string.char(c)] or "?")
				i = i + 1
				part_start = i
			end
		end
		if part_start <= len then
			table.insert(parts, s:sub(part_start, len))
		end
		res = table.concat(parts)
	end
	if u8_cache_count < 32768 then
		u8_cache[s] = res
		u8_cache_count = u8_cache_count + 1
	end
	return res
end

local cp1251_cache = {}
local cp1251_cache_count = 0
local s_native_cp1251 = nil
local function u8_to_cp1251(s)
	if type(s) ~= "string" or s == "" then return s or "" end
	local cached = cp1251_cache[s]
	if cached then return cached end
	local res
	if not s:find("[\128-\255]") then
		res = s
	else
		if s_native_cp1251 == nil then
			s_native_cp1251 = rawget(_G, "monet_utf8_to_cp1251") or rawget(_G, "utf8ToAnsi") or false
		end
		if s_native_cp1251 then
			res = s_native_cp1251(s)
		else
			s = s:gsub("[\224-\239][\128-\191][\128-\191]", utf8_to_cp1251)
			res = (s:gsub("[\192-\223][\128-\191]", utf8_to_cp1251))
		end
	end
	if cp1251_cache_count < 16384 then
		cp1251_cache[s] = res
		cp1251_cache_count = cp1251_cache_count + 1
	end
	return res
end

local encoding = {
	default = "CP1251"
}

local aliases = {
	UTF7 = "UTF-7",
	UTF8 = "UTF-8",
	UTF16 = "UTF-16",
	UTF32 = "UTF-32",
	CP1251 = "CP1251",
	WINDOWS1251 = "CP1251",
	["WINDOWS-1251"] = "CP1251",
	["WIN-1251"] = "CP1251",
	["1251"] = "CP1251",
	["CP-1251"] = "CP1251",
}

local function normalize_encoding_name(e)
	if not e then return nil end
	local direct = aliases[e]
	if direct then return direct end
	local upper = string.upper(e)
	direct = aliases[upper]
	if direct then return direct end
	e = string.upper(string.gsub(e, "_", "-"))
	if aliases[e] then return aliases[e] end
	return e
end

local iconv = nil
local function get_iconv()
	if not iconv then
		local ok, mod = pcall(require, "iconv")
		if ok then iconv = mod end
	end
	return iconv
end

local converter = {}
function converter.new(enc)
	local private = {
		encoder = {},
		decoder = {},
	}

	local public = {
		encoding = enc
	}

	function public:encode(str, enc)
		if str == nil then return "" end
		if type(str) ~= "string" then str = tostring(str) end
		if str == "" then return "" end
		if not enc and self.encoding == "UTF-8" and encoding.default == "CP1251" then
			return cp1251_to_u8(str)
		end
		if not enc and self.encoding == "CP1251" and encoding.default == "CP1251" then
			return str
		end
		if enc then enc = normalize_encoding_name(enc)
		else enc = normalize_encoding_name(encoding.default)
		end
		if not enc or enc == self.encoding then return str end
		if self.encoding == "UTF-8" and enc == "CP1251" then
			return cp1251_to_u8(str)
		elseif self.encoding == "CP1251" and enc == "UTF-8" then
			return u8_to_cp1251(str)
		end
		local ic = get_iconv()
		if not ic then return str end
		local ok, res = pcall(function()
			local cd = private.encoder[enc]
			if not cd then
				cd = ic.new(self.encoding .. "//IGNORE", enc)
				if not cd then return str end
				private.encoder[enc] = cd
			end
			return cd:iconv(str)
		end)
		if ok and res then return res end
		return str
	end

	function public:decode(str, enc)
		if str == nil then return "" end
		if type(str) ~= "string" then str = tostring(str) end
		if str == "" then return "" end
		if not enc and self.encoding == "UTF-8" and encoding.default == "CP1251" then
			return u8_to_cp1251(str)
		end
		if not enc and self.encoding == "CP1251" and encoding.default == "CP1251" then
			return str
		end
		if enc then enc = normalize_encoding_name(enc)
		else enc = normalize_encoding_name(encoding.default)
		end
		if not enc or enc == self.encoding then return str end
		if self.encoding == "UTF-8" and enc == "CP1251" then
			return u8_to_cp1251(str)
		elseif self.encoding == "CP1251" and enc == "UTF-8" then
			return cp1251_to_u8(str)
		end
		local ic = get_iconv()
		if not ic then return str end
		local ok, res = pcall(function()
			local cd = private.decoder[enc]
			if not cd then
				cd = ic.new(enc .. "//IGNORE", self.encoding)
				if not cd then return str end
				private.decoder[enc] = cd
			end
			return cd:iconv(str)
		end)
		if ok and res then return res end
		return str
	end

	local mt = {}
	if enc == "UTF-8" then
		function mt:__call(str, enc_override)
			if not enc_override and encoding.default == "CP1251" then
				if str == nil then return "" end
				if type(str) ~= "string" then str = tostring(str) end
				return cp1251_to_u8(str)
			end
			return self:encode(str, enc_override)
		end
	elseif enc == "CP1251" then
		function mt:__call(str, enc_override)
			if not enc_override and encoding.default == "CP1251" then
				if str == nil then return "" end
				if type(str) ~= "string" then str = tostring(str) end
				return u8_to_cp1251(str)
			end
			return self:encode(str, enc_override)
		end
	else
		function mt:__call(str, enc_override)
			return self:encode(str, enc_override)
		end
	end

	setmetatable(public, mt)
	return public
end

setmetatable(encoding, {
	__index = function(table, index)
		assert(type(index) == "string")
		local enc = normalize_encoding_name(index)
		local already_loaded = rawget(table, enc)
		if already_loaded then
			table[index] = already_loaded
			return already_loaded
		else
			local conv = converter.new(enc)
			table[index] = conv
			table[enc] = conv
			return conv
		end
	end
})

return encoding
