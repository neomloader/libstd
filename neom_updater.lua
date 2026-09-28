local M = {}

local has_json, json = pcall(require, "cjson.safe")
if not has_json or not json then
    local ok, mod = pcall(require, "cjson")
    json = ok and mod or nil
end
local sha256 = require("sha256")
local has_lfs, lfs = pcall(require, "lfs")

local has_ssl, https = pcall(require, "ssl.https")
local has_http, http = pcall(require, "socket.http")
local ltn12 = require("ltn12")
local has_mimgui, mimgui = pcall(require, "mimgui")

local function u8(s)
    if not s or type(s) ~= "string" then return s end
    local is_utf8, has_high, len, i = true, false, #s, 1
    while i <= len do
        local b = string.byte(s, i)
        if b >= 128 then
            has_high = true
            if b >= 192 and b <= 223 then
                if i + 1 > len or string.byte(s, i + 1) < 128 or string.byte(s, i + 1) > 191 then is_utf8 = false; break end
                i = i + 2
            elseif b >= 224 and b <= 239 then
                if i + 2 > len or string.byte(s, i + 1) < 128 or string.byte(s, i + 1) > 191 or string.byte(s, i + 2) < 128 or string.byte(s, i + 2) > 191 then is_utf8 = false; break end
                i = i + 3
            elseif b >= 240 and b <= 247 then
                if i + 3 > len or string.byte(s, i + 1) < 128 or string.byte(s, i + 1) > 191 or string.byte(s, i + 2) < 128 or string.byte(s, i + 2) > 191 or string.byte(s, i + 3) < 128 or string.byte(s, i + 3) > 191 then is_utf8 = false; break end
                i = i + 4
            else
                is_utf8 = false; break
            end
        else
            i = i + 1
        end
    end
    if is_utf8 and has_high then return s end
    local ok, enc = pcall(require, "encoding")
    if ok and enc and enc.UTF8 then return enc.UTF8(s) end
    return s
end

M.CURRENT_VERSION = "1.0.12"
M.CURRENT_BUILD = 112
M.CURRENT_LIBSTD_VERSION = "1.0.2"
if __neom_build and type(__neom_build) == "number" then
    M.CURRENT_BUILD = __neom_build
end
if __neom_version and type(__neom_version) == "string" then
    M.CURRENT_VERSION = __neom_version
end

M.MANIFEST_URL = "https://raw.githubusercontent.com/JustInPaper/neomloader-bin/main/manifest.json"

M.PACKAGE_NAME = "com.arizonagames.arizona.web"
M.DATA_DIR = "/storage/emulated/0/Android/data/" .. M.PACKAGE_NAME .. "/"
M.TARGET_BINARY_PATH = M.DATA_DIR .. "libNeoMLoader.so"
M.BACKUP_BINARY_PATH = M.DATA_DIR .. "libNeoMLoader.so.bak"
M.CANARY_FLAG_PATH = M.DATA_DIR .. "update_booting.flag"
M.LIBSTD_DIR = "/sdcard/Android/media/" .. M.PACKAGE_NAME .. "/neomloader/lib/"

M.STATE_IDLE = 0
M.STATE_CHECKING = 1
M.STATE_AVAILABLE = 2
M.STATE_DOWNLOADING = 3
M.STATE_VERIFYING = 4
M.STATE_COMPLETED = 5
M.STATE_ERROR = 6

M.state = M.STATE_IDLE
M.status_message = "Готов к проверке"
M.progress = 0.0
M.remote_manifest = nil
M.show_ui = false
M.has_binary_update = false
M.has_libstd_update = false

local function log_msg(msg)
    if print then
        print("[NeoMUpdater] " .. tostring(msg))
    end
end

do
    local f = io.open(M.CANARY_FLAG_PATH, "r")
    if f then
        f:close()
        os.remove(M.CANARY_FLAG_PATH)
        log_msg("Успешный запуск после обновления. Флаг canary очищен: " .. M.CANARY_FLAG_PATH)
    end
end

local function http_get(url)
    local response_body = {}
    local client = url:match("^https") and https or http
    if not client then
        return nil, "HTTP клиент недоступен"
    end

    local res, code, headers, status = client.request({
        url = url,
        method = "GET",
        headers = {
            ["User-Agent"] = "NeoMLoader-Updater/" .. M.CURRENT_VERSION,
            ["Accept"] = "*/*",
        },
        sink = ltn12.sink.table(response_body),
    })

    if res and (code == 200 or code == 302 or code == 301) then
        return table.concat(response_body)
    end
    return nil, string.format("Ошибка HTTP запроса: код %s, статус %s", tostring(code), tostring(status))
