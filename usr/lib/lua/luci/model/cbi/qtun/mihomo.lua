return function(s, mode)

local cbi = require("luci.cbi")
local DummyValue = cbi.DummyValue
local fs = require "nixio.fs"
local uci = require("luci.model.uci").cursor()

local BASE = "/etc/qtun/config/clash"
local PROFILE_DIR = BASE .. "/mihomo"

fs.mkdirr(BASE)
fs.mkdirr(PROFILE_DIR)
fs.mkdirr(BASE .. "/active")
fs.mkdirr(BASE .. "/default")
fs.mkdirr(BASE .. "/subscriptions")

local mode_clash = { mode_selector = "clash" }

local function html_escape(str)
    str = str or ""
    str = str:gsub("&", "&amp;")
    str = str:gsub("<", "&lt;")
    str = str:gsub(">", "&gt;")
    str = str:gsub('"', "&quot;")
    return str
end

local function list_profiles()
    local profiles = {}

    if fs.access(PROFILE_DIR) then
        for file in fs.dir(PROFILE_DIR) do
            if file and file:match("%.ya?ml$") then
                profiles[#profiles + 1] = file
            end
        end
    end

    table.sort(profiles)
    return profiles
end

local active_profile = uci:get("qtun", "clash", "profile") or ""
local profiles = list_profiles()

local o = s:option(DummyValue, "_mihomo_editor", "")
o:depends(mode_clash)
o.rawhtml = true

function o.cfgvalue(self, section)
    local options = ""

    if #profiles == 0 then
        options = '<option value="">Belum ada config</option>'
    else
        for _, p in ipairs(profiles) do
            options = options .. string.format(
                '<option value="%s">%s</option>',
                html_escape(p),
                html_escape(p)
            )
        end
    end

    return string.format([[
<style>
#cbi-qtun-main-_mihomo_editor .cbi-value-title {
    display: none;
}

#cbi-qtun-main-_mihomo_editor .cbi-value-field {
    width: 100%% !important;
    margin-left: 0 !important;
}

.qtun-mihomo-box {
    max-width: 980px;
}

.qtun-info-box {
    padding: 12px;
    background: #eef7ff;
    border-left: 5px solid #2196F3;
    margin-bottom: 15px;
}

.qtun-profile-badge {
    display: inline-block;
    padding: 4px 10px;
    border-radius: 6px;
    background: #2196F3;
    color: #fff;
    font-weight: bold;
    margin-left: 6px;
}

.qtun-row {
    margin-bottom: 14px;
}

.qtun-row label {
    display: block;
    font-weight: bold;
    margin-bottom: 5px;
}

.qtun-input,
.qtun-select {
    width: 100%%;
    max-width: 520px;
}

.qtun-sub-file {
    margin-top: 8px;
}

.qtun-inline {
    display: flex;
    gap: 8px;
    align-items: center;
    flex-wrap: wrap;
}

.qtun-editor-wrap {
    display: none;
    margin-top: 15px;
}

.qtun-editor {
    width: 100%%;
    min-height: 620px;
    font-family: monospace;
    font-size: 12px;
    white-space: pre;
    overflow: auto;
    box-sizing: border-box;
}

.qtun-btn-row {
    margin-top: 12px;
    display: flex;
    gap: 10px;
    flex-wrap: wrap;
}

.qtun-status {
    margin-top: 10px;
    font-weight: bold;
}

.qtun-edit-status {
    display: inline-block;
    margin-left: 8px;
    padding: 3px 8px;
    border-radius: 5px;
    font-size: 11px;
    font-weight: bold;
}

.qtun-active {
    background: #4CAF50;
    color: #fff;
}

.qtun-inactive {
    background: #9E9E9E;
    color: #fff;
}

.qtun-danger {
    background: #f44336 !important;
    color: #fff !important;
}
</style>

<div class="qtun-mihomo-box">

    <div class="qtun-info-box">
        <b>Active Profile:</b>
        <span class="qtun-profile-badge" id="mihomo_active_profile">%s</span>
        <br>
        <small>
            Halaman ini hanya mengelola file YAML. Untuk memakai config sebagai aktif,
            pilih dari Dashboard lalu klik Set Config.
        </small>
    </div>

    <div class="qtun-row">
        <label>Pilih Aksi:</label>
        <div class="qtun-inline">
            <select id="mihomo_action_select" class="cbi-input-select qtun-select">
                <option value="sub">Subscription URL</option>
                <option value="upload">Upload File YAML</option>
                <option value="new">Create New YAML</option>
                <option value="list">List Config</option>
            </select>

            <button type="button" class="cbi-button cbi-button-neutral" onclick="qtunApplyMihomoAction()">
                Apply
            </button>
        </div>
    </div>

    <div id="mihomo_sub_wrap" class="qtun-row" style="display:none;">
        <label>Subscription URL:</label>
        <input type="text"
               id="mihomo_sub_url"
               class="cbi-input-text qtun-input"
               placeholder="https://example.com/axis.yaml">

        <div class="qtun-sub-file">
            <label>Nama File YAML:</label>
            <input type="text"
                   id="mihomo_sub_file"
                   class="cbi-input-text qtun-input"
                   placeholder="Kosongkan untuk otomatis dari URL">
        </div>

        <div class="qtun-btn-row">
            <button type="button"
                    class="cbi-button cbi-button-apply"
                    onclick="qtunSaveSubscription()">
                Save Subscription
            </button>

            <button type="button"
                    class="cbi-button cbi-button-neutral"
                    onclick="qtunUpdateSubscriptionFromForm()">
                Update Subscription
            </button>
        </div>
    </div>

    <div id="mihomo_upload_wrap" class="qtun-row" style="display:none;">
        <label>Upload File YAML:</label>

        <div class="qtun-inline">
            <input type="file"
                   id="mihomo_upload_file"
                   accept=".yaml,.yml,text/yaml,text/plain">

            <button type="button"
                    class="cbi-button cbi-button-apply"
                    onclick="qtunSaveUploadDirect()">
                Save Direct
            </button>

            <button type="button"
                    class="cbi-button cbi-button-neutral"
                    onclick="qtunLoadUploadToEditor()">
                Load To Editor
            </button>
        </div>
    </div>

    <div id="mihomo_list_wrap" class="qtun-row" style="display:none;">
        <label>Config List:</label>
        <div class="qtun-inline">
            <select id="mihomo_profile_select" class="cbi-input-select qtun-select">
                %s
            </select>

            <button type="button"
                    class="cbi-button cbi-button-neutral"
                    onclick="qtunEditSelectedMihomoProfile()">
                Edit
            </button>

            <button type="button"
                    class="cbi-button qtun-danger"
                    onclick="qtunDeleteSelectedMihomoProfile()">
                Delete
            </button>

            <span id="mihomo_edit_status" class="qtun-edit-status qtun-inactive">INACTIVE</span>
        </div>
    </div>

    <div id="mihomo_editor_wrap" class="qtun-editor-wrap">
        <div class="qtun-row">
            <label>Nama File YAML:</label>
            <input type="text"
                   id="mihomo_profile_name"
                   class="cbi-input-text qtun-input"
                   placeholder="axis.yaml">
        </div>

        <div class="qtun-row">
            <label>Isi YAML Config:</label>
            <textarea id="mihomo_yaml_editor" class="qtun-editor"></textarea>
        </div>

        <div class="qtun-btn-row">
            <button type="button"
                    class="cbi-button cbi-button-apply"
                    onclick="qtunSaveMihomoProfile()">
                Save YAML
            </button>

            <button type="button"
                    class="cbi-button cbi-button-reset"
                    onclick="qtunCloseMihomoEditor()">
                Close Editor
            </button>
        </div>
    </div>

    <div id="mihomo_editor_status" class="qtun-status"></div>

</div>

<script type="text/javascript">
var QTUN_ACTIVE_MIHOMO_PROFILE = "%s";

function qtunSetMihomoStatus(msg, ok) {
    var el = document.getElementById("mihomo_editor_status");
    if (!el) return;
    el.style.color = ok ? "green" : "red";
    el.innerHTML = msg;
}

function qtunUpdateEditStatus(name) {
    var st = document.getElementById("mihomo_edit_status");
    if (!st) return;

    if (name && name === QTUN_ACTIVE_MIHOMO_PROFILE) {
        st.innerHTML = "ACTIVE";
        st.className = "qtun-edit-status qtun-active";
    } else {
        st.innerHTML = "INACTIVE";
        st.className = "qtun-edit-status qtun-inactive";
    }
}

function qtunShowEditor() {
    document.getElementById("mihomo_editor_wrap").style.display = "block";
}

function qtunCloseMihomoEditor() {
    document.getElementById("mihomo_editor_wrap").style.display = "none";
}

function qtunHideAllMihomoPanels() {
    document.getElementById("mihomo_sub_wrap").style.display = "none";
    document.getElementById("mihomo_upload_wrap").style.display = "none";
    document.getElementById("mihomo_list_wrap").style.display = "none";
}

function qtunApplyMihomoAction() {
    var action = document.getElementById("mihomo_action_select").value;

    qtunHideAllMihomoPanels();
    qtunCloseMihomoEditor();

    if (action === "sub") {
        document.getElementById("mihomo_sub_wrap").style.display = "block";
        qtunSetMihomoStatus("Masukkan Subscription URL. Nama file boleh dikosongkan agar otomatis dari URL.", true);
        return;
    }

    if (action === "upload") {
        document.getElementById("mihomo_upload_wrap").style.display = "block";
        qtunSetMihomoStatus("Pilih file YAML, lalu pilih Save Direct atau Load To Editor.", true);
        return;
    }

    if (action === "list") {
        document.getElementById("mihomo_list_wrap").style.display = "block";

        var sel = document.getElementById("mihomo_profile_select");
        if (sel) qtunUpdateEditStatus(sel.value || "");

        qtunSetMihomoStatus("Pilih config lalu klik Edit, Update Sub, atau Delete.", true);
        return;
    }

    if (action === "new") {
        document.getElementById("mihomo_profile_name").value = "new.yaml";
        document.getElementById("mihomo_yaml_editor").value =
"proxies:\\n" +
"  - name: Example\\n" +
"    type: direct\\n\\n" +
"proxy-groups:\\n" +
"  - name: SELECT\\n" +
"    type: select\\n" +
"    proxies:\\n" +
"      - Example\\n" +
"      - DIRECT\\n\\n" +
"rules:\\n" +
"  - MATCH,SELECT\\n";

        qtunUpdateEditStatus("new.yaml");
        qtunShowEditor();
        qtunSetMihomoStatus("Template new.yaml dibuat. Edit lalu klik Save YAML.", true);
    }
}

function qtunEditSelectedMihomoProfile() {
    var sel = document.getElementById("mihomo_profile_select");
    var name = sel.value || "";

    if (!name) {
        qtunSetMihomoStatus("Belum ada config untuk diedit.", false);
        return;
    }

    document.getElementById("mihomo_profile_name").value = name;
    qtunUpdateEditStatus(name);

    XHR.get("%s", { file: name }, function(x, data) {
        if (data && data.success) {
            document.getElementById("mihomo_yaml_editor").value = data.content || "";
            qtunShowEditor();
            qtunSetMihomoStatus("Editing: " + name, true);
        } else {
            qtunSetMihomoStatus((data && data.message) ? data.message : "Gagal load config.", false);
        }
    });
}

function qtunSaveMihomoProfile() {
    var name = document.getElementById("mihomo_profile_name").value || "";
    var content = document.getElementById("mihomo_yaml_editor").value || "";

    if (!name) {
        qtunSetMihomoStatus("Nama file kosong.", false);
        return;
    }

    XHR.post("%s", {
        file: name,
        content: content
    }, function(x, data) {
        if (data && data.success) {
            qtunSetMihomoStatus("Saved: " + data.file + ". Refresh halaman untuk update Config List.", true);
            qtunUpdateEditStatus(data.file);
        } else {
            qtunSetMihomoStatus((data && data.message) ? data.message : "Gagal save config.", false);
        }
    });
}

function qtunDeleteSelectedMihomoProfile() {
    var sel = document.getElementById("mihomo_profile_select");
    var name = sel.value || "";

    if (!name) {
        qtunSetMihomoStatus("Tidak ada config yang dipilih.", false);
        return;
    }

    if (name === QTUN_ACTIVE_MIHOMO_PROFILE) {
        qtunSetMihomoStatus("Tidak boleh delete config yang sedang ACTIVE. Ganti active config dari Dashboard dulu.", false);
        return;
    }

    if (!confirm("Delete config " + name + "?")) return;

    XHR.post("%s", { file: name }, function(x, data) {
        if (data && data.success) {
            qtunSetMihomoStatus("Deleted: " + name + ". Refresh halaman untuk update Config List.", true);
        } else {
            qtunSetMihomoStatus((data && data.message) ? data.message : "Gagal delete config.", false);
        }
    });
}

function qtunSaveUploadDirect() {
    var input = document.getElementById("mihomo_upload_file");

    if (!input || !input.files || !input.files[0]) {
        qtunSetMihomoStatus("Pilih file YAML dulu.", false);
        return;
    }

    var f = input.files[0];
    var reader = new FileReader();

    reader.onload = function(e) {
        XHR.post("%s", {
            file: f.name,
            content: e.target.result || ""
        }, function(x, data) {
            if (data && data.success) {
                qtunSetMihomoStatus("Upload berhasil disimpan sebagai: " + data.file + ". Refresh halaman untuk update Config List.", true);
            } else {
                qtunSetMihomoStatus((data && data.message) ? data.message : "Gagal menyimpan file.", false);
            }
        });
    };

    reader.readAsText(f);
}

function qtunLoadUploadToEditor() {
    var input = document.getElementById("mihomo_upload_file");

    if (!input || !input.files || !input.files[0]) {
        qtunSetMihomoStatus("Pilih file YAML dulu.", false);
        return;
    }

    var f = input.files[0];
    var reader = new FileReader();

    reader.onload = function(e) {
        document.getElementById("mihomo_profile_name").value = f.name;
        document.getElementById("mihomo_yaml_editor").value = e.target.result || "";
        qtunUpdateEditStatus(f.name);
        qtunShowEditor();
        qtunSetMihomoStatus("Upload dimuat ke editor: " + f.name + ". Klik Save YAML untuk menyimpan.", true);
    };

    reader.readAsText(f);
}

function qtunSaveSubscription() {
    var url = document.getElementById("mihomo_sub_url").value || "";
    var file = document.getElementById("mihomo_sub_file").value || "";

    if (!url) {
        qtunSetMihomoStatus("Subscription URL kosong.", false);
        return;
    }

    qtunSetMihomoStatus("Downloading subscription...", true);

    XHR.post("%s", {
        url: url,
        file: file
    }, function(x, data) {
        if (data && data.success) {
            qtunSetMihomoStatus("Subscription saved: " + data.file + ". Refresh halaman untuk update Config List.", true);
        } else {
            qtunSetMihomoStatus((data && data.message) ? data.message : "Gagal menyimpan subscription.", false);
        }
    });
}

function qtunUpdateSubscriptionFromForm() {
    var file = document.getElementById("mihomo_sub_file").value || "";

    if (!file) {
        qtunSetMihomoStatus("Isi Nama File YAML terlebih dahulu.", false);
        return;
    }

    qtunSetMihomoStatus("Updating subscription...", true);

    XHR.post("%s", {
        file: file
    }, function(x, data) {
        if (data && data.success) {
            qtunSetMihomoStatus(
                "Updated: " + data.file,
                true
            );
        } else {
            qtunSetMihomoStatus(
                (data && data.message) ?
                data.message :
                "Gagal update subscription.",
                false
            );
        }
    });
}

function qtunUpdateSelectedSubscription() {
    var sel = document.getElementById("mihomo_profile_select");
    var name = sel.value || "";

    if (!name) {
        qtunSetMihomoStatus("Tidak ada config yang dipilih.", false);
        return;
    }

    qtunSetMihomoStatus("Updating subscription: " + name + "...", true);

    XHR.post("%s", {
        file: name
    }, function(x, data) {
        if (data && data.success) {
            qtunSetMihomoStatus("Updated: " + data.file + " dari subscription URL.", true);
        } else {
            qtunSetMihomoStatus((data && data.message) ? data.message : "Gagal update subscription.", false);
        }
    });
}

document.addEventListener("DOMContentLoaded", function() {
    qtunApplyMihomoAction();
});
</script>
]],
    html_escape(active_profile ~= "" and active_profile or "Belum dipilih"),
    options,
    html_escape(active_profile),
    luci.dispatcher.build_url("admin/services/qtun/clash_profile_get"),
    luci.dispatcher.build_url("admin/services/qtun/clash_profile_save"),
    luci.dispatcher.build_url("admin/services/qtun/clash_profile_delete"),
    luci.dispatcher.build_url("admin/services/qtun/clash_profile_save"),
    luci.dispatcher.build_url("admin/services/qtun/clash_sub_save"),
    luci.dispatcher.build_url("admin/services/qtun/clash_sub_update"),
    luci.dispatcher.build_url("admin/services/qtun/clash_sub_update"))
end

end