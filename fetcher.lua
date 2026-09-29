--// Extra Hop — FETCHER: всё в одном файле (собрано 2026-09-26 22:21 из config.lua + session_bypass.lua + fetcher.lua)
--// С диска ничего не подгружается. Настройки — в блоке НАСТРОЙКИ ниже; удобнее менять их
--// в исходниках (доб скрипты\виц хоп - исходники\config.lua) и пересобрать build_allinone.py —
--// пересборка перезапишет этот файл.

-- =====================================================================
-- НАСТРОЙКИ (config.lua)
-- =====================================================================
--[[
    ═══════════════════════════════════════════════════════════
    EXTRA HOP v13.0 (BSS Auto-Hop & Farm Suite) — КОНФИГУРАЦИЯ
    ═══════════════════════════════════════════════════════════
    Готовые скрипты лежат в F:\виц хоп: fetcher.lua, searcher.lua, main.lua.
    Каждый самодостаточный (эти настройки и движок сессии встроены), с диска ничего не грузит.
    Настройки меняй здесь (доб скрипты\виц хоп - исходники\config.lua), потом:
        python build_allinone.py

    Инструкция по запуску:
    1. FETCHER (1 аккаунт, сбор серверов в Redis пул):
       Файл: fetcher.lua

    2. SEARCHER (1 или более аккаунтов-скаутов):
       Прыгают по серверам, сканируют мир и мгновенно сбрасывают ВСЕ находки в базу.
       Файл: searcher.lua (или sadsd.txt в autoexec)

    3. MAIN (Основной аккаунт):
       Управляет приоритетами (кнопка ⚙ Настройки в GUI), слушает базу,
       фармит цели и прерывает фарм при обнаружении приоритетных находок.
       Файл: main.lua
]]

-- Общие параметры:
_G.ExtraHopGroup = "default" -- Имя группы серверов
_G.ExtraHopWebhook = ""       -- URL Discord вебхука (по желанию)

_G.ExtraHopConfig = {
    -- Скрипты работают через API сайта (Upstash больше не используется):
    ApiUrl = "https://extra-hop.shop/api/v1",

    -- Сетчер (Searcher):
    Disable3D = false, -- false = графика видна; true = отключение 3D (экран белый, экономия CPU/GPU)

    -- Фетчер (Fetcher):
    PoolTarget = 500,       -- Целевой размер пула серверов
    RefreshInterval = 60,   -- Интервал обновления пула (в секундах)

    -- Основа (Main):
    PollInterval = 3,       -- Частота опроса задач из базы (сек)
    SproutTimeout = 180,    -- Макс. время ожидания слома ростка (сек)
    ViciousTimeout = 300,   -- Макс. время убийства Vicious (сек)
    SproutCollectTime = 25, -- Время сбора токенов после слома (сек)
}

--[=[ ЧТО ИЩЕТ СЁРЧЕР — _G.ExtraConfig (чтобы включить: удали ПЕРВУЮ и ПОСЛЕДНЮЮ строку этого блока)
    Сёрчер отправляет в очередь ТОЛЬКО то, что включено здесь (= true).
    Нет раздела Vicious — вициусы не ищутся; нет Sprouts — ростки не ищутся.
    Если _G.ExtraConfig не задан совсем — ищется всё, как раньше.

    Ростки: Common, Rare, Epic, Legendary, Supreme, Moon, Gummy, Festive
      (Gummy по HP пока не распознаётся — Gummy = true пропускает и нераспознанные ростки)
    MinLevel   — вициусы ниже этого уровня пропускаются
    MinDespawn — сколько секунд цель ещё должна прожить (телепорт ~10-15 с, вициуса ещё надо убить)
    Priority   — срочные цели по порядку: мейн бросит текущий фарм ради них.
                 Можно: любые ростки выше, Vicious (любой), GiftedVicious, RegularVicious.

_G.ExtraConfig = {
    Vicious  = { Regular = true, Gifted = true, MinLevel = 4, MinDespawn = 60 },
    Sprouts  = { Epic = true, Legendary = true, Supreme = true, Gummy = true, Festive = true, MinDespawn = 30 },
    Priority = { "Supreme", "Legendary" },
}
]=]

print("[Extra Hop v13.0] Конфигурация успешно загружена!")

-- =====================================================================
-- НАСТРОЙКИ ИЗ ЛОАДЕРА (с сайта): API, ExtraWebhook, ExtraConfig, DELAY
-- =====================================================================
-- Лоадер задаёт их обычными переменными перед loadstring, например:
--   API = "ключ с сайта"
--   ExtraWebhook = "https://discord.com/api/webhooks/..."        -- по желанию
--   ExtraConfig = { Vicious = {...}, Sprouts = {...}, Priority = {...} }
--   DELAY = 3                                                   -- сёрчер: секунд на сервере до хопа
-- Встроенный конфиг выше их не затирает: здесь они переносятся поверх него.
-- Ключ API = и пропуск на сайт, и то, чья это группа: сайт по нему решает, в чью очередь класть
-- находки, из какого пула серверов брать и чьи (и каких друзей) задачи отдавать мейну.
do
    -- Куда попадёт строка лоадера  API = "..." , зависит от экзекутора и от Luarmor: у одних — в getgenv(),
    -- у других — в окружение самого лоадера, которое loadstring передаёт скрипту. Раньше искали только
    -- в getgenv()/_G, и во втором случае скрипт писал «Нет API-ключа», хотя ключ в лоадере был.
    -- Теперь: как обычная глобальная переменная этого скрипта → getgenv/_G/shared → окружения по стеку вызовов.
    local direct = { API = API, ExtraWebhook = ExtraWebhook, ExtraConfig = ExtraConfig, DELAY = DELAY }
    local function get(name)
        local v = direct[name]
        local function try(t)
            if v ~= nil or type(t) ~= "table" then return end
            local ok, r = pcall(function() return t[name] end)
            if ok and r ~= nil then v = r end
        end
        if getgenv then pcall(function() try(getgenv()) end) end
        try(_G)
        try(shared)
        if v == nil and getfenv then
            for lvl = 0, 30 do
                local ok, e = pcall(getfenv, lvl)
                if not ok then break end -- стек кончился
                try(e)
                if v ~= nil then break end
            end
        end
        return v
    end
    local cfg = _G.ExtraHopConfig
    local api = get("API")
    if type(api) == "string" and api ~= "" and not api:lower():find("paste") then cfg.ApiToken = api end
    local wh = get("ExtraWebhook")
    if type(wh) == "string" and wh:find("^https?://") then _G.ExtraHopWebhook = wh end
    local ec = get("ExtraConfig")
    if type(ec) == "table" then _G.ExtraConfig = ec end
    local d = tonumber(get("DELAY"))
    if d and d > 0 then cfg.ScoutDelay = d end
    if not cfg.ApiToken then
        warn("[Extra Hop] Не указан API-ключ: добавь в лоадер строку  API = \"ключ с сайта\"")
    end
