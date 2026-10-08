-- UI/Tooltip.lua: official DuelElo rank, badges and ladder bans on player
-- unit tooltips (SPEC §3.8), when the DuelElo_Ladder data addon is installed.
local _, ns = ...
local L = ns.L

local GOLD = { 1, 0.82, 0 }

-- Lines to add for "Name-Realm": { text, r, g, b } (empty when not on the ladder).
function ns.TooltipLines(full)
    local e = full and ns.OfficialEntry(full)
    if not e then return {} end
    local r = ns.Elo.Rank(e.rating)
    local lines = { { L["DuelElo: %s  ·  %d%s"]:format(r.label, e.rating, e.rank and ("  ·  #%d"):format(e.rank) or ""),
        r.color[1], r.color[2], r.color[3] } }
    for _, b in ipairs(e.badges) do lines[#lines + 1] = { ns.Ladder.BadgeName(b), GOLD[1], GOLD[2], GOLD[3] } end
    if e.banned then lines[#lines + 1] = { L["Banned from the DuelElo ladder"], 1, 0.25, 0.25 } end
    return lines
end

local function onUnitTooltip(tooltip)
    if tooltip ~= GameTooltip or not (tooltip.GetUnit and DuelEloLadderData) then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not ok or ns.IsSecret(unit) or not unit or not (UnitIsPlayer and UnitIsPlayer(unit)) then return end
    for _, l in ipairs(ns.TooltipLines(ns.UnitFullName(unit))) do tooltip:AddLine(l[1], l[2], l[3], l[4]) end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, onUnitTooltip)
elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetUnit", onUnitTooltip)  -- clients without the tooltip data API
end
