return function(s, mode_selector) 

    local cbi = require("luci.cbi")
    local Value = cbi.Value

    local fs = require "nixio.fs"
    local json = require "luci.jsonc"

    -- Path baru
    local base_dir = "/etc/qtun/config/q-ssh"
    local path = base_dir .. "/config.json"

    -- Load existing config
    local cfg = {}
    if fs.access(path) then
        cfg = json.parse(fs.readfile(path)) or {}
    end

    cfg.ssh = cfg.ssh or {}
    cfg.concurrency = cfg.concurrency or {}
    cfg.proxy = cfg.proxy or {}
    cfg.payload = cfg.payload or {}

    ----------------------------------------------------------
    -- 1. MENGIKAT FIELD UTAMA (SSH Account)
    ----------------------------------------------------------
    local host = s.fields["server"] or s.fields["host"] or s.fields["ssh_host"]
    local port = s.fields["port"] or s.fields["ssh_port"]
    local user = s.fields["username"] or s.fields["ssh_user"]
    local pass = s.fields["password"] or s.fields["ssh_pass"]

    if host then
        host.default = cfg.ssh.host or ""
        host:depends("mode_selector", "q-ssh")
    end
    if port then
        port.default = cfg.ssh.port or "80"
        port:depends("mode_selector", "q-ssh")
    end
    if user then
        user.default = cfg.ssh.username or ""
        user:depends("mode_selector", "q-ssh")
    end
    if pass then
        pass.default = cfg.ssh.password or ""
        pass:depends("mode_selector", "q-ssh")
    end

    ----------------------------------------------------------
    -- 2. DEFINISI FORM TAMBAHAN (Workers, Proxy & Payload)
    ----------------------------------------------------------
    -- Workers (Bisa disesuaikan user)
    local workers = s:option(Value, "workers", "Workers")
    workers.datatype = "uinteger"
    workers.default = cfg.concurrency.workers or "2"
    workers:depends("mode_selector", "q-ssh")
    workers.write = function() end

    -- Proxy
    local proxy_host = s:option(Value, "proxy_host", "Proxy Host")
    proxy_host.default = cfg.proxy.host or ""
    proxy_host:depends("mode_selector", "q-ssh")
    proxy_host.write = function() end

    local proxy_port = s:option(Value, "proxy_port", "Proxy Port")
    proxy_port.datatype = "port"
    proxy_port.default = cfg.proxy.port or "80"
    proxy_port:depends("mode_selector", "q-ssh")
    proxy_port.write = function() end

    -- Payload
    local payload = s:option(Value, "payload", "Payload Request")
    payload.template = "cbi/tvalue"
    payload.rows = 6
    payload.default = cfg.payload.request or ""
    payload:depends("mode_selector", "q-ssh")
    payload.write = function() end

    local expect = s:option(Value, "expect", "Expect Status")
    expect.default = table.concat(cfg.payload.expect or {"200","101"}, ",")
    expect:depends("mode_selector", "q-ssh")
    expect.write = function() end

    ----------------------------------------------------------
    -- 3. SAVE HOOK
    ----------------------------------------------------------
    local old_parse = s.parse

    function s.parse(self, ...)
        local current_mode = mode_selector:formvalue("main")
        
        if current_mode == "q-ssh" then
            local val_host = host and host:formvalue("main") or ""
            local val_port = port and tonumber(port:formvalue("main")) or 80
            local val_user = user and user:formvalue("main") or ""
            local val_pass = pass and pass:formvalue("main") or ""

            -- Memecah data expect ke format elemen array JSON string
            local expect_tbl = {}
            local exp = expect:formvalue("main") or "200,101"
            for v in exp:gmatch("[^,%s]+") do
                expect_tbl[#expect_tbl+1] = '"' .. v .. '"'
            end
            local expect_json = "[" .. table.concat(expect_tbl, ", ") .. "]"

            local json_data = string.format([[
{
  "listen": {
    "host": "127.0.0.1",
    "port": 1080
  },
  "concurrency": {
    "enable": true,
    "workers": %d,
    "start_port": 1080
  },
  "ssh": {
    "host": %q,
    "port": %d,
    "username": %q,
    "password": %q
  },
  "network": {
    "type": "tcp"
  },
  "transport": {
    "tls": false,
    "host": "",
    "path": "/",
    "sni": ""
  },
  "proxy": {
    "enable": true,
    "host": %q,
    "port": %d
  },
  "payload": {
    "enable": true,
    "request": %s,
    "expect": %s
  }
}
]],
                tonumber(workers:formvalue("main")) or 2, -- Memasukkan nilai workers dinamis
                val_host,
                val_port,
                val_user,
                val_pass,
                proxy_host:formvalue("main") or "",
                tonumber(proxy_port:formvalue("main")) or 80,
                string.format("%q", payload:formvalue("main") or ""),
                expect_json
            )

            -- Bersihkan escape berlebih (\/) pada string payload
            json_data = json_data:gsub("\\/", "/")

            fs.mkdirr(base_dir)
            fs.writefile(path, json_data)
        end

        old_parse(self, ...)
    end

end