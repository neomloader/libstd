require 'RakLua'

local MODULE = {
	MODULEINFO = {
		name = 'samp.events',
		version = 4
	},
	INTERFACE = {
		OUTCOMING_RPCS    = {},
		OUTCOMING_PACKETS = {},
		INCOMING_RPCS     = {},
		INCOMING_PACKETS  = {}
	},
	EXPORTS = {}
}

local BitStreamIO            = require 'samp.events.bitstream_io'
MODULE.INTERFACE.BitStreamIO = BitStreamIO

local function read_data(bs, dataType)
	if type(dataType) ~= 'table' then
		return BitStreamIO[dataType].read(bs)
	else
		local values = {}
		for _, it in ipairs(dataType) do
			local name, t = next(it)
			values[name] = read_data(bs, t)
		end
		return values
	end
end

local function write_data(bs, dataType, value)
	if type(dataType) ~= 'table' then
		BitStreamIO[dataType].write(bs, value)
	else
		for _, it in ipairs(dataType) do
			local name, t = next(it)
			write_data(bs, t, value[name])
		end
	end
end

local _raw_unpack = (type(table.unpack) == 'function' and table.unpack) or (type(_G.unpack) == 'function' and _G.unpack) or unpack
local function safe_unpack(t)
	if type(t) ~= 'table' then return t end
	local len = #t
	if type(t.n) == 'number' then
		len = t.n
	end
	return _raw_unpack(t, 1, len)
end

local function process_event(bs, callback, struct, ignorebits)
	if type(struct) ~= 'table' then return end
	local args = {}
	if bs and bs ~= 0 then
		if ignorebits then
			raknetBitStreamIgnoreBits(bs, ignorebits)
		end
		if type(struct[2]) == 'function' then
			local r1, r2 = struct[2](bs)
			if type(callback) == 'table' and type(r1) == 'string' then
				callback = callback[r1]
				if callback then
					args = r2
				else
					return
				end
			else
				args = r1
			end
		else

			for i = 2, #struct do
				local _, t = next(struct[i])
				table.insert(args, read_data(bs, t))
			end
		end
	end
	if type(args) ~= 'table' then
		args = {args}
	end
	local result = callback(safe_unpack(args))
	if result == false then
		return false
	end
	if bs and bs ~= 0 and type(result) == 'table' then
		raknetBitStreamSetWriteOffset(bs, ignorebits or 0)
		if type(struct[3]) == 'function' then
			struct[3](bs, result)
		else
			assert(#struct - 1 == #result)
			for i = 2, #struct do
				local _, t = next(struct[i])
				write_data(bs, t, result[i - 1])
			end
		end
	end
end

local function process_packet(id, bs, event_table, ignorebits)
	local entry = event_table[id]
	if entry ~= nil then
		local key = entry[1]
		local callback = nil
		if type(key) == 'table' then
			for i, name in ipairs(key) do
				if type(MODULE[name]) == 'function' then
					if not callback then callback = {} end
					callback[name] = MODULE[name]
				end
			end
		elseif type(MODULE[key]) == 'function' then
			callback = MODULE[key]
		end
		if callback then
			return process_event(bs, callback, entry, ignorebits)
		end
	end
end

local interface = MODULE.INTERFACE
local function samp_on_send_rpc(id, bitStream, priority, reliability, orderingChannel, shiftTs)
	return process_packet(id, bitStream, interface.OUTCOMING_RPCS)
end

local function samp_on_send_packet(id, bitStream, priority, reliability, orderingChannel)
	return process_packet(id, bitStream, interface.OUTCOMING_PACKETS, 8)
end

local function samp_on_receive_rpc(id, bitStream)
	return process_packet(id, bitStream, interface.INCOMING_RPCS)
end

local function samp_on_receive_packet(id, bitStream)
	return process_packet(id, bitStream, interface.INCOMING_PACKETS, 8)
end

addEventHandler('onSendRpc', samp_on_send_rpc)
addEventHandler('onSendPacket', samp_on_send_packet)
addEventHandler('onReceiveRpc', samp_on_receive_rpc)
addEventHandler('onReceivePacket', samp_on_receive_packet)

return MODULE