end

-- =====================================================================
-- ДВИЖОК СЕССИИ (session_bypass.lua)
-- =====================================================================
if not _G.ExtraHopBypass then
    local SessionBypass = (function()
--// Extra Hop v14.0 — SESSION LOCK BYPASS & HIGH-SPEED TELEPORT ENGINE
--// Архітектурний модуль для запобігання 5-хвилинного бану сесії (Error 267/769/773/Flooded)
--// Повна ініціалізація першої сесії + надшвидкісний транзит між серверами

local SessionBypass = {}
SessionBypass._version = "14.0"
SessionBypass._initialized = false

-- Конфігурація та таймінги (Karpathy First-Principles Optimization)
local CFG = {
    MinHopInterval = 2.8,       -- Мінімальний інтервал між хопами (захист від Enum.TeleportResult.Flooded)
    SaveLockGracePeriod = 3.5,  -- Точний час очікування для завершення DataStore:UpdateAsync минулого сервера
    TeleportTimeout = 12.0,     -- Таймаут зависання телепорту
    MaxRetries = 3,             -- Максимальна кількість спроб на цільовий сервер
    CookieCooldown = 3.0,       -- Інтервал між зміною cookies
    Disable3DDuringHop = true,  -- Відключення рендерингу під час переходу для швидкості
}

local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
-- при раннем запуске из autoexec LocalPlayer ещё может быть nil — тогда init падал на OnTeleport
local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait(0.05)
    LocalPlayer = Players.LocalPlayer
end

-- Внутрішній стан сесії
local state = {
    firstSessionLoaded = false,
    sessionStartTime = os.time(),
    lastHopTime = 0,
    isHopping = false,
    hopGen = 0, -- поколение хопа: таймаут старого хопа не трогает новый
    isRecovering = false,
    lockDetected = false,
    lockCount = 0,
    successHops = 0,
    cookies = {},
    cookieIndex = 0,
    lastCookieSwitch = 0,
    setCookieFn = nil,
    visitedJobs = {},
    currentTargetJobId = nil,
}

-- =========================================================================
-- 1. ДЕТЕКЦІЯ ТА ВСТАНОВЛЕННЯ EXECUTOR API ДЛЯ COOKIE РОТАЦІЇ
-- =========================================================================
local function detectCookieApi()
    if type(syn) == "table" and syn.set_cookie then return syn.set_cookie end
    if set_cookie then return set_cookie end
    if setcookie then return setcookie end
    if type(fluxus) == "table" and fluxus.set_cookie then return fluxus.set_cookie end
    return nil
end

state.setCookieFn = detectCookieApi()

function SessionBypass:setCookies(cookieList)
    if type(cookieList) == "table" then
        state.cookies = cookieList
        state.cookieIndex = 0
        print("[SessionBypass] Завантажено " .. #state.cookies .. " cookies для ротації")
    end
end

function SessionBypass:rotateCookie()
    if #state.cookies == 0 or not state.setCookieFn then return false end
    local now = os.clock()
    if now - state.lastCookieSwitch < CFG.CookieCooldown then return false end

    state.cookieIndex = (state.cookieIndex % #state.cookies) + 1
    local cookie = state.cookies[state.cookieIndex]
    state.lastCookieSwitch = now
    state.lockDetected = false

    local ok = pcall(function() state.setCookieFn(cookie) end)
    if ok then
        print("[SessionBypass] 🔄 Ротація сесії на cookie #" .. state.cookieIndex)
        task.wait(1.2)
        return true
    end
    return false
end

-- =========================================================================
-- 2. LOADING SCREEN & ASSET BYPASS (Миттєвий запуск без затримок)
-- =========================================================================
function SessionBypass:installLoadingBypass()
    pcall(function()
        local ReplicatedFirst = game:GetService("ReplicatedFirst")
        ReplicatedFirst:RemoveDefaultLoadingScreen()
    end)

    task.spawn(function()
        local startWait = os.clock()
        while os.clock() - startWait < 10 do
            pcall(function()
                if not LocalPlayer then LocalPlayer = Players.LocalPlayer end
                if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") then
                    local pg = LocalPlayer.PlayerGui
                    local loadGui = pg:FindFirstChild("LoadingScreenGui") or pg:FindFirstChild("LoadingGui")
                    if loadGui and loadGui:IsA("ScreenGui") then
                        loadGui.Enabled = false
                    end
                    local startMenu = pg:FindFirstChild("StartMenu") or pg:FindFirstChild("ScreenGui")
                    if startMenu and startMenu:FindFirstChild("PlayButton") then
                        local btn = startMenu.PlayButton
                        if firesignal then
                            firesignal(btn.MouseButton1Click)
                            firesignal(btn.Activated)
                        elseif btn.Click then
                            btn:Click()
                        end
                    end
                    local tutorial = pg:FindFirstChild("TutorialGui") or pg:FindFirstChild("Intro")
                    if tutorial then tutorial.Enabled = false end
                end
            end)
            if game:IsLoaded() then break end
            task.wait(0.05)
        end
    end)
end

-- =========================================================================
-- 3. ТЕЛЕПОРТ СТЕЙТ СКИНУТИ ТА ОЧИСТИТИ (Reset Teleport Internal State)
-- =========================================================================
function SessionBypass:resetTeleportState()
    pcall(function()
        TeleportService:SetTeleportGui(nil)
    end)

    pcall(function()
        local t0 = os.clock()
        while os.clock() - t0 < 3 do
            if TeleportService:GetArrivingTeleportGui() == nil then break end
            task.wait(0.05)
        end
    end)

    if CFG.Disable3DDuringHop then
        pcall(function() RunService:Set3dRenderingEnabled(false) end)
    end
end

-- =========================================================================
-- 4. МИТТЄВИЙ ПЕРЕХОПЛЮВАЧ ПОМИЛОК ROBLOX (CoreGui / Prompt Watchdog)
-- =========================================================================
function SessionBypass:dismissPromptOverlay()
    local dismissed = false
    pcall(function()
        local promptGui = CoreGui:FindFirstChild("RobloxPromptGui")
        if promptGui then
            local prompt = promptGui:FindFirstChild("promptOverlay", true)
            if prompt then
                for _, btn in pairs(prompt:GetDescendants()) do
                    if btn:IsA("TextButton") and btn.Visible then
                        if firesignal then
                            firesignal(btn.MouseButton1Click)
                            firesignal(btn.Activated)
                        elseif btn.Click then
                            btn:Click()
                        end
                        dismissed = true
                    end
                end
            end
        end
    end)
    return dismissed
end

-- =========================================================================
-- 5. SAFETELEPORT: ЗАХИСТ ВІД 5-ХВ БАНУ ТА МАКСИМАЛЬНА ШВИДКІСТЬ ХОПУ
-- =========================================================================
function SessionBypass:safeTeleport(placeId, targetJobId, nextServerFallbackFn, markFullFn)
    local targetPlace = placeId or game.PlaceId
    if not targetPlace or targetPlace <= 0 then targetPlace = 1537690962 end

    if state.isHopping then
        warn("[SessionBypass] ⚠️ Хоп вже в процесі, пропускаємо паралельний виклик")
        return false
    end

    -- Захист від Flooded: токен-бакет інтервал між запитами
    local now = os.clock()
    local elapsed = now - state.lastHopTime
    if elapsed < CFG.MinHopInterval then
        local waitDiff = CFG.MinHopInterval - elapsed
        task.wait(waitDiff)
    end

    state.isHopping = true
    state.hopGen = state.hopGen + 1
    local myGen = state.hopGen
    state.lastHopTime = os.clock()
    state.currentTargetJobId = targetJobId

    -- Скидаємо стан TeleportService
    self:resetTeleportState()

    -- Записуємо контекст сесії для збереження між серверами
    pcall(function()
        if writefile and targetJobId then
            writefile("extra_hop_current_target.txt", tostring(targetJobId))
        end
        TeleportService:SetTeleportSetting("EXTRA_HOP_ACTIVE_JOB", tostring(targetJobId or ""))
    end)

    local teleportSuccess = false

    -- Якщо вказано конкретний сервер (JobId)
    if targetJobId and #tostring(targetJobId) > 5 then
        for attempt = 1, CFG.MaxRetries do
            local ok, err = pcall(function()
                TeleportService:TeleportToPlaceInstance(targetPlace, tostring(targetJobId), LocalPlayer)
                teleportSuccess = true
            end)

            if ok and teleportSuccess then
                break
            else
                local errStr = tostring(err):lower()
                warn(string.format("[SessionBypass] Спроба #%d ТП не вдалася: %s", attempt, errStr))

                if errStr:find("full") or errStr:find("773") then
                    if markFullFn then pcall(markFullFn, targetJobId) end
                    break
                elseif errStr:find("flooded") or errStr:find("rate") then
                    state.lockDetected = true
                    state.lockCount = state.lockCount + 1
                    if #state.cookies > 0 then self:rotateCookie() end
                    task.wait(2.0 + attempt * 0.8)
                else
                    task.wait(1.0)
                end
            end
        end
    end

    -- Fallback на наступний сервер з пулу або загальний телепорт
    if not teleportSuccess then
        warn("[SessionBypass] Використовуємо fallback-перехід...")
        if nextServerFallbackFn then
            state.isHopping = false
            return nextServerFallbackFn()
        else
            pcall(function()
                TeleportService:Teleport(targetPlace, LocalPlayer)
                teleportSuccess = true
            end)
        end
    end

    -- Наглядач таймауту телепортації (якщо завис на екрані переходу)
    task.delay(CFG.TeleportTimeout, function()
        if state.isHopping and state.hopGen == myGen then
            warn("[SessionBypass] ⏱ Таймаут телепорту (12с) — розблокування для наступного хопу")
            state.isHopping = false
            if markFullFn and targetJobId then
                pcall(markFullFn, targetJobId)
            end
            if nextServerFallbackFn then
                nextServerFallbackFn()
            end
        end
    end)

    return teleportSuccess
end

-- =========================================================================
-- 6. ОБРОБКА SAVE-LOCK ТА FATAL ПОМИЛОК (Error 267 "still saving")
-- =========================================================================
function SessionBypass:handleSaveLockAndReconnect(placeId, isSaveLock, fallbackFn)
    if state.isRecovering then return end
    state.isRecovering = true

    print(string.format("[SessionBypass] 🛡 Перехоплення помилки (SaveLock: %s) -> ліквідація модального вікна", tostring(isSaveLock)))
    self:dismissPromptOverlay()

    -- Критичний момент: якщо це SaveLock (267), даємо старому серверу записати DataStore!
    -- Замість спаму телепортами, чекаємо рівно 3.5 секунди
    if isSaveLock then
        print("[SessionBypass] ⏳ Очікування закриття попередньої сесії DataStore (3.5с)...")
        task.wait(CFG.SaveLockGracePeriod)
    else
        task.wait(0.8)
    end

    -- Ротуємо cookie якщо є доступні
    if isSaveLock and #state.cookies > 0 then
        self:rotateCookie()
    end

    self:dismissPromptOverlay()
    state.isHopping = false

    if fallbackFn then
        fallbackFn()
    else
        pcall(function()
            TeleportService:Teleport(placeId or 1537690962, LocalPlayer)
        end)
    end

    task.delay(8.0, function()
        state.isRecovering = false
    end)
end

-- =========================================================================
-- 7. СЛУХАЧІ ТА АВТОМАТИЧНИЙ МОНІТОРИНГ
-- =========================================================================
function SessionBypass:init(customCfg)
    if self._initialized then return self end
    self._initialized = true

    if type(customCfg) == "table" then
        for k, v in pairs(customCfg) do CFG[k] = v end
    end

    -- 1. Loading bypass
    self:installLoadingBypass()

    -- 2. Обробка помилок ініціалізації телепорту (TeleportInitFailed)
    TeleportService.TeleportInitFailed:Connect(function(player, teleResult, errorMsg)
        if player ~= LocalPlayer then return end
        local errMsg = tostring(errorMsg):lower()
        local resultStr = tostring(teleResult):lower()

        warn(string.format("[SessionBypass] ⚠️ TeleportInitFailed: %s (%s)", tostring(teleResult), tostring(errorMsg)))
        state.isHopping = false

        local isRateLimit = resultStr:find("flooded") or errMsg:find("flooded") or errMsg:find("773") or errMsg:find("769")
        if isRateLimit then
            state.lockDetected = true
            state.lockCount = state.lockCount + 1
            if #state.cookies > 0 then self:rotateCookie() end
            -- Розумний бекофф замість миттєвого спаму
            task.wait(2.5)
        end
    end)

    -- 3. Відстеження успішного початку переходу
    LocalPlayer.OnTeleport:Connect(function(teleportState)
        if teleportState == Enum.TeleportState.Started then
            state.successHops = state.successHops + 1
            state.lockDetected = false
            state.isHopping = false
            print("[SessionBypass] ✅ Телепорт успішно розпочато")
        end
    end)

    -- 4. Завантаження cookies з файлу cookies.txt (якщо існує)
    pcall(function()
        if isfile and isfile("cookies.txt") then
            local raw = readfile("cookies.txt")
            local list = {}
            for line in raw:gmatch("[^\r\n]+") do
                local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
                if #trimmed > 20 and not trimmed:find("^#") then
                    table.insert(list, trimmed)
                end
            end
            if #list > 0 then self:setCookies(list) end
        end
    end)

    _G.ExtraHopBypass = self
    print(string.format("[SessionBypass v%s] Запущено успішно. Захист сесії активовано.", self._version))
    return self
end

function SessionBypass:getState()
    return state
end

function SessionBypass:isHopping()
    return state.isHopping
end

function SessionBypass:setHopping(val)
    state.isHopping = val
end

return SessionBypass
    end)()
    if SessionBypass and SessionBypass.init then pcall(function() SessionBypass:init() end) end
end

-- =====================================================================
-- FETCHER (fetcher.lua)
-- =====================================================================
--// Extra Hop v13.2 — FETCHER | Minimalist Stealth Dark Server Pooler
-- =========================================================================
-- 1. РАННИЙ СТОРОЖЕВОЙ ТАЙМЕР (WATCHDOG) ОТ ОШИБОК 279 / 267 / DISCONNECT
-- =========================================================================
local CoreGui = game:GetService("CoreGui")
local TeleportService = game:GetService("TeleportService")
local PlaceId = game.PlaceId > 0 and game.PlaceId or 1537690962

-- Ініціалізація Session Lock Bypass Engine
local Bypass = _G.ExtraHopBypass
if not Bypass then
    pcall(function()
        if isfile and isfile("session_bypass.lua") then
            Bypass = loadstring(readfile("session_bypass.lua"))()
        elseif isfile and isfile("Bss_hop/session_bypass.lua") then
            Bypass = loadstring(readfile("Bss_hop/session_bypass.lua"))()
        end
    end)
    if Bypass and Bypass.init then
        pcall(function() Bypass:init() end)
    end
end

local isRecovering = false
local function dismissErrorAndReconnect(isSaveLock)
    if isRecovering then return end
    if Bypass and Bypass.handleSaveLockAndReconnect then
        Bypass:handleSaveLockAndReconnect(PlaceId, isSaveLock)
        return
    end
    isRecovering = true

    pcall(function()
        local promptGui = CoreGui:FindFirstChild("RobloxPromptGui")
        if promptGui then
            local prompt = promptGui:FindFirstChild("promptOverlay", true)
            if prompt then
                for _, btn in pairs(prompt:GetDescendants()) do
                    if btn:IsA("TextButton") and btn.Visible then
                        pcall(function()
                            if firesignal then
                                firesignal(btn.MouseButton1Click)
                                firesignal(btn.Activated)
                            elseif btn.Click then
                                btn:Click()
                            end
                        end)
                    end
                end
            end
        end
    end)

    if isSaveLock then task.wait(5.5) else task.wait(0.5) end

    for attempt = 1, 3 do
        local ok = pcall(function()
            TeleportService:Teleport(PlaceId, game:GetService("Players").LocalPlayer)
        end)
        if ok then break end
        task.wait(2)
    end
    task.delay(10, function() isRecovering = false end)
end

task.spawn(function()
    while true do
        pcall(function()
            local promptGui = CoreGui:FindFirstChild("RobloxPromptGui")
            if promptGui then
                local prompt = promptGui:FindFirstChild("promptOverlay", true)
                if prompt and #prompt:GetChildren() > 0 then
                    local errorFound = false
                    local isSaveLock = false
                    for _, obj in pairs(prompt:GetDescendants()) do
                        if obj:IsA("TextLabel") and obj.Visible then
                            local t = obj.Text:lower()
                            if t:find("still saving") or t:find("saving on the previous") or t:find("267") then
                                isSaveLock = true; errorFound = true; break
                            elseif t:find("279") or t:find("failed") or t:find("disconnect") or t:find("lost connection") or t:find("277") or t:find("268") or t:find("timed out") or t:find("no response") or t:find("kicked") then
                                errorFound = true; break
                            end
                        elseif obj:IsA("TextButton") and obj.Visible then
                            local bt = obj.Text:lower()
                            if bt:find("retry") or bt:find("cancel") or bt:find("reconnect") or bt:find("leave") then
                                errorFound = true; break
                            end
                        end
                    end
                    if errorFound then dismissErrorAndReconnect(isSaveLock) end
                end
            end
        end)
        task.wait(1)
    end
end)

if not game:IsLoaded() then
    local startWait = os.clock()
    while not game:IsLoaded() and (os.clock() - startWait) < 15 do
        task.wait(0.5)
    end
    if not game:IsLoaded() then
        dismissErrorAndReconnect(false)
        return
    end
end

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local lpWait = os.clock()
while not LocalPlayer and (os.clock() - lpWait) < 10 do
    task.wait(0.1)
    LocalPlayer = Players.LocalPlayer
end
if not LocalPlayer then
    dismissErrorAndReconnect(false)
    return
end

if not _G.ExtraHopConfig then
    pcall(function()
        if isfile and isfile("extra_hop_config.lua") then
            loadstring(readfile("extra_hop_config.lua"))()
        elseif isfile and isfile("Bss_hop/extra_hop_config.lua") then
            loadstring(readfile("Bss_hop/extra_hop_config.lua"))()
        elseif isfile and isfile("scripts/extra_hop_config.lua") then
            loadstring(readfile("scripts/extra_hop_config.lua"))()
        elseif isfile and isfile("config.lua") then
            loadstring(readfile("config.lua"))()
        end
    end)
end

local CFG_EXT = _G.ExtraHopConfig or {}
local GROUP = _G.ExtraHopGroup or "default"
-- Пул серверов — через API сайта, а не напрямую в базу.
local API_URL = CFG_EXT.ApiUrl or "https://extra-hop.shop/api/v1"
-- Ключ — только из лоадера (API = "..."). Общий токен, зашитый раньше, убран:
-- его видел любой, кто открывал скрипт.
local API_TOKEN = CFG_EXT.ApiToken or ""

local HttpService = game:GetService("HttpService")
local POOL_TARGET = CFG_EXT.PoolTarget or 500
local SERVER_API = "https://games.roblox.com/v1/games/" .. PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
local REFRESH_INTERVAL = CFG_EXT.RefreshInterval or 60

local function httpRequest(options)
    options.Timeout = options.Timeout or 4
    local req = (syn and syn.request) or (http and http.request) or (fluxus and fluxus.request) or http_request or request
    if req then
        return req(options)
    elseif options.Method == "GET" and type(game.HttpGet) == "function" then
        local success, body = pcall(function() return game:HttpGet(options.Url) end)
        return {StatusCode = success and 200 or 500, Body = body}
    else
        local success, body = pcall(function()
            if options.Method == "GET" then return HttpService:GetAsync(options.Url)
            else return HttpService:PostAsync(options.Url, options.Body or "", Enum.HttpContentType.ApplicationJson) end
        end)
        return {StatusCode = success and 200 or 500, Body = body}
    end
end

-- Запрос к API сайта. Возвращает разобранный JSON (таблицу) или nil при ошибке сети/сервера.
local function apiCall(method, path, body, timeout)
    local ok, resp = pcall(function()
        return httpRequest({
            Url = API_URL .. path,
            Method = method,
            Timeout = timeout or 3.5,
            Headers = {
                ["X-Extra-Token"] = API_TOKEN,
                ["Content-Type"] = "application/json",
            },
            Body = body and HttpService:JSONEncode(body) or nil,
        })
    end)
    if not ok or not resp or not resp.Body then return nil end
    local code = tonumber(resp.StatusCode) or 0
    if code < 200 or code >= 300 then return nil end
    local decOk, data = pcall(function() return HttpService:JSONDecode(resp.Body) end)
    return decOk and data or nil
end

local function getPoolSize()
    local r = apiCall("GET", "/pool/size?group=" .. GROUP, nil, 2)
    return r and tonumber(r.size) or 0
end

local function fetchServerPage(cursor)
    local url = SERVER_API
    if cursor and cursor ~= "" then
        url = url .. "&cursor=" .. cursor
    end

    for attempt = 1, 3 do
        local ok, resp = pcall(function()
            return httpRequest({
                Url = url,
                Method = "GET",
                Timeout = 4,
                Headers = {
                    ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
                    ["Accept"] = "application/json"
                }
            })
        end)

        if ok and resp then
            local code = resp.StatusCode or 0
            if code == 429 then
                task.wait(attempt * 4 + math.random(1, 3))
            elseif resp.Body then
                local body = type(resp.Body) == "string" and resp.Body or tostring(resp.Body)
                local decOk, data = pcall(function() return HttpService:JSONDecode(body) end)
                if decOk and data and data.data then
                    return data
                end
            end
        end

        if attempt < 3 then task.wait(attempt * 1.5) end
    end

    local ok2, data2 = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(url))
    end)
    if ok2 and data2 and data2.data then return data2 end

    return nil
