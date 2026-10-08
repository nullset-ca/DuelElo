-- UI/Art.lua: every image DuelElo shows comes from WoW's own art (we ship none).
-- Each lookup has a fallback, because WoW Forever has no rated PvP and may lack
-- some of it: rank emblems fall back to a tinted icon, markers to tinted icons.
local _, ns = ...

local FALLBACK_ICON = 134400  -- question mark; exists in every client
local GREY = { 0.6, 0.6, 0.6 }

-- Dev: /duelelo art <normal|noapi|noart> simulates clients missing art.
local artMode = "normal"

local atlasCache = {}
local function hasAtlas(name)
    if artMode == "noart" then return false end
    if atlasCache[name] == nil then
        atlasCache[name] = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)) ~= nil
    end
    return atlasCache[name]
end

-- SetTexture can't tell us a file is missing (it reports success for anything),
-- but GetFileIDFromPath returns nil for paths the client doesn't have.
local function fileExists(path)
    if artMode == "noart" then return false end
    if not GetFileIDFromPath then return true end
    return GetFileIDFromPath(path) ~= nil
end

local function showFallback(region, rgb)
    region:SetTexture(FALLBACK_ICON)
    region:SetDesaturated(true)
    region:SetVertexColor(rgb[1], rgb[2], rgb[3])
end

local function showNormal(region)
    region:SetDesaturated(false)
    region:SetVertexColor(1, 1, 1)
end

---------------------------------------------------------------------------
-- Rank emblems: WoW's rated-PvP tier icons, in Blizzard's order.
---------------------------------------------------------------------------

local EMBLEM_ORDER = { "UNRANKED", "COMBATANT", "CHALLENGER", "RIVAL", "DUELIST", "ELITE" }

-- The same icons by path (file IDs 2023043..2023053 on retail 12.1), for
-- clients whose PvP tier data is missing but whose art files are still there.
local KNOWN_EMBLEM_PATHS = {
    UNRANKED   = "Interface\\PVPFrame\\Icons\\UI_RankedPvP_01",
    COMBATANT  = "Interface\\PVPFrame\\Icons\\UI_RankedPvP_02",
    CHALLENGER = "Interface\\PVPFrame\\Icons\\UI_RankedPvP_03",
    RIVAL      = "Interface\\PVPFrame\\Icons\\UI_RankedPvP_04",
    DUELIST    = "Interface\\PVPFrame\\Icons\\UI_RankedPvP_05",
    ELITE      = "Interface\\PVPFrame\\Icons\\UI_RankedPvP_06",
}

local emblems

local function loadEmblems()
    emblems = {}
    local fromApi = {}
    if artMode == "normal" and C_PvP and C_PvP.GetPvpTierInfo then
        local byEnum, enums = {}, {}
        for id = 0, 200 do
            local ok, info = pcall(C_PvP.GetPvpTierInfo, id)
            local e = ok and type(info) == "table" and info.pvpTierEnum
            if e and info.tierIconID and not byEnum[e] then
                byEnum[e] = info.tierIconID
                enums[#enums + 1] = e
            end
        end
        table.sort(enums)
        for i, e in ipairs(enums) do
            if EMBLEM_ORDER[i] then fromApi[EMBLEM_ORDER[i]] = byEnum[e] end
        end
    end
    for _, key in ipairs(EMBLEM_ORDER) do
        if fromApi[key] then
            emblems[key] = fromApi[key]
        elseif fileExists(KNOWN_EMBLEM_PATHS[key]) then
            emblems[key] = KNOWN_EMBLEM_PATHS[key]
        end
    end
end

local function tierColor(key)
    for _, t in ipairs(ns.Elo.TIERS) do
        if t.key == key then return t.color end
    end
    return GREY
end

-- Put the emblem for a tier key ("UNRANKED", "COMBATANT", ...) on a texture region.
function ns.SetEmblem(region, key)
    if not emblems then loadEmblems() end
    key = key or "UNRANKED"
    if emblems[key] then
        region:SetTexture(emblems[key])
        showNormal(region)
    else
        showFallback(region, tierColor(key))
    end
end

---------------------------------------------------------------------------
-- Leaderboard markers
--   SILVER (top 100): rare-mob silver dragon
--   GOLD   (top 10):  elite-mob gold dragon
--   FIRST  (#1):      gold dragon + crown + pulsing golden glow
---------------------------------------------------------------------------

local DRAGON = {
    GOLD = "nameplates-icon-elite-gold",
    SILVER = "nameplates-icon-elite-silver",
    FIRST = "nameplates-icon-elite-gold",
}
local CROWN = "groupfinder-icon-leader"

local function setMarker(m, key)
    if not key or not DRAGON[key] then
        m.glowAnim:Stop()
        m:Hide()
        return
    end
    m:Show()
    if hasAtlas(DRAGON[key]) then
        m.dragon:SetAtlas(DRAGON[key])
        showNormal(m.dragon)
    else
        showFallback(m.dragon, key == "SILVER" and { 0.8, 0.8, 0.85 } or { 1, 0.8, 0.2 })
    end
    local first = key == "FIRST"
    m.crown:SetShown(first and hasAtlas(CROWN))
    m.glow:SetShown(first)
    if first then m.glowAnim:Play() else m.glowAnim:Stop() end
end

-- A size x size marker. The crown sits inside the box so scroll lists don't clip it.
function ns.CreateMarker(parent, size)
    local m = CreateFrame("Frame", nil, parent)
    m:SetSize(size, size)

    m.glow = m:CreateTexture(nil, "BACKGROUND")
    m.glow:SetTexture("Interface\\Cooldown\\star4")
    m.glow:SetBlendMode("ADD")
    m.glow:SetVertexColor(1, 0.8, 0.2)
    m.glow:SetSize(size * 1.8, size * 1.8)
    m.glow:SetPoint("CENTER", 0, -size * 0.1)
    m.glowAnim = m.glow:CreateAnimationGroup()
    m.glowAnim:SetLooping("BOUNCE")
    local a = m.glowAnim:CreateAnimation("Alpha")
    a:SetFromAlpha(0.35)
    a:SetToAlpha(0.95)
    a:SetDuration(1.1)
    a:SetSmoothing("IN_OUT")

    m.dragon = m:CreateTexture(nil, "ARTWORK")
    m.dragon:SetSize(size * 0.82, size * 0.82)
    m.dragon:SetPoint("BOTTOM")

    m.crown = m:CreateTexture(nil, "OVERLAY")
    if hasAtlas(CROWN) then m.crown:SetAtlas(CROWN) end
    m.crown:SetSize(size * 0.55, size * 0.4)
    m.crown:SetPoint("TOP", 0, 1)

    m.SetMarker = setMarker
    m:Hide()
    return m
end

function ns.SetArtMode(mode)
    if mode ~= "normal" and mode ~= "noapi" and mode ~= "noart" then return false end
    artMode = mode
    emblems = nil
    return true
end
