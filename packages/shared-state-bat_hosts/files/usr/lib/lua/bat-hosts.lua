local shared_state = require("shared-state")
local JSON = require("luci.jsonc")
local utils = require("lime.utils")

local bat_hosts = {}

function bat_hosts.bathost_deserialize(hostname_plus_iface)
    local partial_hostname = hostname_plus_iface
    local iface
    for _, ifname in ipairs(utils.get_ifnames()) do
        local serialized_ifname = string.gsub(ifname, "%W", "_")
        serialized_ifname = utils.literalize(serialized_ifname)
        local replaced_hostname = hostname_plus_iface:gsub("_"..serialized_ifname, "")
        -- hostname don't have underscores see utils.is_valid_hostname
        replaced_hostname = replaced_hostname:gsub("_", "-")
        if #replaced_hostname < #partial_hostname then
            partial_hostname = replaced_hostname
            iface = ifname
        end
    end
    return partial_hostname, iface
end

function bat_hosts.get_bathost(mac, outgoing_iface)
	local bathosts = JSON.stringify(
		io.popen("shared-state-async get bat-hosts", "r"):read("*all") )
	local bathost = bathosts[mac:lower()]
	if bathost == nil then return end
	local hostname, iface = bat_hosts.bathost_deserialize(bathost.data)
	return { hostname = hostname, iface = iface }
end

return bat_hosts