end

-- ========== SAFE GUI PARENTING ==========
local function safeParentGui(gui)
    local parented = false
    pcall(function()
        if gethui then
            gui.Parent = gethui()
            parented = true
        elseif syn and syn.protect_gui then
            syn.protect_gui(gui)
            gui.Parent = game:GetService("CoreGui")
            parented = true
        end
    end)
    if not parented or not gui.Parent then
        pcall(function()
            gui.Parent = game:GetService("CoreGui")
            parented = true
        end)
    end
    if not gui.Parent then
        pcall(function()
            gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
            parented = true
        end)
    end
    return parented
end

pcall(function()
    local old = (gethui and gethui():FindFirstChild("ExtraHopFetcherGUI"))
        or game:GetService("CoreGui"):FindFirstChild("ExtraHopFetcherGUI")
        or (LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("ExtraHopFetcherGUI"))
    if old then old:Destroy() end
end)

-- ========== MINIMALIST STEALTH DARK FETCHER GUI ==========
local THEME = {
    bg = Color3.fromRGB(14, 16, 22),
    surface = Color3.fromRGB(20, 23, 31),
    surfaceElevated = Color3.fromRGB(27, 31, 42),
    border = Color3.fromRGB(36, 42, 56),
    borderActive = Color3.fromRGB(56, 66, 88),
    textPrimary = Color3.fromRGB(241, 245, 249),
    textSecondary = Color3.fromRGB(148, 163, 184),
    textMuted = Color3.fromRGB(100, 116, 139),
    accentBlue = Color3.fromRGB(56, 189, 248),
    accentGreen = Color3.fromRGB(52, 211, 153),
    accentAmber = Color3.fromRGB(251, 191, 36),
    accentRed = Color3.fromRGB(248, 113, 113)
}

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ExtraHopFetcherGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 999999
safeParentGui(ScreenGui)

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 330, 0, 185)
MainFrame.Position = UDim2.new(0.5, -165, 0.025, 0)
MainFrame.BackgroundColor3 = THEME.bg
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Active = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)

