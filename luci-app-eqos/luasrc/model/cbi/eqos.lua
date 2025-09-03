local ipc = require "luci.ip"

local m = Map("eqos", translate("Quality of Service"))

local s = m:section(TypedSection, "eqos", "")
s.anonymous = true

local e = s:option(Flag, "enabled", translate("Enable"))
e.rmempty = false

local mac_enable = s:option(Flag, "ipv6_enabled", translate("Enable MAC-based Speed Limiting"), translate("Apply comprehensive speed limits to all IP addresses (IPv4/IPv6) of a device using MAC address identification"))
mac_enable.rmempty = false
mac_enable:depends("enabled", "1")

local dl = s:option(Value, "download", translate("Download speed (Mbit/s)"), translate("Total bandwidth"))
dl.datatype = "and(uinteger,min(1))"

local ul = s:option(Value, "upload", translate("Upload speed (Mbit/s)"), translate("Total bandwidth"))
ul.datatype = "and(uinteger,min(1))"

s = m:section(TypedSection, "device", translate("Device Speed Limiting Rules"))
s.template = "cbi/tblsection"
s.anonymous = true
s.addremove = true
s.sortable  = true

local device_type = s:option(ListValue, "device_type", translate("Limiting Mode"))
device_type:value("ip", translate("IP Address Mode"))
device_type:value("mac", translate("MAC Address Mode (Recommended)"))
device_type.default = "ip"

local ip = s:option(Value, "ip", translate("IP Address"))
ip:depends("device_type", "ip")

local mac = s:option(Value, "mac", translate("MAC Address"))
mac:depends("device_type", "mac")

local device_info = s:option(DummyValue, "device_info", translate("Device Information"))
device_info:depends("device_type", "mac")

-- Collect device information with multiple fallback methods
local devices = {}
local sys = require "luci.sys"
local util = require "luci.util"

-- Method 1: Try ipc.neighbors (preferred)
local function collect_via_ipc()
	local success = pcall(function()
		-- Try different interface names
		local interfaces = {"br-lan", "lan", "eth0"}
		for _, iface in ipairs(interfaces) do
			pcall(function()
				ipc.neighbors({family = 4, dev = iface}, function(n)
					if n.mac and n.dest then
						local mac_addr = n.mac:upper()
						if not devices[mac_addr] then
							devices[mac_addr] = {mac = mac_addr, ipv4 = {}, ipv6 = {}}
						end
						table.insert(devices[mac_addr].ipv4, n.dest:string())
					end
				end)
				ipc.neighbors({family = 6, dev = iface}, function(n)
					if n.mac and n.dest then
						local mac_addr = n.mac:upper()
						if not devices[mac_addr] then
							devices[mac_addr] = {mac = mac_addr, ipv4 = {}, ipv6 = {}}
						end
						table.insert(devices[mac_addr].ipv6, n.dest:string())
					end
				end)
			end)
		end
	end)
	return success
end

-- Method 2: Parse /proc/net/arp and ip neigh output
local function collect_via_system()
	local arp_content = sys.exec("cat /proc/net/arp 2>/dev/null || true")
	if arp_content and #arp_content > 0 then
		for line in arp_content:gmatch("[^\n]+") do
			local ip, hw_type, flags, mac = line:match("([%d%.]+)%s+0x%w+%s+0x%w+%s+([%w:]+)")
			if ip and mac and mac ~= "00:00:00:00:00:00" then
				local mac_addr = mac:upper()
				if not devices[mac_addr] then
					devices[mac_addr] = {mac = mac_addr, ipv4 = {}, ipv6 = {}}
				end
				table.insert(devices[mac_addr].ipv4, ip)
			end
		end
	end
	
	-- Get IPv6 neighbors
	local ipv6_neigh = sys.exec("ip -6 neigh show 2>/dev/null || true")
	if ipv6_neigh and #ipv6_neigh > 0 then
		for line in ipv6_neigh:gmatch("[^\n]+") do
			local ipv6, dev, mac = line:match("([%w:]+)%s+dev%s+%w+%s+lladdr%s+([%w:]+)")
			if ipv6 and mac then
				local mac_addr = mac:upper()
				if not devices[mac_addr] then
					devices[mac_addr] = {mac = mac_addr, ipv4 = {}, ipv6 = {}}
				end
				table.insert(devices[mac_addr].ipv6, ipv6)
			end
		end
	end
end

-- Try collection methods in order
if not collect_via_ipc() then
	collect_via_system()
end

-- Add device options
for mac_addr, device in pairs(devices) do
	local ipv4_list = table.concat(device.ipv4, ", ")
	local ipv6_count = #device.ipv6
	local display_text = string.format("%s | IPv4: %s | IPv6: %d addresses", 
		mac_addr, 
		ipv4_list ~= "" and ipv4_list or "None", 
		ipv6_count)
	
	mac:value(mac_addr, display_text)
	
	-- For IP mode, still show IPv4 addresses
	for _, ipv4 in ipairs(device.ipv4) do
		ip:value(ipv4, string.format("%s (%s)", ipv4, mac_addr))
	end
end

dl = s:option(Value, "download", translate("Download speed (Mbit/s)"))
dl.datatype = "and(uinteger,min(1))"

ul = s:option(Value, "upload", translate("Upload speed (Mbit/s)"))
ul.datatype = "and(uinteger,min(1))"

comment = s:option(Value, "comment", translate("Comment"))

return m