end

local function download_file(url, target_path, on_progress)
    local client = url:match("^https") and https or http
    if not client then
        return false, "HTTP клиент недоступен"
    end

    local f, err = io.open(target_path, "wb")
    if not f then
        return false, "Не удалось открыть файл для записи: " .. tostring(err)
    end

    local total_bytes = 0
    local downloaded_bytes = 0

    local custom_sink = function(chunk, src_err)
        if chunk and #chunk > 0 then
            f:write(chunk)
            downloaded_bytes = downloaded_bytes + #chunk
            if on_progress then
                on_progress(downloaded_bytes, total_bytes)
            end
        end
        return 1
    end

    local res, code, headers = client.request({
        url = url,
        method = "GET",
        headers = {
            ["User-Agent"] = "NeoMLoader-Updater/" .. M.CURRENT_VERSION,
        },
        sink = custom_sink,
    })

    f:close()

    if res and (code == 200 or code == 302 or code == 301) then
        return true
    else
        os.remove(target_path)
        return false, string.format("Ошибка загрузки: HTTP код %s", tostring(code))
    end
end

function M.check_update_coroutine(callback)
    M.state = M.STATE_CHECKING
    M.status_message = "Проверка наличия обновлений на сервере..."
    log_msg("Запрос манифеста: " .. M.MANIFEST_URL)

    local manifest_str, err = http_get(M.MANIFEST_URL)
    if not manifest_str then
        M.state = M.STATE_ERROR
        M.status_message = "Не удалось получить манифест: " .. tostring(err)
        log_msg(M.status_message)
        if callback then callback(false, err) end
        return
    end

    local manifest = json.decode(manifest_str)
    if not manifest or not manifest.version then
        M.state = M.STATE_ERROR
        M.status_message = "Получен некорректный манифест"
        log_msg(M.status_message)
        if callback then callback(false, "Некорректный манифест") end
        return
    end

    M.remote_manifest = manifest
    local remote_build = tonumber(manifest.build_number) or 0
    local remote_ver = manifest.version

    M.has_binary_update = (remote_build > M.CURRENT_BUILD) or (remote_build == 0 and remote_ver ~= M.CURRENT_VERSION)
    M.has_libstd_update = false
    if manifest.libstd and manifest.libstd.version and manifest.libstd.version ~= M.CURRENT_LIBSTD_VERSION then
        M.has_libstd_update = true
    end

    if M.has_binary_update or M.has_libstd_update then
        M.state = M.STATE_AVAILABLE
        M.status_message = string.format("Доступна новая версия: v%s (сборка %s)", remote_ver, tostring(remote_build))
        M.show_ui = true
        log_msg(M.status_message)
        if callback then callback(true, manifest) end
    else
        M.state = M.STATE_IDLE
        M.status_message = "Все компоненты NeoMLoader актуальны (v" .. M.CURRENT_VERSION .. ")"
        log_msg(M.status_message)
        if callback then callback(false, "Обновлений не требуется") end
    end
end