local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Color = THEME.border
MainStroke.Thickness = 1.2

-- Dragging
local isDragging = false
local dragInput, dragStart, startPos
MainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        isDragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then isDragging = false end
        end)
    end
end)
MainFrame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then dragInput = input end
end)
game:GetService("UserInputService").InputChanged:Connect(function(input)
    if input == dragInput and isDragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

-- Header Bar
local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 34)
Header.BackgroundColor3 = THEME.surface
Header.BorderSizePixel = 0
Header.Parent = MainFrame
Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 10)

local LogoImg = Instance.new("ImageLabel")
LogoImg.Size = UDim2.new(0, 20, 0, 20)
LogoImg.Position = UDim2.new(0, 8, 0.5, -10)
LogoImg.BackgroundTransparency = 1
LogoImg.Parent = Header
Instance.new("UICorner", LogoImg).CornerRadius = UDim.new(0, 4)

pcall(function()
    local getAsset = getcustomasset or getsynasset
    if getAsset and isfile and isfile("extra_hop_logo.png") then
        LogoImg.Image = getAsset("extra_hop_logo.png")
    elseif getAsset and isfile and isfile("scripts/extra_hop_logo.png") then
        LogoImg.Image = getAsset("scripts/extra_hop_logo.png")
    else
        LogoImg.Visible = false
    end
end)

