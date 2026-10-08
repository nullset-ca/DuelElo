-- Leaderboard.lua: ranking players and assigning markers (no WoW API).
local _, ns = ...

local LB = {}
ns.Leaderboard = LB

LB.GOLD_CUTOFF = 10      -- positions 2..10 get the gold dragon
LB.SILVER_CUTOFF = 100   -- positions 11..100 get the silver dragon
LB.MAX_AGE = 30 * 86400  -- players not heard from in this long drop off the board

-- Marker key for a leaderboard position: "FIRST", "GOLD", "SILVER" or nil.
function LB.Marker(pos)
    if not pos then return nil end
    if pos == 1 then return "FIRST" end
    if pos <= LB.GOLD_CUTOFF then return "GOLD" end
    if pos <= LB.SILVER_CUTOFF then return "SILVER" end
    return nil
end

-- players: ["Name-Realm"] = { rating, games, class, w, l, seen, source }
-- self:    { name, rating, games, class, w, l } for the local character (always fresh)
-- now:     current time(); entries with seen older than MAX_AGE are skipped (optional)
-- Returns a sorted list of { name, rating, games, class, w, l, pos, marker, isMe, verified }
-- (only players who finished placements) and the local character's position.
-- verified = we dueled them ourselves (source "met"); everything else is self-reported.
function LB.Build(players, self, now)
    local list = {}
    local function add(name, p, isMe)
        if type(p) ~= "table" or type(p.rating) ~= "number" then return end
        if (p.games or 0) < ns.Elo.PLACEMENTS then return end
        if not isMe and now and p.seen and now - p.seen > LB.MAX_AGE then return end
        list[#list + 1] = {
            name = name, rating = p.rating, games = p.games, class = p.class,
            w = p.w or 0, l = p.l or 0, isMe = isMe, verified = isMe or p.source == "met" or p.source == nil,
            source = p.source, seen = p.seen,
        }
    end
    for name, p in pairs(players or {}) do
        if not (self and name == self.name) then add(name, p, false) end
    end
    if self then add(self.name, self, true) end

    table.sort(list, function(a, b)
        if a.rating ~= b.rating then return a.rating > b.rating end
        if a.games ~= b.games then return a.games > b.games end
        return a.name < b.name
    end)

    local myPos
    for i, e in ipairs(list) do
        e.pos = i
        e.marker = LB.Marker(i)
        if e.isMe then myPos = i end
    end
    return list, myPos
end
