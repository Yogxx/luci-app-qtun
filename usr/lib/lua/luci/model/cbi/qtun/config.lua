m = Map("qtun", "QTUN - Tunnel Configuration")

m.description = [[
<style type="text/css">
    @media screen and (max-width: 600px) {
        .cbi-value { display: flex !important; flex-direction: column !important; }
        .cbi-value-title { width: 100% !important; text-align: left !important; }
        .cbi-value-field { width: 100% !important; margin: 0 !important; }
    }
</style>
<div style="padding: 10px; background: #fff3cd; border-left: 5px solid #ffecb5; color: #856404; margin-bottom: 15px;">
    <strong>Info:</strong> Untuk mengedit config silakan pilih dulu <strong>Config Mode</strong> config yang mana yang akan di edit.
</div>
]]

s = m:section(NamedSection, "main", "global", "Edit Konfigurasi")
s.addremove = false

-- Dropdown Mode (Hanya sebagai pengalih tampilan)
mode = s:option(ListValue, "mode_selector", "Config Mode")
mode:value("ssh", "SSH Direct")
mode:value("q-ssh","Q SSH(proxy,payload)")
mode:value("clash", "Clash / Mihomo")
mode:value("zivpn", "ZiVPN (UDP)")

-- Ambil mode aktif dari sistem hanya untuk dijadikan DEFAULT tampilan saat buka halaman
local active_mode = m.uci:get("qtun", "main", "mode") or "zivpn"
mode.default = active_mode

-- PENTING: Agar dropdown ini tidak tersimpan ke /etc/config/qtun
-- kita buat agar dia tidak menulis (non-persistent)
function mode.write() return end

-- Memuat sub-module
dofile("/usr/lib/lua/luci/model/cbi/qtun/ssh.lua")(s, mode)
dofile("/usr/lib/lua/luci/model/cbi/qtun/mihomo.lua")(s, mode)
dofile("/usr/lib/lua/luci/model/cbi/qtun/zivpn.lua")(s, mode)
dofile("/usr/lib/lua/luci/model/cbi/qtun/q-ssh.lua")(s, mode)

return m