local HeaderTitle = Instance.new("TextLabel")
HeaderTitle.Size = UDim2.new(1, -120, 1, 0)
HeaderTitle.Position = LogoImg.Visible and UDim2.new(0, 32, 0, 0) or UDim2.new(0, 10, 0, 0)
HeaderTitle.BackgroundTransparency = 1
HeaderTitle.Text = "EXTRA HOP"
HeaderTitle.TextColor3 = THEME.textPrimary
HeaderTitle.TextSize = 11
HeaderTitle.Font = Enum.Font.GothamBold
HeaderTitle.TextXAlignment = Enum.TextXAlignment.Left
HeaderTitle.Parent = Header

local Badge = Instance.new("TextLabel")
Badge.Size = UDim2.new(0, 52, 0, 16)
Badge.Position = LogoImg.Visible and UDim2.new(0, 102, 0.5, -8) or UDim2.new(0, 80, 0.5, -8)
Badge.BackgroundColor3 = THEME.surfaceElevated
Badge.Text = "FETCHER"
Badge.TextColor3 = THEME.accentBlue
Badge.TextSize = 9
Badge.Font = Enum.Font.GothamBold
Badge.Parent = Header
Instance.new("UICorner", Badge).CornerRadius = UDim.new(0, 4)

local MinimizeBtn = Instance.new("TextButton")
MinimizeBtn.Size = UDim2.new(0, 22, 0, 20)
MinimizeBtn.Position = UDim2.new(1, -28, 0.5, -10)
MinimizeBtn.BackgroundColor3 = THEME.surfaceElevated
MinimizeBtn.Text = "—"
MinimizeBtn.TextColor3 = THEME.textSecondary
MinimizeBtn.TextSize = 11
MinimizeBtn.Font = Enum.Font.GothamBold
MinimizeBtn.BorderSizePixel = 0
MinimizeBtn.Parent = Header
Instance.new("UICorner", MinimizeBtn).CornerRadius = UDim.new(0, 4)

