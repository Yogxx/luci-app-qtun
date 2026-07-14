return function(s, mode_selector) 

local cbi = require("luci.cbi")
local Value = cbi.Value
local Flag = cbi.Flag
local TextValue = cbi.TextValue

local fs = require "nixio.fs"
local json = require "luci.jsonc"

-- Path penyimpanan file konfigurasi internal SSH
local base_dir = "/etc/qtun/config/ssh"
local path = base_dir .. "/config.json"

-- Muat data konfigurasi yang sudah ada jika tersedia
local sshcfg = {}
if fs.access(path) then
    sshcfg = json.parse(fs.readfile(path)) or {}
end

-- =========================================================
-- HTTP PROXY OPTION
-- =========================================================

-- Enable HTTP Proxy
local eh = s:option(Flag, "ssh_http_enable", "Enable HTTP Proxy")
eh:depends("mode_selector", "ssh")
eh.default = (sshcfg.http_proxy and sshcfg.http_proxy.enable == true) and "1" or "0"
eh.rmempty = false
eh.write = function() end

-- Proxy IP
local pip = s:option(Value, "ssh_proxy_ip", "Proxy IP")
pip:depends({mode_selector = "ssh", ssh_http_enable = "1"})
pip.placeholder = "192.168.1.1"
pip.datatype = "ipaddr"
pip.default = (sshcfg.http_proxy and sshcfg.http_proxy.ip) or ""
pip.write = function() end

-- Proxy Port
local pport = s:option(Value, "ssh_proxy_port", "Proxy Port")
pport:depends({mode_selector = "ssh", ssh_http_enable = "1"})
pport.datatype = "port"
pport.default = (sshcfg.http_proxy and sshcfg.http_proxy.port) or ""
pport.write = function() end

-- Payload (WAJIB TextValue, bukan Value)
local pay = s:option(TextValue, "ssh_payload", "Payload")
pay:depends({mode_selector = "ssh", ssh_http_enable = "1"})
pay.rows = 5
pay.wrap = "off"
pay.default = (sshcfg.http_proxy and sshcfg.http_proxy.payload) or "CONNECT [host_port] HTTP/1.1\\r\\nHost: [host_port]\\r\\n\\r\\n"
pay.write = function() end

-- =========================================================
-- BASIC SSH ACCOUNT Settings
-- =========================================================

-- Server Host
local host = s:option(Value, "ssh_host", "Server Host")
host:depends("mode_selector", "ssh")
host.datatype = "host"
host.default = sshcfg.host or ""
host.write = function() end
host.remove = function() end

-- Port
local port = s:option(Value, "ssh_port", "Server Port")
port:depends("mode_selector", "ssh")
port.datatype = "port"
port.default = sshcfg.port or "22"
port.write = function() end

-- Username
local user = s:option(Value, "ssh_user", "Username")
user:depends("mode_selector", "ssh")
user.write = function() end
user.default = sshcfg.username or ""

-- Password
local pass = s:option(Value, "ssh_pass", "Password")
pass:depends("mode_selector", "ssh")
pass.password = true
pass.write = function() end
pass.default = sshcfg.password or ""

-- UDPGW
local udpgw = s:option(Value, "ssh_udpgw", "UDPGW Port")
udpgw:depends("mode_selector", "ssh")
udpgw.datatype = "port"
udpgw.default = sshcfg.udpgw_port or "7300"
udpgw.write = function() end

-- =========================================================
-- SAVE & EXPORT HOOK OVERRIDE (Ekspor JSON Mandiri)
-- =========================================================

local old_parse = s.parse

function s.parse(self, ...)
    -- Ambil status selektor tab dari dashboard/config utama
    local current_mode = mode_selector:formvalue("main")
    
    if current_mode == "ssh" then
        -- Kumpulkan data form
        local is_proxy_enabled = (eh:formvalue("main") == "1")
        local p_ip = pip:formvalue("main") or ""
        local p_port = pport:formvalue("main") or ""
        local p_payload = pay:formvalue("main") or ""

        local s_host = host:formvalue("main") or ""
        local s_port = port:formvalue("main") or "22"
        local s_user = user:formvalue("main") or ""
        local s_pass = pass:formvalue("main") or ""
        local s_udpgw = udpgw:formvalue("main") or "7300"

        -- Konversi ke struktur JSON string yang rapi
        local json_data = string.format([[{
  "host": %q,
  "port": %q,
  "username": %q,
  "password": %q,
  "udpgw_port": %q,
  "http_proxy": {
    "enable": %s,
    "ip": %q,
    "port": %q,
    "payload": %q
  },
  "socks5": {
    "listen": "127.0.0.1:1080"
  }
}]],
            s_host, s_port, s_user, s_pass, s_udpgw,
            is_proxy_enabled and "true" or "false", p_ip, p_port, p_payload
        )

        -- Amankan folder target dan tulis filenya
        fs.mkdirr(base_dir)
        fs.writefile(path, json_data)
    end

    -- Jalankan parser bawaan
    old_parse(self, ...)
end

end