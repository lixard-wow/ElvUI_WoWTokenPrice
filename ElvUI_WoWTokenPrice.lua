local E, L, V, P, G = unpack(ElvUI)
local DT = E:GetModule('DataTexts')

local currentPrice = nil
local previousPrice = nil
local REFRESH_INTERVAL = 300
local HISTORY_SIZE = 24  -- 2 hours at 5-min intervals
local lastRequest = 0
local lastUpdated = nil
local sessionHigh = nil
local sessionLow = nil
local priceHistory = {}  -- { time, price } entries


local function FormatGold(copper)
    return BreakUpLargeNumbers(floor(copper / 10000)) .. "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
end

local function FormatAge(t)
    if not t then return "unknown" end
    local age = time() - t
    if age < 60 then
        return "just now"
    elseif age < 3600 then
        local m = floor(age / 60)
        local s = age % 60
        return string.format("%dm %ds ago", m, s)
    else
        local h = floor(age / 3600)
        local m = floor((age % 3600) / 60)
        return string.format("%dh %dm ago", h, m)
    end
end

local function FormatDuration(secs)
    if secs <= 0 then return "now" end
    if secs < 60 then
        return string.format("%ds", secs)
    else
        return string.format("%dm %ds", floor(secs / 60), secs % 60)
    end
end

local function GetTrendColor()
    if not currentPrice or not previousPrice then
        return "|cffffffff"  -- white, no data yet
    elseif currentPrice > previousPrice then
        return "|cff00ff00"  -- green, going up
    elseif currentPrice < previousPrice then
        return "|cffff4444"  -- red, going down
    else
        return "|cffffffff"  -- white, unchanged
    end
end

local function BuildSparkline()
    local n = #priceHistory
    if n < 2 then return nil end

    local min, max = math.huge, -math.huge
    for _, entry in ipairs(priceHistory) do
        if entry.price < min then min = entry.price end
        if entry.price > max then max = entry.price end
    end

    local range = max - min
    local line = ""
    for _, entry in ipairs(priceHistory) do
        local t = range == 0 and 0.5 or (entry.price - min) / range
        local r = t < 0.5 and 1 or (1 - t) * 2
        local g = t < 0.5 and t * 2 or 1
        line = line .. string.format("|cff%02x%02x00l|r", floor(r * 255), floor(g * 255))
    end
    return line, min, max
end

local function SaveState()
    ElvUI_WoWTokenPriceDB = {
        currentPrice  = currentPrice,
        previousPrice = previousPrice,
        lastUpdated   = lastUpdated,
        priceHistory  = priceHistory,
    }
end

local function LoadState()
    local db = ElvUI_WoWTokenPriceDB
    if not db then return end
    currentPrice  = db.currentPrice
    previousPrice = db.previousPrice
    lastUpdated   = db.lastUpdated
    priceHistory  = db.priceHistory or {}
end