function M.apply_all_updates_coroutine(callback)
    if not M.remote_manifest then
        M.state = M.STATE_ERROR
        M.status_message = "Отсутствует манифест обновления"
        if callback then callback(false, M.status_message) end
        return
    end

    if M.has_binary_update and M.remote_manifest.binary then
        local bin_info = M.remote_manifest.binary
        local bin_url = bin_info.url
        local expected_sha = bin_info.sha256
        local expected_size = bin_info.size

        local tmp_path = M.TARGET_BINARY_PATH .. ".tmp"
        local target_path = M.TARGET_BINARY_PATH

        M.state = M.STATE_DOWNLOADING
        M.status_message = "Загрузка ядра libNeoMLoader.so..."
        M.progress = 0.0

        log_msg("Загрузка ядра из: " .. bin_url)

        local success, err = download_file(bin_url, tmp_path, function(downloaded, total)
            if expected_size and expected_size > 0 then
                M.progress = (downloaded / expected_size) * 0.5
            else
                M.progress = 0.25
            end
        end)

        if not success then
            M.state = M.STATE_ERROR
            M.status_message = "Ошибка при загрузке ядра: " .. tostring(err)
            log_msg(M.status_message)
            if callback then callback(false, err) end
            return
        end

        M.state = M.STATE_VERIFYING
        M.status_message = "Проверка контрольной суммы ядра..."

        local computed_sha = sha256.file(tmp_path)
        if expected_sha and #expected_sha > 0 and computed_sha ~= expected_sha then
            os.remove(tmp_path)
            M.state = M.STATE_ERROR
            M.status_message = string.format("Несовпадение SHA256 ядра! Ожидалось: %s, получено: %s", expected_sha, computed_sha)
            log_msg(M.status_message)
            if callback then callback(false, "Ошибка SHA256") end
            return
        end

        local cur_in = io.open(target_path, "rb")
        if cur_in then
            local cur_data = cur_in:read("*a")
            cur_in:close()
            if cur_data and #cur_data > 1024 then
                local bak_out = io.open(M.BACKUP_BINARY_PATH, "wb")
                if bak_out then
                    bak_out:write(cur_data)
                    bak_out:close()
                    log_msg("Создана резервная копия: " .. M.BACKUP_BINARY_PATH)
                end
            end
        end

        local flag_out = io.open(M.CANARY_FLAG_PATH, "w")
        if flag_out then
            flag_out:write(os.date("!%Y-%m-%dT%H:%M:%SZ\n"))
            flag_out:close()
            log_msg("Установлен canary-флаг: " .. M.CANARY_FLAG_PATH)
        end

        M.status_message = "Установка обновлённого ядра..."
        local renamed, rename_err = os.rename(tmp_path, target_path)
        if not renamed then
            os.remove(target_path)
            renamed, rename_err = os.rename(tmp_path, target_path)
        end

        if not renamed then
            M.state = M.STATE_ERROR
            M.status_message = "Ошибка замены бинарника: " .. tostring(rename_err)
            log_msg(M.status_message)
            if callback then callback(false, rename_err) end
            return
        end
    end

    if M.has_libstd_update and M.remote_manifest.libstd and M.remote_manifest.libstd.zip_url then
        local zip_url = M.remote_manifest.libstd.zip_url
        local tmp_zip = M.LIBSTD_DIR .. "libstd_update.zip.tmp"
        local unzip_dir = M.LIBSTD_DIR .. ".unzip_tmp"

        M.state = M.STATE_DOWNLOADING
        M.status_message = "Загрузка пакета стандартных библиотек..."
        M.progress = 0.55

        log_msg("Загрузка libstd.zip из: " .. zip_url)
        local success, err = download_file(zip_url, tmp_zip, function(downloaded, total)
            M.progress = 0.55 + (downloaded / (downloaded + 1000000)) * 0.25
        end)

        if success then
            M.state = M.STATE_VERIFYING
            M.status_message = "Распаковка и установка библиотек..."
            M.progress = 0.85

            os.execute(string.format("mkdir -p '%s'", unzip_dir))
            local code = os.execute(string.format("unzip -o -q '%s' -d '%s'", tmp_zip, unzip_dir))
            if code == 0 or code == true then
                os.execute(string.format("cp -rf '%s'/libstd-main/* '%s' 2>/dev/null || cp -rf '%s'/* '%s' 2>/dev/null", unzip_dir, M.LIBSTD_DIR, unzip_dir, M.LIBSTD_DIR))
                os.execute(string.format("cp -f '%s/neom_updater.lua' '%s/../neom_updater.lua' 2>/dev/null", M.LIBSTD_DIR, M.LIBSTD_DIR))
                os.execute(string.format("cp -f '%s/scriptmgr.lua' '%s/../scriptmgr.lua' 2>/dev/null", M.LIBSTD_DIR, M.LIBSTD_DIR))
                log_msg("Библиотеки успешно распакованы в " .. M.LIBSTD_DIR)
            end
            os.execute(string.format("rm -rf '%s' '%s'", unzip_dir, tmp_zip))
            M.CURRENT_LIBSTD_VERSION = M.remote_manifest.libstd.version
        else
            log_msg("Предупреждение: не удалось загрузить libstd.zip: " .. tostring(err))
        end
    end

    M.progress = 1.0
    M.state = M.STATE_COMPLETED
    M.status_message = "Обновление успешно установлено! Перезапустите игру для применения."
    log_msg(M.status_message)
    if callback then callback(true, "Успешно") end
end

M.apply_binary_update_coroutine = M.apply_all_updates_coroutine

function M.start_auto_check()
    local co = coroutine.create(function()
        M.check_update_coroutine(function(has_update, data)
            if has_update then
                log_msg("Обнаружена новая версия компонентов: " .. tostring(data.version))
            end
        end)
    end)
    coroutine.resume(co)
end

