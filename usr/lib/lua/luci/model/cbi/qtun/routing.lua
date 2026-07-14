return function(s, mode_selector)

    local cbi = require("luci.cbi")
    local ListValue = cbi.ListValue

    -- =========================================================
    -- GLOBAL ROUTING OPTION (TUN vs REDIRECT)
    -- =========================================================

    -- Dropdown untuk memilih mode pengalihan trafik global di GUI
    local route_mode = s:option(ListValue, "clash_mode", "Routing Mode")
    route_mode:value("tun", "TUN Mode (Auto Route/Native)")
    route_mode:value("redirect", "NAT REDIRECT Mode (iptables)")
    route_mode.default = "tun"
    
    -- Tampilkan opsi ini jika user memilih "Clash / Mihomo" di Config Mode
    route_mode:depends("mode_selector", "clash")

    -- =========================================================
    -- OVERRIDE SAVE HOOK UNTUK GLOBAL CORE CONFIG
    -- =========================================================
    -- Mencegat hook parser bawaan LuCI saat tombol 'Save & Apply' ditekan.
    -- Langkah ini memastikan penulisan variabel ke /etc/config/qtun 
    -- terisi secara presisi dan ringkas sesuai arsitektur QTUN.

    local old_parse = s.parse
    function s.parse(self, ...)
        -- Membaca status pilihan terakhir dari form dropdown di config.lua
        local current_mode = mode_selector:formvalue("main")
        
        if current_mode == "clash" then
            local chosen_route = route_mode:formvalue("main") or "tun"
            
            -- Tulis struktur parameter secara bersih dan efisien ke UCI
            s.map.uci:set("qtun", "main", "mode", "clash")
            s.map.uci:set("qtun", "main", "backend", "clash")
            s.map.uci:set("qtun", "main", "clash_mode", chosen_route)
        
        elseif current_mode == "zivpn" then
            s.map.uci:set("qtun", "main", "mode", "zivpn")
            -- Catatan: ZiVPN tidak memanfaatkan backend atau clash_mode, 
            -- biarkan variabel lama dihapus atau di-ignore agar config tetap minimalis.
            s.map.uci:delete("qtun", "main", "backend")
            s.map.uci:delete("qtun", "main", "clash_mode")

        elseif current_mode == "ssh" then
            -- Kerangka awal untuk persiapan mode SSH multi-worker
            s.map.uci:set("qtun", "main", "mode", "ssh")
            s.map.uci:set("qtun", "main", "backend", "clash") -- Default aggregator backend
        end

        -- Lanjutkan proses parsing standar LuCI
        old_parse(self, ...)
    end

end