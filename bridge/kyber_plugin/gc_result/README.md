# `gc_result` — Galactic Conquest match-result plugin

A server-realm KYBER Lua plugin. On `Level:Complete` it tallies each team's score and
sends one line of JSON to any TCP client connected on `127.0.0.1:45702`. That is how the
GC campaign learns who won a battle — **KYBER has no result RPC, event, or round-end log
line** (verified against the Module source).

## Installing it — from the GC app (recommended)

KYBER's module only loads a server plugin named by `KYBER_SERVER_PLUGINS_PATH` /
`KYBER_DEV_PLUGIN_PATH` (verified from `Module/Source/Script/ScriptManager.cpp`). The
desktop Launcher scans no folder and never sets those. So GC does it:

1. Run GC → **KYBER Setup…** (button in the side panel, Windows only).
2. The path to `kyber_launcher.exe` auto-fills (from the Start Menu shortcut); fix it if
   needed.
3. **Launch KYBER with GC plugin.** GC packages this folder into
   `<GC user data>\GalacticConquest\gc_result.kbplugin` — a writable folder, **not** next to
   `kyber_launcher.exe` (which under `C:\Program Files\` would need admin rights) — sets
   `KYBER_SERVER_PLUGINS_PATH` **in the KYBER process it starts** (nothing written to your
   registry / profile — the same mechanism KYBER uses for its own variables), and starts
   KYBER.
4. **Caveat:** the plugin only loads into a KYBER that GC started. If KYBER is already
   open, GC tells you — close it and use **Close KYBER and relaunch**.
5. Host a match. Confirm it loaded: newest file in
   `%AppData%\ArmchairDevelopers\Kyber\Logs\kyber_<date>.log` shows
   `[gc_result] listening on 127.0.0.1:45702`.

**Uninstall** (same dialog) deletes the `.kbplugin`. There is nothing else to undo.

### Manual alternative

Set a Windows environment variable `KYBER_SERVER_PLUGINS_PATH` to a folder containing a
packaged `gc_result.kbplugin` (or `KYBER_DEV_PLUGIN_PATH` straight at this unzipped
folder), then restart the Launcher.

## Layout (required — verified from `ScriptManager.cpp`)

```
gc_result/
  plugin.json          {"name": "gc_result"}   <- must be plugin.json, at the archive root
  server/
	__init__.lua       the entry point KYBER auto-runs for the server realm
```

`main.lua` / `manifest.json` do **not** work.

## Wire protocol (`bridge/kyber_link.gd` on the GC side)

**GC → plugin** — one plain-text command per line:

| Line | Effect |
| --- | --- |
| `load <lvl> <mode> [botsT1 botsT2 [aimNoise [bpT1 bpT2 [maxSec margin]]]]` | `LoadLevel`; arm a result; **start managing** this match; store per-team bot / difficulty / BP-floor / auto-end targets. Co-op (`Mode9`/`ModeDefend`) uses a gentler start profile: only `Whiteshark.LobbyThreshold 1` before the load, no `SkipLobby`/`DisableStartupFlow`, and the `startgame` fallback waits 12 s and is skipped if the human already spawned. Other modes keep the full start-command set. `maxSec margin` = `0 0` for co-op / GA / starfighter |
| `bots <n> [n2]` | per-team bot targets (`MIN_BOTS` only replaces an unparseable value); sets `AutoPlayers.ForceFillGameplayBotsTeam1/2`, applies them (`ForceApplyGameplayBotsCount`), and stops the server autofilling past them (`AllowAddAutoFillPlayers false`, `AllowRemoveAutoFillPlayers true`) |
| `bp <n> [n2]` | per-team Battle-Point **floor** for each bot |
| `autoend <maxSec> <margin>` | Supremacy: end after `maxSec`, or a `margin`-kill lead; `0 0` = off |
| `diff <aimNoise>` | `AutoPlayers.AimNoiseScale` — lower is harder, `0` = perfect aim |
| `start` | re-run the start commands (`Kyber.startgame`, `Whiteshark.SkipLobby` …) |
| `groundwin <1\|2>` | team N won the Clone Wars ground phase → `Kyber.endgameteam<N>` once, skipping the capital-ship phase (GC sends it when the ship sub-level streams into the log) |
| `end [1\|2]` | emit the result + a single `Restart`; optional forced winner (testing) |
| `ping` | plugin replies `{"type":"pong"}` |

- **Managing.** The plugin only drives a level GC `load`ed — start cvars, bot fill, BP
  floor, the Supremacy auto-end. Once the result is emitted it goes **passive**: it still
  reports and accepts connections, but never force-starts a level. Force-starting KYBER's
  own auto-advanced rotation level mid-teardown thrashed the listen-server client into a
  crash; passivity is the fix.
- **Start commands** (`run_start_cmds`): `Whiteshark.SkipLobby/LobbyThreshold/DisableStartupFlow`
  **and** `Kyber.startgame` / `startgame` — run in the `load` handler (before `LoadLevel`),
  at a managed `Level:Loaded`, ~12 s later, and on the `start` command. KYBER has no
  documented force-start; an unknown command is a harmless no-op.
- **Auto-end is Supremacy only.** When `maxSec > 0` the plugin ends the match at `maxSec`
  (360) or a `margin`-kill lead (40, after 90 s), then a single `Console.Execute("Restart")`
  — no `Kyber.Restart`. This lands the result in the ground phase; nothing skips the
  capital-ship phase. A `Broadcast` chat line warns players at T-30 s, T-10 s, and on the
  end. **Co-op / GA / starfighter send `0 0` and play to the game's own finish** — reported
  on `Level:Complete` or the rotation-advance `Level:Loaded`, no `Restart`.
- **Winner** (`pick_winner`): the end-of-round persistence `score` when it is populated and
  the teams differ (a natural finish), otherwise the live **kill tally** —
  `ServerPlayer:Killed(victim, inflictor, weapon)` → `kill_tally[inflictor.team] += 1`,
  reset each `Level:Loaded` (persistence score/kills read 0 mid-match, so a cut-short
  Supremacy match always uses the tally). `emit_result` writes the chosen number into
  `teams.N.score` (parser keys on `score`) and the tally into `teams.N.kills`.
- **Bots**: filled per team every level load + every ~10 s below target; every ~20 s
  `fund_bots` **floors** each bot's BP at its side's grant (`if battlepoints < grant`) so a
  low-funded side (no fleet in the fight) is never handed hero money and a well-funded one
  always can afford one. `Whiteshark.MaximumBattlepoints 30000` lifts the cap. **Whether
  the AI spends it on specials/heroes at all is base-game behaviour — stock Supremacy / GA
  AI does not; that needs the IOI Nexus mod in the KYBER hosting collection.**

**plugin → GC** — one JSON object per line:

| `type` | When | Fields |
| --- | --- | --- |
| `hello` | on connect | — |
| `level` | `Level:Loaded` | `map`, `mode` |
| `gc_result` | round end — see below | `seq`, `map`, `mode`, `teams`, `winner_team`, `reason` |
| `pong` | reply to `ping` | — |

```json
{"type":"gc_result","v":1,"seq":3,
 "map":"S7_1/Levels/Kamino_03/Kamino_03","mode":"Mode1",
 "teams":{"1":{"score":58,"kills":58,"deaths":41,"players":20},
		  "2":{"score":37,"kills":37,"deaths":58,"players":20}},
 "winner_team":1,"reason":"kills"}
```

- Reported on **`Level:Complete`, the next unexpected `Level:Loaded`, or right after an
  `end` command** (KYBER's rotation auto-advances after a round; `Level:Complete` is
  unreliable on a listen server). `seq` increments per report so GC drops the duplicate;
  a reconnecting GC also gets the last result re-sent right after `hello`.
- `reason` is `"score"` (game's own end-of-round score — reads 0 for every mode in this
  build), `"blast kills N-M"` (**Blast only** — a kill race to 100, decided by the higher
  tally; kills are NOT used for objective modes, where they mis-report), `"coop: attackers
  did not complete"`, `"forced"` (an `end 1|2` / the capital-ship-skip `override_winner`),
  or `"no score"` (Supremacy / GA — GC reads the winner from KYBER's log instead, or the
  player uses the manual buttons).
- `winner_team` — `1`, `2`, or `0` (undetermined).
- `teams.N.score` carries whichever number decided it; `teams.N.kills` is always the live
  tally. `deaths` / `players` come from the
  player snapshot.
- Which faction is team `1` depends on the map; GC resolves it with `team_one_faction`
  in `data/maps.json` (currently a guess — confirm from a capture).

## If the plugin loads twice ("Failed to bind socket" in the log)

You have a leftover persistent `KYBER_DEV_PLUGIN_PATH` user env var. GC clears it in the
KYBER process it launches, but delete it for good (Windows → *Edit environment variables
for your account*). A duplicate instance now bails immediately instead of double-loading.

## Capturing a real result (flips `BattleResultParser.PLUGIN_CONTRACT_VERIFIED`)

Install the plugin, click **Host** in KYBER, run a bot match on a GC map, then in GC's
**Log** panel press **Save last result → fixture**. Headless alternative (note the `&`):

```powershell
& "C:\Users\tezla\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" `
  --headless --path E:\Godot\gc --script res://bridge/tools/capture_gc_result.gd
```

Both write the round-end line to `tests/fixtures/gc_result_sample.json`. Then set
`team_one_faction` for those maps in `data/maps.json` from which `team` id was the
Republic, set `BattleResultParser.PLUGIN_CONTRACT_VERIFIED = true`, and delete
`test_plugin_contract_is_still_unverified`.