local Body = Instance.new("Frame")
Body.Size = UDim2.new(1, -16, 1, -40)
Body.Position = UDim2.new(0, 8, 0, 38)
Body.BackgroundTransparency = 1
Body.Parent = MainFrame

local isMin = false
MinimizeBtn.MouseButton1Click:Connect(function()
    isMin = not isMin
    Body.Visible = not isMin
    MainFrame.Size = isMin and UDim2.new(0, 330, 0, 34) or UDim2.new(0, 330, 0, 185)
    MinimizeBtn.Text = isMin and "+" or "—"
end)

-- 1. СТАТУС
local StatusRow = Instance.new("Frame")
StatusRow.Size = UDim2.new(1, 0, 0, 18)
StatusRow.BackgroundTransparency = 1
StatusRow.Parent = Body

local StatusDot = Instance.new("TextLabel")
StatusDot.Size = UDim2.new(0, 10, 0, 10)
StatusDot.Position = UDim2.new(0, 2, 0.5, -5)
StatusDot.BackgroundTransparency = 1
StatusDot.Text = "●"
StatusDot.TextColor3 = THEME.accentGreen
StatusDot.TextSize = 11
StatusDot.Font = Enum.Font.GothamBold
StatusDot.Parent = StatusRow

local StatusText = Instance.new("TextLabel")
StatusText.Size = UDim2.new(1, -18, 1, 0)
StatusText.Position = UDim2.new(0, 16, 0, 0)
StatusText.BackgroundTransparency = 1
StatusText.Text = "Статус: Запуск..."
StatusText.TextColor3 = THEME.textPrimary
StatusText.TextSize = 11
StatusText.Font = Enum.Font.GothamMedium
StatusText.TextXAlignment = Enum.TextXAlignment.Left
StatusText.Parent = StatusRow