local function RecordPrice(price)
    local last = priceHistory[#priceHistory]
    if last and last.price == price then return end

    table.insert(priceHistory, { time = time(), price = price })
    if #priceHistory > HISTORY_SIZE then
        table.remove(priceHistory, 1)
    end
end

local function RequestPrice()
    local now = GetTime()
    if now - lastRequest > REFRESH_INTERVAL then
        C_WowTokenPublic.UpdateMarketPrice()
        lastRequest = now
    end
end

local function OnUpdate(self, elapsed)
    RequestPrice()
end

local function OnEvent(self, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        sessionHigh = nil
        sessionLow  = nil
        RequestPrice()
    elseif event == "TOKEN_MARKET_PRICE_UPDATED" then
        local newPrice = C_WowTokenPublic.GetCurrentMarketPrice()
        if newPrice and newPrice > 0 then
            previousPrice = currentPrice
            currentPrice  = newPrice
            lastUpdated   = time()
            sessionHigh   = (not sessionHigh or newPrice > sessionHigh) and newPrice or sessionHigh
            sessionLow    = (not sessionLow  or newPrice < sessionLow)  and newPrice or sessionLow
            RecordPrice(newPrice)
            SaveState()
        end
    end

    if currentPrice and currentPrice > 0 then
        local color = GetTrendColor()
        self.text:SetText(color .. "Token:|r " .. FormatGold(currentPrice))
    else
        self.text:SetText("|cffffffffToken:|r ...")
    end
end

local function OnClick(self, btn)
    if btn == "LeftButton" then
        lastRequest = 0  -- force refresh on next OnUpdate tick
        RequestPrice()
    end
end

local function OnEnter(self)
    DT.tooltip:ClearLines()
    DT.tooltip:AddLine("WoW Token Price", 1, 1, 1)
    DT.tooltip:AddLine(" ")

    if currentPrice and currentPrice > 0 then
        local gold   = floor(currentPrice / 10000)
        local silver = floor((currentPrice % 10000) / 100)
        local copper = currentPrice % 100
        DT.tooltip:AddDoubleLine(
            "Current:",
            string.format("|cffffd700%s|r g  |cffc0c0c0%d|r s  |cffb87333%d|r c",
                BreakUpLargeNumbers(gold), silver, copper),
            1, 1, 1, 1, 1, 1
        )

        if previousPrice and previousPrice > 0 then
            local diff = currentPrice - previousPrice
            local pct  = (diff / previousPrice) * 100
            local sign = diff >= 0 and "+" or ""
            local col  = diff > 0 and "|cff00ff00" or (diff < 0 and "|cffff4444" or "|cffffffff")
            DT.tooltip:AddDoubleLine(
                "Change:",
                string.format("%s%s%dg (%.2f%%)|r", col, sign, floor(diff / 10000), pct),
                1, 1, 1, 1, 1, 1
            )
        end

        DT.tooltip:AddLine(" ")
        DT.tooltip:AddDoubleLine(
            "Last updated:",
            "|cffaaaaaa" .. FormatAge(lastUpdated) .. "|r",
            1, 1, 1, 1, 1, 1
        )
        local remaining = max(0, REFRESH_INTERVAL - floor(GetTime() - lastRequest))
        DT.tooltip:AddDoubleLine(
            "Next refresh:",
            "|cffaaaaaa" .. FormatDuration(remaining) .. "|r",
            1, 1, 1, 1, 1, 1
        )

        if sessionHigh and sessionLow then
            DT.tooltip:AddDoubleLine(
                "Session range:",
                string.format("|cffffd700%s|r – |cffffd700%s|r",
                    BreakUpLargeNumbers(floor(sessionLow / 10000)),
                    BreakUpLargeNumbers(floor(sessionHigh / 10000))),
                1, 1, 1, 1, 1, 1
            )
        end

        local sparkline, minPrice, maxPrice = BuildSparkline()
        if sparkline then
            local oldest = priceHistory[1]
            local historyAge = oldest and (time() - oldest.time) or 0
            local hh = floor(historyAge / 3600)
            local mm = floor((historyAge % 3600) / 60)
            local ageStr = hh > 0 and string.format("%dh %dm", hh, mm) or string.format("%dm", mm)

            DT.tooltip:AddLine(" ")
            DT.tooltip:AddLine("|cffaaaaaaPrice history (" .. ageStr .. " span):|r", 1, 1, 1)
            DT.tooltip:AddLine(sparkline, 1, 1, 1)
            DT.tooltip:AddDoubleLine(
                string.format("|cffaaaaaa Low: |cffffd700%sg|r", BreakUpLargeNumbers(floor(minPrice / 10000))),
                string.format("|cffaaaaaa High: |cffffd700%sg|r", BreakUpLargeNumbers(floor(maxPrice / 10000))),
                1, 1, 1, 1, 1, 1
            )
        end

        DT.tooltip:AddLine(" ")
        DT.tooltip:AddLine("|cff888888Left-click to force refresh|r", 1, 1, 1)
    else
        DT.tooltip:AddLine("Price not yet loaded.", 1, 0.5, 0.5)
        DT.tooltip:AddLine("|cff888888Left-click to request price|r", 1, 1, 1)
    end

    DT.tooltip:Show()
end

local function OnLeave()
    DT.tooltip:Hide()
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, arg1)
    if arg1 == "ElvUI_WoWTokenPrice" then
        LoadState()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

DT:RegisterDatatext(
    "WoW Token Price",
    nil,
    { "PLAYER_ENTERING_WORLD", "TOKEN_MARKET_PRICE_UPDATED" },
    OnEvent,
    OnUpdate,
    OnClick,
    OnEnter,
    OnLeave,
    "WoW Token Price"
)
