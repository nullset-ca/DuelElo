-- BannedAuras.lua: buffs that make a duel unfair, mirroring the Forever Open
-- tournament bans (world buffs, holiday/event buffs, campfire buffs, quest and
-- world-objective buffs). Having any of these blocks ranked (readiness bit 16).
-- Spell IDs are from the classic-era clients; every one is marked
-- "verify in Forever" until probe v2 confirms the IDs there.
local _, ns = ...

ns.BANNED_AURAS = {
    -- World buffs
    [22888] = "Rallying Cry of the Dragonslayer",  -- Onyxia/Nefarian head; verify in Forever
    [16609] = "Warchief's Blessing",               -- Rend head; verify in Forever
    [24425] = "Spirit of Zandalar",                -- Hakkar heart; verify in Forever
    [15366] = "Songflower Serenade",               -- Felwood songflower; verify in Forever
    [22817] = "Fengus' Ferocity",                  -- Dire Maul tribute; verify in Forever
    [22818] = "Mol'dar's Moxie",                   -- Dire Maul tribute; verify in Forever
    [22820] = "Slip'kik's Savvy",                  -- Dire Maul tribute; verify in Forever

    -- Darkmoon Faire (Sayge's fortunes)
    [23768] = "Sayge's Dark Fortune of Damage",    -- verify in Forever
    [23736] = "Sayge's Dark Fortune of Agility",   -- verify in Forever
    [23766] = "Sayge's Dark Fortune of Intelligence", -- verify in Forever
    [23738] = "Sayge's Dark Fortune of Spirit",    -- verify in Forever
    [23737] = "Sayge's Dark Fortune of Stamina",   -- verify in Forever
    [23735] = "Sayge's Dark Fortune of Strength",  -- verify in Forever
    [23767] = "Sayge's Dark Fortune of Armor",     -- verify in Forever
    [23769] = "Sayge's Dark Fortune of Resistance", -- verify in Forever

    -- Campfire
    [7353]  = "Cozy Fire",                         -- Basic Campfire spirit buff; verify in Forever

    -- Quest / world-objective buffs
    [29534] = "Traces of Silithyst",               -- Silithus PvP objective; verify in Forever

    -- Holiday buffs: none seeded yet. Add their IDs once confirmed on Forever
    -- (the tournament rules ban them, but the IDs differ between clients).
}