-- 2. КАРТОЧКА ПУЛА СЕРВЕРОВ
local PoolCard = Instance.new("Frame")
PoolCard.Size = UDim2.new(1, 0, 0, 50)
PoolCard.Position = UDim2.new(0, 0, 0, 22)
PoolCard.BackgroundColor3 = THEME.surface
PoolCard.BorderSizePixel = 0
PoolCard.Parent = Body
Instance.new("UICorner", PoolCard).CornerRadius = UDim.new(0, 6)
local CardStroke = Instance.new("UIStroke", PoolCard)
CardStroke.Color = THEME.border
CardStroke.Thickness = 1

local PoolCountLabel = Instance.new("TextLabel")
PoolCountLabel.Size = UDim2.new(1, -16, 0, 16)
PoolCountLabel.Position = UDim2.new(0, 8, 0, 5)
PoolCountLabel.BackgroundTransparency = 1
PoolCountLabel.Text = "Пул серверов: 0 / " .. POOL_TARGET
PoolCountLabel.TextColor3 = THEME.textPrimary
PoolCountLabel.TextSize = 11
PoolCountLabel.Font = Enum.Font.GothamBold
PoolCountLabel.TextXAlignment = Enum.TextXAlignment.Left
PoolCountLabel.Parent = PoolCard

local BarBg = Instance.new("Frame")
BarBg.Size = UDim2.new(1, -16, 0, 6)
BarBg.Position = UDim2.new(0, 8, 0, 24)
BarBg.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
BarBg.BorderSizePixel = 0
BarBg.Parent = PoolCard
Instance.new("UICorner", BarBg).CornerRadius = UDim.new(0, 3)

local BarFill = Instance.new("Frame")
BarFill.Size = UDim2.new(0, 0, 1, 0)
BarFill.BackgroundColor3 = THEME.accentBlue
BarFill.BorderSizePixel = 0
BarFill.Parent = BarBg
Instance.new("UICorner", BarFill).CornerRadius = UDim.new(0, 3)

local DetailLabel = Instance.new("TextLabel")
DetailLabel.Size = UDim2.new(1, -16, 0, 12)
DetailLabel.Position = UDim2.new(0, 8, 0, 33)
DetailLabel.BackgroundTransparency = 1
DetailLabel.Text = "Стр: 0  •  Добавлено: 0  •  Цикл: 0"
DetailLabel.TextColor3 = THEME.textMuted
DetailLabel.TextSize = 9
DetailLabel.Font = Enum.Font.Code
DetailLabel.TextXAlignment = Enum.TextXAlignment.Left
DetailLabel.Parent = PoolCard

-- 3. БЛОК СЛЕДУЮЩЕГО ЦИКЛА
local InfoBox = Instance.new("Frame")
InfoBox.Size = UDim2.new(1, 0, 0, 42)
InfoBox.Position = UDim2.new(0, 0, 0, 76)
InfoBox.BackgroundColor3 = THEME.surface
InfoBox.BorderSizePixel = 0
InfoBox.Parent = Body
Instance.new("UICorner", InfoBox).CornerRadius = UDim.new(0, 6)
local InfoStroke = Instance.new("UIStroke", InfoBox)
InfoStroke.Color = THEME.border
InfoStroke.Thickness = 1

