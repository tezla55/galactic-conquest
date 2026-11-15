# GunGame (vendored, minimal changes)

Verbatim copy of the `GunGame` example plugin from KYBER's own community examples repo,
fetched 2026-09-11:

https://github.com/ArmchairDevelopers/PluginExamples/tree/main/GunGame

`LICENSE` is that repo's own MIT license, copied alongside per its terms (Copyright (c) 2024
Armchair Developers). Reverted back to this minimal state 2026-09-11 after a round of
internal-logic patches (case fixes, type guards, bot checks) turned out to be chasing
symptoms, not the real problem — see below. Exactly two changes from upstream now, both
tiny:

1. **`server/admins.lua`**: added the user's own EA player ID, `2755533100` ("DrTezla"),
   alongside the two original authors' — found in the user's own KYBER logs
   (`"DrTezla (2755533100) successfully authenticated"`, multiple sessions). Unlocks
   GunGame's debug slash-commands (`/testanakin`, `/setscore <n>`, etc.).

2. **`server/__init__.lua`**: one call commented out (not deleted). Upstream unconditionally
   runs `if debugMode then CompleteReset() end` right after registering its event listeners
   — at *plugin-load* time, since `debugMode` is forced true (`... or true`) a few lines up.
   `CompleteReset()` calls `PlayerManager.GetPlayers()` and `Player:SetTeam()`, which is fine
   once a level/server exists, but is called here before any server exists at all. Confirmed
   live and 100% reproducible, 3/3 attempts: SWBF2 hard-crashed (no window ever opened)
   within ~100ms of the plugin loading, every single time this line ran. `CompleteReset()`
   is still called correctly, unconditionally, from `Level:Loaded` elsewhere in the same
   file — the safe point, once a real level exists.

Everything else — `plugin.json`, `common/sdk.lua`, `server/{bfplus_gun_list,vanilla_gun_list,
input_blocks}.lua` — is byte-identical to upstream (verified with `diff -r` at revert time).

## The real problem (found after reverting the internal patches)

None of GunGame's own logic bugs (found and fixed, then reverted per above — see git history
of this file if that detail is ever needed again) explain why the mod never actually starts:
across every match captured, `Level:Loaded`'s own effects (`CompleteReset()`'s gun-list
randomization, the "Welcome to Blaster Master" broadcast) have **never once fired** — no
output, no error, it just never runs.

Traced this into KYBER's own module source (`ArmchairDevelopers/Kyber`, `ver/beta10`) rather
than guess further. `Level:Loaded` is fired from exactly one place a listen server can reach,
`InitLevelSetup()` (`Module/Source/Core/Server.cpp`), which is called from exactly two
places in the whole module:

- `GameSimulationInitDedicatedServerHk` (`Program.cpp`) — hardcodes `isDedicated = true`.
  Not us; this is the real dedicated-server (`kyber-server` Docker/CLI) boot path only.
- `Server::LoadNextLevel()` — called by (a) the native `LoadLevel` console command (what GC's
  own `gc_result` plugin uses for every battle — `Console.Execute("LoadLevel <level> <mode>")`
  — which is exactly why `Level:Loaded` fires reliably for it every time), and (b)
  `Server::Start()`, which is what the KYBER Launcher's own **Host / START SERVER** button
  calls (the `StartServer` gRPC → `ServerInterfaceService::StartServer` →
  `g_program->m_server->Start(info)`, `changeState` defaulting to `true` → `LoadNextLevel`).

So mechanically, `Level:Loaded` *should* fire the moment a match is started through KYBER
Launcher's own Host button — same as it does for `gc_result`. If it isn't firing, the
likeliest explanation is that the match was started some other way instead: SWBF2's own
in-game multiplayer/host menu (bypassing KYBER's `StartServer` RPC and `Server::Start`
entirely — the module is present and its hooks/EventManager are live, but nothing ever calls
the one function that fires `Level:Loaded`), Instant Action (documented elsewhere in this
project to never fire `Level:Loaded` at all), or joining a server someone else is already
hosting rather than hosting it yourself. **Needs the user to confirm exactly how they started
the match** — through the KYBER Launcher's own Host/Start Server control, or some other way —
to settle which of these it is.

**Why it's here:** the user wanted to play a real KYBER community plugin themselves to see
its mechanics live in-game (progressive weapon-on-kill, forced team, special-kit blocking
via `Player:SetInputEnabled`) — partly for its own sake, partly because `input_blocks.lua`'s
kit-gating technique is a candidate lever for GC's own (currently unimplemented) unit-buying
system. See `CLAUDE.md`'s KYBER section for the full context.

**This is not part of Galactic Conquest's own plugin** (`bridge/kyber_plugin/gc_result/`).
`KyberPluginInstaller.launch_gungame_playtest()` packages and launches KYBER with *only*
this plugin active — `gc_result` does not load at the same time, so GC's own campaign
reporting does nothing during a GunGame playtest session. Launch KYBER normally
("Launch KYBER with GC plugin") again afterward to go back to campaign play.

**Playing it**: GunGame doesn't pick a map itself — click **Host** (or **Start Server**) in
the KYBER Launcher itself and choose any multiplayer map/mode (a Blast/Team Deathmatch-style
mode matches its design best). It works for every player automatically from there — once
`Level:Loaded` is actually reaching it.