function M.render_ui()
    if not M.show_ui then return end

    local imgui = nil
    if has_mimgui and mimgui then
        imgui = mimgui
    elseif type(_G.imgui) == "table" then
        imgui = _G.imgui
    else
        local ok, lib = pcall(require, "imgui")
        if ok then imgui = lib end
    end

    if not imgui or not imgui.Begin then return end

    local mds = 1.0
    if type(MONET_DPI_SCALE) == "number" and MONET_DPI_SCALE > 0 then
        mds = MONET_DPI_SCALE
    end

    local scrW, scrH = 1920, 1080
    if getScreenResolution then
        scrW, scrH = getScreenResolution()
    end
    local winW, winH = 480 * mds, 280 * mds
    imgui.SetNextWindowPos(imgui.ImVec2((scrW - winW) / 2, (scrH - winH) / 2), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowSize(imgui.ImVec2(winW, winH), imgui.Cond.FirstUseEver)

    local flags = imgui.WindowFlags.NoCollapse
    if imgui.WindowFlags.AlwaysAutoResize then
        flags = flags + imgui.WindowFlags.AlwaysAutoResize
    end

    if imgui.Begin(u8("NeoMLoader - Обновление##updater"), nil, flags) then
        imgui.TextColored(imgui.ImVec4(0.2, 0.8, 1.0, 1.0), u8("Доступно обновление NeoMLoader"))
        imgui.Separator()

        imgui.Text(string.format(u8("Текущая версия: v%s (сборка %d) | libstd v%s"), M.CURRENT_VERSION, M.CURRENT_BUILD, M.CURRENT_LIBSTD_VERSION))
        if M.remote_manifest and M.remote_manifest.version then
            imgui.TextColored(imgui.ImVec4(0.3, 1.0, 0.4, 1.0),
                string.format(u8("Новая версия:   v%s (сборка %s)"), M.remote_manifest.version, tostring(M.remote_manifest.build_number)))
        end

        if M.remote_manifest and M.remote_manifest.changelog and #M.remote_manifest.changelog > 0 then
            imgui.Separator()
            imgui.TextDisabled(u8("Что нового:"))
            imgui.TextWrapped(u8(M.remote_manifest.changelog))
        end

        imgui.Separator()

        if M.state == M.STATE_ERROR then
            imgui.TextColored(imgui.ImVec4(1.0, 0.3, 0.3, 1.0), u8(M.status_message))
        elseif M.state == M.STATE_COMPLETED then
            imgui.TextColored(imgui.ImVec4(0.3, 1.0, 0.4, 1.0), u8(M.status_message))
        else
            imgui.Text(u8(M.status_message))
        end

        if M.state == M.STATE_DOWNLOADING or M.state == M.STATE_VERIFYING then
            imgui.ProgressBar(M.progress, imgui.ImVec2(-1, 20 * mds), string.format("%d%%", math.floor(M.progress * 100)))
        end

        imgui.Spacing()

        if M.state == M.STATE_AVAILABLE then
            if imgui.Button(u8("Обновить сейчас"), imgui.ImVec2(160 * mds, 34 * mds)) then
                local co = coroutine.create(function()
                    M.apply_all_updates_coroutine()
                end)
                coroutine.resume(co)
            end
            imgui.SameLine()
            if imgui.Button(u8("Позже"), imgui.ImVec2(100 * mds, 34 * mds)) then
                M.show_ui = false
            end
        elseif M.state == M.STATE_COMPLETED then
            imgui.TextColored(imgui.ImVec4(0.3, 1.0, 0.4, 1.0), u8("Перезапустите игру для применения."))
            if imgui.Button(u8("Закрыть"), imgui.ImVec2(120 * mds, 34 * mds)) then
                M.show_ui = false
            end
        elseif M.state == M.STATE_ERROR then
            if imgui.Button(u8("Повторить"), imgui.ImVec2(120 * mds, 34 * mds)) then
                M.start_auto_check()
            end
            imgui.SameLine()
            if imgui.Button(u8("Закрыть"), imgui.ImVec2(100 * mds, 34 * mds)) then
                M.show_ui = false
            end
        end

        imgui.End()
    end
end

if has_mimgui and mimgui and mimgui.OnFrame then
    mimgui.OnFrame(
        function() return M.show_ui end,
        function(player)
            player.HideCursor = false
            player.LockPlayer = true
        end,
        function()
            M.render_ui()
        end
    )
end

function main()
    if isSampAvailable then
        while not isSampAvailable() do
            if wait then wait(250) else break end
        end
    end

    if sampIsLocalPlayerSpawned then
        while not sampIsLocalPlayerSpawned() do
            if wait then wait(500) else break end
        end
    end

    if wait then
        wait(3000)
    end

    M.start_auto_check()

    if wait then
        while true do
            wait(1000)
        end
    end
end

return M