local CycleLabel = Instance.new("TextLabel")
CycleLabel.Size = UDim2.new(1, -12, 0, 18)
CycleLabel.Position = UDim2.new(0, 8, 0, 4)
CycleLabel.BackgroundTransparency = 1
CycleLabel.Text = "Следующий сбор: " .. REFRESH_INTERVAL .. "с"
CycleLabel.TextColor3 = THEME.accentAmber
CycleLabel.TextSize = 10
CycleLabel.Font = Enum.Font.GothamMedium
CycleLabel.TextXAlignment = Enum.TextXAlignment.Left
CycleLabel.Parent = InfoBox

local TotalStatsLabel = Instance.new("TextLabel")
TotalStatsLabel.Size = UDim2.new(1, -12, 0, 16)
TotalStatsLabel.Position = UDim2.new(0, 8, 0, 22)
TotalStatsLabel.BackgroundTransparency = 1
TotalStatsLabel.Text = "Всего залито: 0 серверов  •  Фильтр: 2+ слота"
TotalStatsLabel.TextColor3 = THEME.textMuted
TotalStatsLabel.TextSize = 9
TotalStatsLabel.Font = Enum.Font.Code
TotalStatsLabel.TextXAlignment = Enum.TextXAlignment.Left
TotalStatsLabel.Parent = InfoBox

local Footer = Instance.new("TextLabel")
Footer.Size = UDim2.new(1, 0, 0, 16)
Footer.Position = UDim2.new(0, 2, 0, 122)
Footer.BackgroundTransparency = 1
Footer.Text = "Extra Hop Fast Matchmaking Pooler Active"
Footer.TextColor3 = THEME.textMuted
Footer.TextSize = 8
Footer.Font = Enum.Font.Code
Footer.TextXAlignment = Enum.TextXAlignment.Left
Footer.Parent = Body

local function setStatus(text, color)
    StatusText.Text = "Статус: " .. text
    StatusDot.TextColor3 = color or THEME.accentGreen
end

local totalAdded = 0
local cycles = 0

local function fillPool()
    local poolSize = getPoolSize()
    local progress = math.clamp(poolSize / POOL_TARGET, 0, 1)
    BarFill.Size = UDim2.new(progress, 0, 1, 0)
    PoolCountLabel.Text = "Пул серверов: " .. poolSize .. " / " .. POOL_TARGET

    if poolSize >= POOL_TARGET then
        setStatus("Пул полон (" .. poolSize .. ")", THEME.accentGreen)
        return
    end

    setStatus("Опрос серверов...", THEME.accentAmber)
    local cursor = ""
    local pages = 0
    local added = 0

    while pages < 10 do
        if getPoolSize() >= POOL_TARGET then break end
        local result = fetchServerPage(cursor)
        if not result or not result.data or #result.data == 0 then break end

        local batch = {}
        for _, server in ipairs(result.data) do
            local id = tostring(server.id)
            if id ~= game.JobId and server.playing and server.maxPlayers and (server.maxPlayers - server.playing) >= 2 and server.playing >= 2 then
                table.insert(batch, id)
            end
        end

        if #batch > 0 then
            -- сервер добавит в пул и сам продлит его жизнь на час
            local r = apiCall("POST", "/pool/add", { group = GROUP, ids = batch }, 3)
            if r then
                added = added + (tonumber(r.added) or 0)
            end
        end

        pages = pages + 1
        DetailLabel.Text = "Стр: " .. pages .. "  •  Добавлено: +" .. added .. "  •  Цикл: " .. (cycles + 1)
        setStatus("Стр. " .. pages .. " (+" .. added .. ")", THEME.accentBlue)

        if not result.nextPageCursor or result.nextPageCursor == "" then break end
        cursor = result.nextPageCursor
        task.wait(0.6)
    end

    totalAdded = totalAdded + added
    cycles = cycles + 1

    local currentPool = getPoolSize()
    local finalProg = math.clamp(currentPool / POOL_TARGET, 0, 1)
    BarFill.Size = UDim2.new(finalProg, 0, 1, 0)
    PoolCountLabel.Text = "Пул серверов: " .. currentPool .. " / " .. POOL_TARGET
    DetailLabel.Text = "Стр: " .. pages .. "  •  Добавлено: +" .. added .. "  •  Цикл: " .. cycles
    TotalStatsLabel.Text = "Всего залито: " .. totalAdded .. " серверов  •  Фильтр: 2+ слота"
    setStatus("Завершено +" .. added, THEME.accentGreen)
end

task.spawn(function()
    if not game:IsLoaded() then game.Loaded:Wait() end
    task.wait(1)
    -- без API-ключа сайт серверы не примет — пул не пополняем
    if API_TOKEN == "" then
        setStatus("Нет API-ключа — впиши API = \"...\" в лоадер", THEME.accentRed)
        warn("[Extra Hop Fetcher] Нет API-ключа (API = \"...\" в лоадере) — пул не пополняется")
        return
    end
    while true do
        pcall(fillPool)
        for i = REFRESH_INTERVAL, 1, -1 do
            CycleLabel.Text = "Следующий сбор: " .. i .. "с"
            task.wait(1)
        end
    end
end)

-- Anti-AFK
task.spawn(function()
    while true do
        pcall(function()
            local vu = game:GetService("VirtualUser")
            vu:CaptureController()
            vu:ClickButton2(Vector2.new())
        end)
        task.wait(30)
    end
end)

print("[Extra Hop v13.2] FETCHER | Группа: " .. GROUP .. " | Игрок: " .. LocalPlayer.Name)
