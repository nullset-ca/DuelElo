# Changelog

## v0.6.0 (unreleased)
**Official ladder update — ranked dueling for WoW Forever.**
- **Upload your duels** to the official WoW Forever ladder at
  **duelelo.com**: `/duelelo upload` (or the new *Upload* tab) creates
  an upload code; paste it on the site or use `/upload` with the DuelElo
  Discord bot. One upload also verifies your opponents' side of each duel.
- **Signed ranked duels:** both players' clients sign every ranked result
  with a per-character key, so nobody can invent or change a match.
- **Upload reminders:** a gentle reminder (once per session) when ranked duels
  are waiting to be verified, a badge on the Upload tab and a hint on the
  results screen. Turn them off in Settings (*Upload reminders*).
- **Verified by the community:** with the *DuelElo Ladder* data addon
  installed, History marks ranked duels the site confirmed (both players'
  signatures checked) with a ✔.
- Reports you made are sent to the moderators with your next upload.
- **Setup guide:** a short popup after your first login walks you through
  ranked duels, the rank widget and uploading. Skip it or run it again any
  time with `/duelelo setup` (also a button in the main window and Options).
- The rank widget is now off until you turn it on (`/duelelo widget show` or
  Options); the main window's Discord and Options buttons no longer overlap
  the tabs.
- **Stream-safe upload codes:** the code stays hidden in the copy box
  (Ctrl+C still copies it; *Show code* reveals it) and in the box on
  duelelo.com/upload, which also has a *Paste from clipboard* button.
- **Clearer ranked rules:** the setup guide has a "How ranked works" step,
  the ranked prompt has a **?** with the rules, and *Strict* is now called
  *Wait for cooldowns* (`/duelelo cooldowns on|off`; `strict` still works).
- Fixed: no duel was recorded on WoW Forever. Its names have surnames
  ("Duelio Vodee"), which DuelElo mistook for a realm; names now come from
  the whole name the game shows, on your real realm.
- DuelElo now targets WoW Classic Forever only. Retail still loads it with
  *Load out of date AddOns*, for development.
- Fixed: typing in the game's Settings search box blamed DuelElo for a
  blocked action. DuelElo's settings page now draws its own controls, which the
  search never touches.
- Fixed: on WoW Forever, challenging someone could print "No player named …"
  in chat. DuelElo now messages players on your realm by their plain name.
- Fixed: on WoW Forever the opponent's class could be missing, and your own
  characters could show up on the realm leaderboard from earlier test builds.
- Fixed: ranked was impossible on WoW Forever, which hides health and mana
  from addons. Those two checks now show as *unchecked* instead of blocking.
- Fixed: the hidden leaderboard channel could take `/1` and push General and
  Trade down a number. It now always stays behind every other channel and is
  left at logout, so the game can't rejoin it early.
- Fixed: challenging with `/duel` (no name, or `/duel Name`) now starts the
  ranked handshake like the right-click menu does.
- **Your build on the site:** when a duel starts, DuelElo notes your own gear,
  talents, buffs and which cooldowns were still running, and which major
  cooldowns you used during the duel. They go up with your next upload, so
  your profile shows your current build and every duel shows both players'
  builds. Only your own character is read; nothing is inspected.
- Keep your upload code private: it contains your character's key.

## v0.5.0 (unreleased)
**Fair Play update — ranked dueling for WoW Forever.**
- **Readiness check:** ranked duels need both players at 95% health and mana,
  out of combat and without banned buffs (world buffs, Darkmoon fortunes,
  campfire and objective buffs). The ranked prompt shows both sides' readiness;
  cooldowns and trinkets are shown but never block.
- **Strict mode** (`/duelelo strict on` or Settings): only agree to ranked when
  both sides' cooldowns and trinkets are ready too.
- **Same level** required for ranked, at any level. Your own characters can't
  play ranked against each other.
- **Fairer repeats:** a second ranked duel against the same player within 7 days
  counts half, the third a quarter, then not at all.
- **New rating system (Glicko-2).** Your rating is shown as an *estimate* until
  the official ladder confirms it. Ratings from the test versions are archived
  (shown as "Test-era rating") and everyone starts fresh with placements.
- **Report a duel** from the ranked results screen or the "!" button in your
  History: pick a reason, add a note. Reports go to the moderators with your
  next upload.
- **Rank widget** for streamers and everyone else: rank, recent W/L and rating
  trend in a small movable panel (`/duelelo widget`, Full / Compact / Minimal).
- Ranked needs DuelElo v0.5 on both sides; players on older versions get a
  "needs to update" notice and duel casually.
- Behind the scenes: ranked results are signed by both players' clients,
  groundwork for the official ladder website.
- Developer commands (`demo`, `test`, `art`, `debug`) now need `/duelelo dev on`.

## v0.4.4
- New community Discord for feedback, bug reports and ideas: `/duelelo discord`, the *Discord* button in the DuelElo window, or *Settings > AddOns > DuelElo*.

## v0.4.3
- Marked as compatible with WoW Forever (1.60.1) as well as Retail (12.1.0),
  so it no longer shows as out of date in Forever.

## v0.4.2
- Now also available on Wago Addons.
- Addon info now lists the author, license and website.

## v0.4.1
- First public release.
- Tracks every duel automatically: wins, losses, fled, opponent class, zone and duel length.
- Ranked duels between DuelElo players, agreed before the fight (Ranked / Casual prompt).
- ELO rating with 10 placement games and ranks from Combatant to Elite.
- League-style results screen with rank emblem, animated rating bar and promotion / demotion.
- Leaderboard of DuelElo players on your realm, with gold and silver elite dragons for the top 10 and top 100 and a crown for #1.
- History, Leaderboard and Stats tabs; options in Settings > AddOns > DuelElo.
