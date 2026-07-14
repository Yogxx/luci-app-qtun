return function(s)

local cbi = require("luci.cbi")
local Value = cbi.Value
local Flag = cbi.Flag
local ListValue = cbi.ListValue
local FileUpload = cbi.FileUpload

-- Variabel bantu dependensi utama
local mode_clash = {mode = "clash"}

-- 1. PILIHAN INPUT MODE
local im = s:option(ListValue, "input_mode", "Mihomo Config Mode")
im:depends(mode_clash)
im:value("sub", "Subscription URL")
im:value("file", "Upload Local YAML")
im:value("manual", "Manual Proxy (Trojan/Vmess/Vless)")
im.default = "sub"

-- 2. JIKA MODE SUBSCRIPTION & FILE (Sama seperti sebelumnya)
local sub = s:option(Value, "sub_url", "Subscription URL")
sub:depends({mode = "clash", input_mode = "sub"})

local fu = s:option(FileUpload, "config_file", "Upload YAML Config")
fu:depends({mode = "clash", input_mode = "file"})
fu.dest = "/etc/qtun/mihomo.yaml"

-- 3. JIKA MODE MANUAL
local pt = s:option(ListValue, "protocol", "Protocol")
pt:depends({mode = "clash", input_mode = "manual"})
pt:value("vmess", "Vmess")
pt:value("vless", "Vless")
pt:value("trojan", "Trojan")

local srv = s:option(Value, "server", "Server Address")
srv:depends({mode = "clash", input_mode = "manual"})

local prt = s:option(Value, "port", "Port")
prt:depends({mode = "clash", input_mode = "manual"})
prt.default = "443"

-- --- KONDISI UUID vs PASSWORD ---
local uuid = s:option(Value, "uuid", "UUID")
uuid:depends({mode = "clash", input_mode = "manual", protocol = "vmess"})
uuid:depends({mode = "clash", input_mode = "manual", protocol = "vless"})

local pass = s:option(Value, "password", "Password")
pass:depends({mode = "clash", input_mode = "manual", protocol = "trojan"})
pass.password = true

-- --- PEMISAHAN SERVERNAME (VMESS/VLESS) DAN SNI (TROJAN) ---

-- Servername untuk Vmess & Vless
local sn = s:option(Value, "servername", "Servername")
sn:depends({mode = "clash", input_mode = "manual", protocol = "vmess"})
sn:depends({mode = "clash", input_mode = "manual", protocol = "vless"})
sn.placeholder = "m.facebook.com"

-- SNI untuk Trojan
local sni = s:option(Value, "sni", "SNI")
sni:depends({mode = "clash", input_mode = "manual", protocol = "trojan"})
sni.placeholder = "m.facebook.com"

-- ----------------------------------------------------------

-- Transport (WS/GRPC/TCP)
local net = s:option(ListValue, "transport", "Transport")
net:depends({mode = "clash", input_mode = "manual"})
net:value("ws", "WebSocket")
net:value("grpc", "gRPC")
net:value("tcp", "TCP")
net.default = "ws"

-- Path / Service Name
local path = s:option(Value, "path", "Path / Service Name")
path:depends({mode = "clash", input_mode = "manual", transport = "ws"})
path:depends({mode = "clash", input_mode = "manual", transport = "grpc"})

-- TLS Flag
local tls = s:option(Flag, "tls", "Enable TLS")
tls:depends({mode = "clash", input_mode = "manual"})
tls.default = "1"
tls.rmempty = false

-- AlterID (Khusus Vmess)
local aid = s:option(Value, "alterid", "AlterID")
aid:depends({mode = "clash", input_mode = "manual", protocol = "vmess"})
aid.default = "0"

end