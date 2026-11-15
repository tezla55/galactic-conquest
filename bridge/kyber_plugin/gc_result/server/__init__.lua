-- Galactic Conquest - match control + result reporter (server realm)
--
-- GC talks to this plugin over a localhost TCP socket (127.0.0.1:GC_RESULT_PORT).
--
-- GC -> plugin (one plain-text command per line):
--   load <level> <mode> [botsT1 botsT2 [aimT1 aimT2 [bp1 bp2 [maxSec margin]]]]   switch map/mode; arm a result; start MANAGING it
--   bots <n> [n2]                                                per-team bot targets (trusted as sent; MIN_BOTS is only the unparseable-value fallback), apply now
--   label <team> <text>                                          name team 1/2 (faction + force) for the logs
--   heroprob <0..1>                                              AutoPlayers.HeroSpawnProbability_Gameplay — how often bots field a HERO (0 = never); GC scales it with the AI's fleet upgrades. Cleared on each `load`, re-sent after it.
--   humanteam <1|2>                                              move human player(s) onto this team (faction the player runs in GC) — single player / local hotseat, where there's only ever one physical player
--   teamid <playerId> <1|2|0>                                    pin ONE specific human (by EA id, from KYBER's own "<name> (<id>) successfully authenticated" log line) to a team, or 0 to un-pin — for ONLINE two-player, where a real human sits on both teams and one shared value can't express that; call once per known player, checked before `humanteam`
--   coopdef <1|2>                                                CO-OP: this team wins if the mission ends with no score (attackers failed)
--   stopeor <0|1|auto>                                          Whiteshark.StopEOR - auto (default) = ON only for capital-ship Supremacy (Mode1), OFF elsewhere (natural EOR); 1/0 override the next load
--   settings [name]                                              dump a Console.GetSettings object's fields; no arg = hunt list
--   diff <aimT1> [aimT2]                                         AutoPlayers.AimNoiseScaleTeam1 / Team2 (lower = deadlier)
--   say <text>                                                   broadcast one line into the match chat (campaign briefing / result)
--   groundwin <1|2>                                              team N won the Clone Wars ground phase -> Kyber.endgameteam<N>, skip the capital-ship phase (once per match)
--   start                                                        re-run the start commands (Kyber.startgame, lobby cvars)
--   end [1|2]                                                    emit the result + single Console "Restart"; optional forced winner (test)
--   restart                                                      match is over and GC has the result: managing=false + a single Console "Restart" so KYBER never runs its own end-of-round -> LoadNextLevel (empty rotation -> crash). No result emitted.
--   testeor                                                      DIAGNOSTIC ONLY: Console.Execute("endofround") — a real native (non-Kyber) command found in a live PluginExamples plugin; does not touch match state or emit a result
--   hero <assetPath>                                             DIAGNOSTIC ONLY: Player:SetCustomizationAsset(assetPath) on the first human found — e.g. "hero Gameplay/Kits/Hero/DarthVader/Kit_Hero_DarthVader" (confirmed live in PluginExamples); does not touch match state or emit a result
--   bpdump / bp / bpmax / autoend                                accepted but NO-OP — BP + time/kill auto-end are not levers in this build
--   ping                                                        -> {"type":"pong"}
--
-- The plugin only manages a level GC `load`ed (start cvars, bot fill, aim). Once the
-- result is emitted it goes passive so it never force-starts KYBER's own rotation levels
-- — doing that mid-teardown crashed the listen server. BP manipulation does NOT work in
-- this KYBER build (verified in-game); the winner is the end-of-round persistence SCORE
-- only, never a kill count.
--
-- plugin -> GC (one JSON object per line):
--   {"type":"hello"}                         on connect
--   {"type":"load_ack","running":bool,...}   right after a `load` — running=false means
--                                            no match is live (LoadLevel needs one; offline,
--                                            the player must start an Arcade / Instant Action
--                                            match by hand first)
--   {"type":"load_failed","code":..,"reason":..}  `load`ed but no real level switch followed.
--                                            code "instant_action" = LoadLevel only echoed
--                                            then failed "you aren't running a server" (bots
--                                            + aim still applied to the running match);
--                                            code "no_switch" = nothing happened at all
--   {"type":"level","map":..,"mode":..}      when a level loads (this is the load succeeding)
--   {"type":"gc_result","seq":N, ...}        when a round ends  (seq dedups the two report paths)
--   {"type":"pong"}
--
-- OFFLINE / INSTANT ACTION (verified in-game 2026-09-06): the plugin runtime is
-- hosting-independent — Server:UpdatePre, PlayerManager.GetPlayers(), the AutoPlayers.*
-- cvars (bot count + aim) and Broadcast ALL work in an Instant Action match. But
-- `LoadLevel` / `Restart` / `startgame` are KYBER-server-only: in IA they echo then fail
-- "This is a server command, and you aren't running a server!" (IA runs its own local
-- Frostbite server, but not KYBER's). Real IA level loads don't fire Level:Loaded either;
-- only KYBER's own LoadLevel echo does. So the offline flow is REDUCED: the player starts
-- Instant Action on exactly the target map + mode themselves, GC's `load` pushes bot
-- counts / aim / team onto it, and the result is reported by hand (Level:Complete does not
-- fire in IA). GC gets `load_failed code=instant_action` and guides accordingly.
--
-- Verified against KYBER source (branch ver/beta10):
--   * Console.Execute(cmd) enqueues a console command; "LoadLevel <lvl> <mode>" and the
--     "AutoPlayers.*" cvars (ForceFillGameplayBotsTeam1/2, AimNoiseScale) all work.
--   * Fire("Level:Loaded", level, mode) on every level change (host, our load, and KYBER's
--     own rotation auto-advance after a round). "Level:Complete" is unreliable on a listen
--     server, so we also report on the next unexpected "Level:Loaded".
--   * Supremacy phase 1 -> phase 2 is NOT a level reload, so bots are re-topped on a timer.
--   * client:Recv(len) -> str | nil (would-block) | "" (closed); client:Send(str).
--   * Supremacy/GA have NO Lua-readable winner. `ServerPlayer.score`/`.deaths` read 0/0;
--     ~65 score/ticket/winner field names all error; `_G` has no gamemode/ticket global;
--     Objective() is a HUD node; Level:Complete never fires; no round-end event fires.
--     Full history: docs/SUPREMACY_PHASE.md. Open leads (opt-in `probe`): a bundle-load
--     event carrying `Outro_Team<N>` (the winner), and LookupDataContainer(<EBX path>).
--     Until one lands, Supremacy/GA -> winner 0 -> GC's manual buttons.
--   * "Broadcast <msg>" is the only Lua chat.

local PLUGIN_BUILD = "2026-11-03a"  -- bump on every change; GC logs a mismatch so a stale
                                   -- plugin (KYBER not relaunched from GC) is obvious.
                                   -- '2026-09-18a': groundwin now follows Kyber.endgameteam<N>
                                   -- with a delayed native Restart (ground_restart_pending) —
                                   -- a live Supremacy crash right after groundwin looked like
                                   -- the same "empty rotation advance" crash class StopEOR
                                   -- already guards elsewhere, reached through a path StopEOR
                                   -- doesn't cover. Unverified — needs a live retest.
                                   -- '2026-09-13a': `teamid <playerId> <1|2|0>` — pins ONE
                                   --   specific human (by EA id) to a team, for online
                                   --   two-player (a real human on both teams, which the
                                   --   single shared `humanteam` value can't express). Checked
                                   --   before `humanteam` everywhere a player's team is
                                   --   (re)asserted; single player / local hotseat are
                                   --   unaffected since they never send it. UNVERIFIED LIVE —
                                   --   `player.playerId` itself is confirmed real (the
                                   --   vendored GunGame admins.lua already checks it against a
                                   --   hardcoded EA id list, live, successfully) but this
                                   --   specific new verb has not been tested against an actual
                                   --   two-human match yet.
                                   -- '2026-09-11e': GunGame's own `endofround`/error-hunting
                                   --   dead-ended, but its `SetCustomizationAsset` call
                                   --   (spawning as a hero kit, confirmed live in a real
                                   --   PluginExamples capture — "Gameplay/Kits/Hero/
                                   --   DarthVader/Kit_Hero_DarthVader") is worth testing on
                                   --   its own merits: if a heroes-unlocked-by-campaign-state
                                   --   system is ever worth reviving, this is a real, much
                                   --   simpler lever than the deleted `.fbmod`-swap approach.
                                   --   Added `hero <assetPath>` — DIAGNOSTIC ONLY, no match
                                   --   state or result touched — applies Player:
                                   --   SetCustomizationAsset(assetPath) to the first human
                                   --   found. New "Log -> Set hero kit" text field + button,
                                   --   pre-filled with the one confirmed-working path.
                                   -- '2026-09-11d': the user found the actual KYBER community
                                   --   plugin examples repo (ArmchairDevelopers/PluginExamples)
                                   --   — a `globals.lua` there is the OFFICIAL Lua API doc
                                   --   (confirms every event/field this file already relies on
                                   --   the hard way, nothing new there) and the "GunGame" example
                                   --   is a full custom gamemode built entirely in a plugin —
                                   --   proof this is possible at all, and it ends its own round
                                   --   with `Console.Execute("endofround")`, a real NATIVE
                                   --   (non-Kyber) console command we'd never tried. Added
                                   --   `testeor` — diagnostic only, does not touch match state
                                   --   or emit a result — to find out live whether it runs the
                                   --   game's own natural end-of-round sequence (which might
                                   --   finally fire ServerLevelCompletedMessage / Level:Complete,
                                   --   unlike "Restart") and/or decides its own winner.
                                   -- '2026-09-11c': the user played '2026-09-11b' through a
                                   --   real co-op defeat and captured it (KYBER_MESSAGE_DEBUG
                                   --   on) — turned up two of 11b's own bugs:
                                   --   (1) persist_score/_kills/_deaths/_assists were computed
                                   --   into emit_result()'s `rep` table but team_obj() (the
                                   --   hand-written JSON writer) never grew to match, so they
                                   --   were silently dropped on the way to the wire — the
                                   --   capture's gc_result line had no persist_* fields at
                                   --   all. Fixed: team_obj() now emits them.
                                   --   (2) COOP_RUNAWAY_CAP_S (240s, added '2026-09-11a') fired
                                   --   right on schedule at the 4-minute mark — but the SAME
                                   --   capture's real "Game ended, moving to next level" didn't
                                   --   land until 10m47s in. The cap pre-empted its own real
                                   --   signal 6+ minutes early: GC would have shown "no
                                   --   automatic winner" while the player was still mid-
                                   --   mission, and the real end then went unreported because
                                   --   `match_armed` was already false by the time it arrived.
                                   --   Combined with the FIRST '2026-09-11a' capture (which
                                   --   already showed a natural, different-map rotation
                                   --   advance at 13m46s, disproving the "same-level retry"
                                   --   theory the cap and its `coop_retried` companion clause
                                   --   were built on) — two live matches now agree co-op just
                                   --   takes ~11-14 minutes and rotates normally, same as every
                                   --   other mode. REVERTED both COOP_RUNAWAY_CAP_S and
                                   --   `coop_retried` entirely; co-op uses the plain one-hour
                                   --   RUNAWAY_CAP_S like everything else.
                                   -- '2026-09-11b': reading the actual KYBER module source
                                   --   (ArmchairDevelopers/Kyber, ver/beta10) turned up two
                                   --   fields on ServerPlayer never actually tried before —
                                   --   .kills / .assists, siblings of the verified-dead
                                   --   .score / .deaths on the same PersistenceServerPlayer-
                                   --   Extent struct (Script/LuaPlayerManager.cpp). snapshot()
                                   --   now also reads all four directly (persist_score /
                                   --   persist_kills / persist_deaths / persist_assists,
                                   --   pcall-wrapped) purely to compare against kill_tally
                                   --   (built independently from the ServerPlayer:Killed
                                   --   EVENT) on the next capture — NOT wired into
                                   --   pick_winner, informational only. (Shipped with a
                                   --   serializer bug — see '2026-09-11c' above.)
                                   -- '2026-09-11a': a live co-op defeat (Republic defending
                                   --   the Venator) was reported as "not reported to GC at
                                   --   all" — a FRESH capture the same day
                                   --   (logs_2026-09-11_08-44-21) disproved the first theory
                                   --   (a same-level retry loop silently resetting
                                   --   managed_elapsed forever): the log shows KYBER's own
                                   --   rotation legitimately advancing to an unrelated map
                                   --   (Tatooine_01) 13m46s in, the EXISTING rotation-advance
                                   --   Level:Loaded handler firing correctly, GC receiving
                                   --   `{"winner_team":0,"reason":"no score"}`, staging it,
                                   --   and broadcasting "no clear winner (0-0) — use the
                                   --   manual buttons" back into match chat — all working as
                                   --   designed. So the report DID arrive; there was no
                                   --   automatic winner to give (co-op genuinely has no score
                                   --   or outro signal, confirmed again in this same capture —
                                   --   zero Outro_Team lines near the match end). This build
                                   --   ALSO added a same-level-reload clause + a separate
                                   --   240s cap for co-op, both reverted in '2026-09-11c'
                                   --   above once a second capture disproved the theory
                                   --   behind them.
                                   -- '2026-09-10a': co-op (Mode9 / ModeDefend, incl. the
                                   --   Clone Wars capital-ship boarding lanes) no longer
                                   --   auto-guesses a winner from `coopdef` — the plugin
                                   --   can't actually read whether the boarders cleared the
                                   --   ship, so it was wrong ~half the time. Co-op -> winner
                                   --   0 -> GC's manual buttons, like Supremacy/GA.
                                   -- '2026-09-09i': Blast winner = highest kill tally (it's a
                                   --   kill race to 100, no score/ticket signal). Kills stay
                                   --   excluded for Supremacy/GA (objective modes).
                                   -- '2026-09-09h': adopt-on-live. A small/fast map (Blast,
                                   --   some GA) fires only ONE Level:Loaded and it lands
                                   --   inside REAL_LOAD_MIN_S — judged an echo, so the plugin
                                   --   used to "give up" after 15 s and send a scary
                                   --   load_failed even though the match was running fine.
                                   --   Now: echo seen + ADOPT_MIN_S passed + a human on a
                                   --   team -> adopt the load as real (send `level`, manage
                                   --   it). load_failed only when NO match is live.
                                   -- '2026-09-09g': `groundwin <1|2>` command. GC watches
                                   --   KYBER's log for the capital-ship sub-level streaming
                                   --   in (`<level>/Venator|Dreadnought … into compartment`,
                                   --   [info] level) — that means a team won the ground phase
                                   --   — and sends `groundwin <winner>`; the plugin fires
                                   --   `Kyber.endgameteam<N>` (a DICE ConsoleCommandTrigger,
                                   --   user-verified) ONCE to end the match there, skipping
                                   --   the bot-broken capital-ship phase. Clone Wars only;
                                   --   GCW Supremacy has no ship phase so GC never sends it.
                                   -- '2026-09-09f': rotation-advance emit bug + winner moved
                                   --   OUT of the plugin.
                                   --   * The 09-09e engine-message bindings (OnlineNetworkEnd-
                                   --     OfRoundStateMessage etc.) did NOT fire — EventManager
                                   --     does not surface engine message classes. Kept as
                                   --     harmless no-ops; not a live lead.
                                   --   * BUG: when a hosted `load`'s Level:Loaded lands inside
                                   --     REAL_LOAD_MIN_S it's judged a LoadLevel echo and
                                   --     `level_name` never gets set — so the rotation-advance
                                   --     emit guard (`level_name ~= ""`) was FALSE and the
                                   --     plugin went on to "manage" the rotation level
                                   --     (Geonosis_02) instead of emitting. Now a long
                                   --     `managed_elapsed` (ECHO_MATCH_MIN_S) also counts as
                                   --     "a real match ran under us" -> emit, don't manage.
                                   --   * The Supremacy/GA winner is now read GC-side from
                                   --     KYBER's own daily log (`<level>/Outro_Team<N>` +, at
                                   --     debug level, `In_VictoryDeclarationTeam<N>Won`), which
                                   --     GC already tails. The plugin can't see those lines;
                                   --     this build just stops it making things worse.
                                   -- '2026-09-09b/c/d': opt-in probe only; IA-timeout fix; sock_dead
                                   --   latch; removed all time/kill auto-end.
                                   -- '2026-09-09e': DEBUG-LOG CAPTURE cleared it up.
                                   --   * Level:Complete NEVER fires here (0 in a 50k-line log).
                                   --   * The EOR-quiet fallback was WRONG for Supremacy — it fired
                                   --     ~7 min early during the capital-ship / "BXL Ground Phase
                                   --     Restart" lull, reported a bogus winner_team:0, and cleared
                                   --     `managing` so the REAL end signal was ignored. REMOVED.
                                   --     Only a 60-min runaway cap remains.
                                   --   * The reliable end signal IS the rotation-advance Level:Loaded
                                   --     ("Game ended, moving to next level") — fires at the true end
                                   --     of every match, Supremacy included, AFTER the ship phase.
                                   --   * New: bind the engine's `OnlineNetworkEndOfRoundStateMessage`
                                   --     / `NetworkMetricsLevelCompleteMessage` / `WSUINetworkScore-
                                   --     EventMessage` as events (they fire once at the real end in
                                   --     the debug log) — if EventManager surfaces them, that's an
                                   --     even cleaner trigger + maybe the winner. Logs only unless
                                   --     one fires. The winner itself (In_VictoryDeclarationTeam<N>
                                   --     Won / Outro_Team<N>) is still only in [PrintDebugText].
local GC_RESULT_PORT = 45702
local RESULT_VERSION = 1
-- `2026-09-16`: this used to be `clamp_bots`'s own FLOOR too, silently raising every real
-- bot count GC sent up to 20 — harmless while every GC mode floor genuinely was ~20, but
-- a live Blast garrison defence (mode floor 14, KyberBridge.MODE_BOTS) still hosted a full
-- 20v20, and the same bug would hit Extraction (floor 8) or CO-OP (floor 10) too. GC's own
-- per-mode floors are the real minimums now, so this only needs to be the STARTUP default
-- before any `load` ever sets a real target, and clamp_bots's fallback for a genuinely
-- unparseable value — never a floor applied on top of a real number GC sent.
local MIN_BOTS = 20
-- AutoPlayers.AimNoiseScaleTeam1 / Team2; LOWER = deadlier. GC sends a per-team value on
-- `load`; these are only the fallback when it sends none. No unit-buying system any more.
local DEFAULT_AIM_T1 = 2.5
local DEFAULT_AIM_T2 = 2.0
local BOT_TOPUP_INTERVAL = 10.0     -- seconds; re-fills bots (covers the phase-2 reset)
local DEFAULT_BP_GRANT = 500        -- per-bot Battle-Point floor when GC sends none (bare minimum)
local START_DELAY = 12.0            -- seconds after a level loads before we force the round on
local REPORT_DELAY = 2.5            -- seconds after Level:Complete before emitting (score settle)
-- `2026-09-16b`: Blast is a straight kill race to 100 (vanilla TDM, confirmed no ticket/
-- score field and no Outro_Team/Level:Complete signal — see pick_winner's own header). Every
-- round-end signal this file has (Level:Complete, the rotation-advance Level:Loaded, even
-- the generalised same-level-reload check added 2026-09-16a) is still just waiting to be
-- TOLD the round is over — and a live capture showed that telling never reliably arrives for
-- Blast at all. There's no need to wait: once a team hits 100 kills THAT is the round being
-- over, unconditionally, for this one mode — nothing else about the match state matters.
local BLAST_KILL_TARGET = 100
-- Absolute last-ditch cap: if a managed match has run this long with NO round-end signal
-- at all (no rotation-advance Level:Loaded, no Level:Complete), emit an undetermined result
-- so GC isn't stuck. Long enough that no real match — capital-ship phase and all — reaches
-- it; a real end always arrives first.
local RUNAWAY_CAP_S = 3600.0
-- '2026-09-11b' REVERTED the separate, shorter COOP_RUNAWAY_CAP_S (240s) added in
-- '2026-09-11a' — two same-day live captures (07:36-07:50 and 09:52-10:03, both
-- Kamino_03/ModeDefend) both eventually produced a genuine "Game ended, moving to next
-- level" and a real Level:Loaded round-boundary on their own, taking ~11-14 minutes, NOT a
-- same-level retry loop (that theory was already disproven for the first capture; the
-- second now disproves the "co-op needs its own short cap" theory too — the 240s cap fired
-- at the 4-minute mark on the second match and pre-empted its own real signal 6+ minutes
-- before the match actually ended, which is worse than the generic cap: the player would
-- see "no automatic winner" while still mid-mission, and the real end went unreported
-- because `match_armed` was already false by the time it arrived). Co-op just takes as long
-- as it takes, same as every other mode — the one-hour cap below covers it fine, so use it
-- uniformly. The same-level-reload clause (`coop_retried`) is removed too — same reasoning.
-- After a `load`, how long to wait for the real Level:Loaded before telling GC it didn't
-- switch. In a hosted match the real switch is bundle-streaming: 2026-09-09 capture showed
-- ~6 s online (LoadLevel echoes instantly, the real load lands seconds later). GC's own
-- deadline is 16 s, so wait ~15 s here — long enough that a real online load always beats
-- it, and in genuine Instant Action (no server, switch never comes) GC times out anyway.
local LOAD_TIMEOUT_S = 15.0
local SYNTH_FAIL_S = 15.0          -- same: don't give up early just because we saw the echo
local REAL_LOAD_MIN_S = 2.0        -- a Level:Loaded for our target sooner than this after the
                                   -- `load` is KYBER's console-command echo, not the real
                                   -- bundle-streaming switch
local ADOPT_MIN_S = 5.0            -- after the echo, if this long has passed AND players are on
                                   -- teams in a running match, adopt the load as real. Small/
                                   -- fast maps (Blast, some GA) fire only the one echo-timed
                                   -- Level:Loaded — there's no second event to wait for.
local ECHO_MATCH_MIN_S = 60.0      -- if `load`'s Level:Loaded was misjudged as an echo,
                                   -- `level_name` stays "" — but this many seconds of managed
                                   -- ticks means a real match nonetheless ran under us, so a
                                   -- later unrequested Level:Loaded is its round-end

-- Console commands that push a match to start without a full lobby. Best-effort: an
-- unknown name is a harmless no-op. Run BEFORE LoadLevel so cvars apply as the level builds.
local START_CMDS = {
	"Whiteshark.LobbyThreshold 1",
	"Whiteshark.SkipLobby 1",
	"Whiteshark.DisableStartupFlow 1",
	"Kyber.startgame",
	"startgame",
}

-- CO-OP ship levels (COOP_NT_*) are different: their own startup flow builds the mission
-- HUD/localization. Live 2026-10-30, starting them manually from KYBER produced normal text;
-- GC's full START_CMDS produced Aurebesh HUD text and the wrong side. So for co-op we do NOT
-- set SkipLobby/DisableStartupFlow, and we do NOT force startgame before the level loads.
-- Before the load we only raise the lobby threshold; the delayed force-start (once the level
-- has had START_DELAY seconds to build) is the fallback.
local START_CMDS_COOP = {
	"Whiteshark.LobbyThreshold 1",
}
local START_CMDS_COOP_FULL = {
	"Whiteshark.LobbyThreshold 1",
	"Kyber.startgame",
	"startgame",
}

local managed_mode = ""   -- mode GC's last `load` asked for (Mode9/ModeDefend = co-op)
local function is_coop_mode()
	return managed_mode == "Mode9" or managed_mode == "ModeDefend"
end

-- Whiteshark.StopEOR: true suppresses KYBER's end-of-round flow, which otherwise advances
-- the (empty) map rotation -> LoadLevel("","") -> client thrash -> listen-server crash.
-- 2026-09-08b tested it OFF: `Level:Complete` STILL never fires (the natural EOR bundles
-- load but no Lua event), and KYBER got less stable. So it's back ON by default. The
-- round-end signal has to come from somewhere else — see the Bundle event sweep + the
-- LookupDataContainer probes. `stopeor 0|1` still toggles it live. docs/SUPREMACY_PHASE.md.
-- 2026-11-03: StopEOR is per MODE and per CAMPAIGN, not global. Clone Wars / Sequel Era
-- Supremacy (Mode1) is the only match with the capital-ship phase, and its natural
-- end-of-round is the crash path (docs/SUPREMACY_PHASE.md), so it keeps StopEOR ON -
-- the v33 playtest showed that is stable and
-- restores the victory/defeat screen. `stopeor 0|1` overrides the mode default for the
-- next load (GC sends it per battle); `stopeor auto` returns to the mode default.
local stop_eor_override = nil

local function eor_suppressed()
	if stop_eor_override ~= nil then
		return stop_eor_override
	end
	return managed_mode == "Mode1"
end

local function apply_stop_eor()
	local on = eor_suppressed()
	Console.Execute("Whiteshark.StopEOR " .. (on and "true" or "false"))
	print("gc_result: Whiteshark.StopEOR " .. (on and "true (capital-ship Supremacy)" or "false (natural EOR - " .. (managed_mode ~= "" and managed_mode or "pre-load") .. ")"))
end

local function run_start_cmds(pre_load)
	if pre_load == nil then pre_load = false end
	local cmds = START_CMDS
	if is_coop_mode() then
		cmds = pre_load and START_CMDS_COOP or START_CMDS_COOP_FULL
	end
	for _, c in ipairs(cmds) do
		Console.Execute(c)
	end
	apply_stop_eor()
end

-- --- tiny JSON writer: flat, strings + numbers only ---------------------------
local function jstr(s)
	s = tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
	return '"' .. s .. '"'
end

local function team_obj(t)
	-- persist_* (2026-09-11b probe) fell out of every capture since this hand-written
	-- serializer never grew the fields alongside emit_result()'s `rep` table — they were
	-- computed, then silently dropped on the way to JSON. Fixed.
	return string.format(
		'{"score":%d,"kills":%d,"deaths":%d,"players":%d,'
		.. '"persist_score":%d,"persist_kills":%d,"persist_deaths":%d,"persist_assists":%d}',
		t.score, t.kills, t.deaths, t.players,
		t.persist_score, t.persist_kills, t.persist_deaths, t.persist_assists)
end

local function result_line(r)
	return table.concat({
		'{"type":"gc_result","v":', tostring(RESULT_VERSION),
		',"seq":', tostring(r.seq),
		',"map":', jstr(r.map),
		',"mode":', jstr(r.mode),
		',"teams":{"1":', team_obj(r.teams[1]), ',"2":', team_obj(r.teams[2]), '}',
		',"winner_team":', tostring(r.winner_team),
		',"reason":', jstr(r.reason),
		'}\n',
	})
end

-- --- bail cleanly if we're a duplicate instance (socket already bound) --------
local created_ok, created = pcall(function() return SocketManager.Create(GC_RESULT_PORT) end)
if not created_ok then
	print("gc_result: SocketManager.Create failed (" .. tostring(created)
		.. ") — another instance already owns the port; this one will not run.")
	return
end

local sock = created
print(string.format("gc_result: listening on 127.0.0.1:%d (build %s)", GC_RESULT_PORT, PLUGIN_BUILD))

-- --- DIAG: live service singletons, dumped once at load -------------------------------
-- 2026-09-06: an earlier pass here guessed at team/gamemode globals (TeamManager, Conquest,
-- TicketManager, ...) and speculative round-outcome event names one by one — almost all
-- guesses came back empty, and reverted 2026-09-06 (see docs/SUPREMACY_PHASE.md) along with
-- a full _G dump that found them: of _G's ~7800 non-stdlib names, nearly all are Frostbite's
-- EBX type registry (asset schema constructors, e.g. "AIArchetype" — not commands or
-- services) and exactly 8 are real live singletons — Console, EntityManager, EventManager,
-- PlayerManager, ResourceManager, SocketManager, Utils, and our own 'plugin'. Both probes
-- and the full _G dump are gone now that they've served their purpose (a live capture with
-- them running showed a "Join token not found" kick-and-reconnect loop repeating for
-- minutes instead of the few seconds seen without them — plausibly the extra load-time Lua
-- work widening the self-join race further; see the crash discussion). This block just
-- dumps the 8 known services' own keys, functions included (a service's useful surface IS
-- its methods — PlayerManager almost certainly has something like GetPlayers/score per
-- player; Console likely has more than the one Execute/GetSettings pair used so far).
-- The `_G` dump ran its course: 8 live services (Console, EntityManager, EventManager,
-- PlayerManager, ResourceManager, SocketManager, Utils, plugin) — everything else is the
-- Frostbite EBX type registry. No gamemode / ticket / conquest global exists.

-- --- state -------------------------------------------------------------------
local clients = {}          -- { {peer = <socket>, buf = ""} , ... }
local level_name = ""
local mode_name = ""
local expected_level = nil   -- the level GC's last `load` asked for
local pending_load = nil      -- { level, mode, accum, synthetic } while a `load` waits for
                              -- its Level:Loaded; cleared on a real switch or a timeout
local real_level = ""         -- last level we judged a REAL load (not a LoadLevel echo) —
local real_mode = ""          -- what the player is actually in. `already_there` keys on this.
local match_armed = false    -- a result is owed for the current match
local managing = false       -- GC asked for this match: run start cmds, fill bots, auto-end.
                             -- Cleared once the result is emitted so we never touch
                             -- KYBER's own rotation levels (that thrashed the client -> crash).
local result_seq = 0
local override_winner = nil  -- set by `end <team>` for test purposes
local target_bots_t1 = MIN_BOTS
local target_bots_t2 = MIN_BOTS
local team_label_1 = "team 1"   -- set by `label 1 <text>` from GC: which faction / force this is
local team_label_2 = "team 2"
local bp_grant_t1 = DEFAULT_BP_GRANT   -- carried in `load` for compat; BP is not a lever
local bp_grant_t2 = DEFAULT_BP_GRANT
local human_team = 0                    -- team the human player(s) belong on (0 = don't touch)
-- Per-player team pins, keyed by player.playerId (the EA account id — the same number the
-- log's own "[Server] <name> (<id>) successfully authenticated" line shows, confirmed
-- against that exact field by the vendored GunGame plugin's admins.lua, which already
-- checks player.playerId against a hardcoded EA id list live). Set via `teamid <id> <team>`,
-- one call per known human — this is what makes an ONLINE two-player match (a real human on
-- BOTH teams) put each of them on their own correct side automatically: `human_team` above
-- is a single shared value and can only ever express "the one human," which single player
-- and local hotseat both fit (there's only one physical player at a time either way) but two
-- separate remote humans do not. Checked FIRST wherever a player's team is (re)asserted; a
-- player whose id isn't in this table falls through to the plain `human_team` behavior
-- unchanged, so single player / local hotseat need no changes here at all.
local human_teams = {}                  -- playerId (number) -> team (1|2)
local coop_defender = 0                 -- co-op defending team from GC's `coopdef` (team setup / log only since 2026-09-10a — not the winner)
local aim_t1 = DEFAULT_AIM_T1
local hero_prob = nil                -- nil = leave the server's own value alone (GC sends `heroprob` per battle)
local aim_t2 = DEFAULT_AIM_T2
local topup_accum = 0.0
local start_accum = 0.0
local managed_elapsed = 0.0        -- seconds since this managed match loaded (runaway cap only)
local pending_start = false

-- Live kill tally from ServerPlayer:Killed — informational only (the winner comes from
-- pick_winner; kills are never used to decide it).
local kill_tally = { [1] = 0, [2] = 0 }
local spawn_logs = 0          -- per-level cap on the per-spawn log lines
local report_pending = false  -- Level:Complete fired; snapshot a few more times then emit
local report_accum = 0.0
local ground_end_sent = false -- `groundwin` fired Kyber.endgameteam this match already (once only)

-- `2026-09-18`: a live Clone Wars Supremacy crash right after `groundwin` — the user's own
-- recollection matches the EXACT crash class already documented above StopEOR: KYBER's
-- natural end-of-round flow advancing an (empty/undefined) map rotation -> LoadLevel("","")
-- -> listen-server crash. `Whiteshark.StopEOR true` (run_start_cmds, line ~316) suppresses
-- that ONLY for the vanilla round-end flow it hooks; `Kyber.endgameteam<N>` is a DICE
-- ConsoleCommandTrigger with its own internal victory/outro sequence, plausibly reaching a
-- rotation-advance StopEOR was never wired to intercept. Fix mirrors the ALREADY-PROVEN-SAFE
-- pattern the `end` verb already uses for "deliberately end this match right now" — a single
-- native `Console.Execute("Restart")` (not `Kyber.Restart`, which double-advanced -> crash) —
-- fired a few seconds AFTER `endgameteam<N>` rather than immediately alongside it, so the
-- victory/outro sequence (and its `Outro_Team<N>` bundle load, which is what GC's
-- KyberMatchWatch actually reads the winner from) has time to play and be observed before
-- anything forces the level to change again. GROUND_RESTART_DELAY_S is an estimate — the
-- BF+ outro for other modes has been captured taking anywhere from a few seconds to ~15-25s
-- (docs/DEVLOG.md, the EOR-bundle capture) — not yet confirmed against a real
-- groundwin-triggered crash; needs a live retest to say whether 10s is enough headroom.
local GROUND_RESTART_DELAY_S = 10.0
local ground_restart_pending = false
local ground_restart_accum = 0.0

local last_snapshot = nil    -- { [1]={score,kills,deaths,players}, [2]={...} }
local bots_t1, bots_t2 = 0, 0
local last_line = nil

local function empty_team()
	return { score = 0, deaths = 0, players = 0,
		-- 2026-09-11c probe fields (see snapshot() below) — NOT wired into pick_winner.
		-- .score / .deaths above stay hardcoded 0 on purpose (verified dead many times over;
		-- pick_winner must keep treating them as absent). These read the same
		-- PersistenceServerPlayerExtent struct's other two fields (KYBER source,
		-- Script/LuaPlayerManager.cpp) — our own kill_tally is built independently, from the
		-- ServerPlayer:Killed EVENT, not this. CONFIRMED DEAD too (live capture, same day):
		-- a full match showed real kill_tally numbers (161/174) alongside persist_kills /
		-- persist_score / persist_deaths / persist_assists all sitting at 0 the entire time,
		-- for both teams — not a partial gap, the whole extent never populates on a
		-- listen-server host (matches PersistenceManager.cpp's LoadPlayerPersistenceHk,
		-- which skips its stats load unless g_program->m_isDedicatedServer). Left in place as
		-- a record, not removed — but there is nothing left to learn from these four fields.
		persist_score = 0, persist_kills = 0, persist_deaths = 0, persist_assists = 0 }
end

-- ServerPlayer exposes no readable score/deaths field — verified across many captures
-- (every candidate name errors; the persistence score reads 0/0). snapshot() is now just
-- team + bot counts; the winner comes from pick_winner (outro bundle / coop defender).
local function snapshot()
	local players = PlayerManager.GetPlayers()
	if players == nil then return end
	local snap = { [1] = empty_team(), [2] = empty_team() }
	local b1, b2 = 0, 0
	for _, p in ipairs(players) do
		local team = p.team
		if team == 1 or team == 2 then
			snap[team].players = snap[team].players + 1
			if p.isBot then
				if team == 1 then b1 = b1 + 1 else b2 = b2 + 1 end
			end
			-- Probe-read, per player, pcall-wrapped so one bad player can't lose the whole
			-- snapshot (same caution as every other reflection attempt in this file).
			pcall(function()
				local t = snap[team]
				t.persist_score = t.persist_score + (tonumber(p.score) or 0)
				t.persist_kills = t.persist_kills + (tonumber(p.kills) or 0)
				t.persist_deaths = t.persist_deaths + (tonumber(p.deaths) or 0)
				t.persist_assists = t.persist_assists + (tonumber(p.assists) or 0)
			end)
		end
	end
	last_snapshot = snap
	bots_t1, bots_t2 = b1, b2
end

-- Winner: the game's own end-of-round score, and ONLY that. Kills are never the winner --
-- a Supremacy round won on objectives was being mis-reported as the other side "by kills".
-- Corrected 2026-09-05: Supremacy has no accumulating score at all — it resolves by
-- objectives (ground command posts, then boarding and destroying the enemy capital ship),
-- confirmed by the user. So `score` reading 0/0 on every real capture isn't a broken field,
-- it's the right answer to the wrong question — there was never going to be a numeric score
-- for this mode. Kills stay excluded for the same reason as before (a round won on
-- objectives was mis-reported by kills), and are additionally just the wrong shape of
-- signal here. The real fix is detecting the objective outcome directly — a team ticket
-- count (Battlefront+ changes Supremacy to tickets counting down to zero, replacing the
-- vanilla percentage — user-confirmed) or a round-outcome event — neither turned up in the
-- 2026-09-06 discovery pass (docs/SUPREMACY_PHASE.md). Until one does, this returns
-- "no score" every time for Supremacy/GA, and GC prompts the manual buttons instead of
-- guessing from a signal that doesn't apply.
-- CO-OP posts no team score AND the plugin can't read whether the boarders cleared the
-- ship (no Lua signal — same dead end as Supremacy/GA). A `coopdef`-based guess was wrong
-- about half the time, so co-op now returns "no score" too and GC prompts the manual
-- buttons. `coopdef` is still used for team setup / bot fill, just not the winner.
local function pick_winner(persist1, persist2)
	if persist1 ~= persist2 and (persist1 > 0 or persist2 > 0) then
		if persist1 > persist2 then return 1, "score" else return 2, "score" end
	end
	return 0, "no score"
end

-- --- clients ----------------------------------------------------------------
-- KYBER destroys SocketManager (our listen socket included) when a match tears down and
-- reloads the plugin for the next one. Once any socket op fails, latch here and go quiet —
-- the old instance is on its way out, and hammering a dead handle spams "Invalid socket
-- handle" into the module log.
local sock_dead = false

local function send_to(client, line)
	if sock_dead then return false end
	local ok = pcall(function() client.peer:Send(line) end)
	return ok
end

local function broadcast(line)
	if sock_dead then return end
	for i = #clients, 1, -1 do
		if not send_to(clients[i], line) then
			table.remove(clients, i)
		end
	end
end

local function accept_pending()
	if sock_dead then return end
	while true do
		local ok, peer = pcall(function() return sock:Accept() end)
		if not ok then sock_dead = true; return end
		if peer == nil then break end
		local client = { peer = peer, buf = "" }
		clients[#clients + 1] = client
		send_to(client, '{"type":"hello","build":' .. jstr(PLUGIN_BUILD) .. '}\n')
		-- A GC that reconnected after a KYBER restart may have missed the last result.
		if last_line ~= nil and not match_armed then
			send_to(client, last_line)
		end
		print("gc_result: GC connected")
	end
end

-- --- bots / difficulty ----------------------------------------------------
local function apply_bots()
	Console.Execute("AutoPlayers.ForceFillGameplayBotsTeam1 " .. tostring(target_bots_t1))
	Console.Execute("AutoPlayers.ForceFillGameplayBotsTeam2 " .. tostring(target_bots_t2))
	-- `2026-10-30`: CO-OP's own late autofill was ignoring the per-team targets and
	-- ballooning the AI-only side to a full 24-bot team ~30 s into the round (live log:
	-- target 7, actual 24, then slowly decaying). ForceFill only *adds*; turning server
	-- autofill off and allowing removal of autofill players stops the mode from adding
	-- beyond what GC asked for. Real humans can still join; these only govern auto-added
	-- bot slots. ForceApplyGameplayBotsCount makes the per-team caps authoritative in
	-- modes (like CO-OP) that otherwise fill to their own default.
	Console.Execute("AutoPlayers.ForceApplyGameplayBotsCount true")
	Console.Execute("AutoPlayers.AllowAddAutoFillPlayers false")
	Console.Execute("AutoPlayers.AllowRemoveAutoFillPlayers true")
	print(string.format("gc_result: bots apply — T1 target=%d (%s) | T2 target=%d (%s)",
		target_bots_t1, team_label_1, target_bots_t2, team_label_2))
end

-- Count the bots actually on each team right now and log target vs actual, with the
-- GC-supplied label for each team. This is the line that proves whether the counts
-- landed on the right side.
local function bots_sample_log(tag)
	local players = PlayerManager.GetPlayers()
	if players == nil then return end
	local b1, b2, h1, h2 = 0, 0, 0, 0
	for _, p in ipairs(players) do
		if p.team == 1 then
			if p.isBot then b1 = b1 + 1 else h1 = h1 + 1 end
		elseif p.team == 2 then
			if p.isBot then b2 = b2 + 1 else h2 = h2 + 1 end
		end
	end
	print(string.format("gc_result: bots %s — T1 %s: %d bots +%d human (target %d) | T2 %s: %d bots +%d human (target %d)",
		tag, team_label_1, b1, h1, target_bots_t1, team_label_2, b2, h2, target_bots_t2))
end

-- Per-team bot aim. LOWER AimNoiseScale = deadlier. GC sends aim_t1 / aim_t2 already
-- mapped to the right team (it knows which faction is Team 1 for the level).
-- Corrected 2026-09-05: the non-team AutoPlayers.AimNoiseScale / WeaponAimNoiseScale cvars
-- this used to also set (as a "fallback for builds that ignore the per-team ones") apply to
-- EVERY bot regardless of team and were being set AFTER the per-team cvars in the same
-- console echo — live capture confirmed both the per-team AND the non-team cvars land (all
-- three "> ..." lines echo a value), so the non-team ones were silently overwriting Team1/
-- Team2's aim to a flat average on every match. That made Combat Training's per-side aim a
-- no-op. Removed; per-team cvars alone are what's verified to work.
local function apply_difficulty()
	Console.Execute("AutoPlayers.AimNoiseScaleTeam1 " .. tostring(aim_t1))
	Console.Execute("AutoPlayers.AimNoiseScaleTeam2 " .. tostring(aim_t2))
	print(string.format("gc_result: aim apply — T1 %.2f | T2 %.2f (lower = deadlier)", aim_t1, aim_t2))
	if hero_prob ~= nil then
		Console.Execute("AutoPlayers.HeroSpawnProbability_Gameplay " .. string.format("%.2f", hero_prob))
		print(string.format("gc_result: hero spawn probability -> %.2f", hero_prob))
	end
end

-- (Removed the speculative Supremacy-shorten cvars — they did nothing and a bad cvar name
-- fired at level-build time is a plausible crash. If Supremacy length ever needs changing,
-- verify the real cvar first.)

-- BP is dead in this build (SetBattlepoints is a no-op — verified), so all BP read/write/
-- sample code is gone. `apply_bp_cap` is the one harmless leftover: a cvar that only helps
-- if BP ever comes back.
local function apply_bp_cap()
	Console.Execute("Whiteshark.MaximumBattlepoints 30000")
end

-- Dump a Frostbite settings object's fields (`settings <name>` command). Only AutoPlayers
-- and Whiteshark resolve in this build, and both are non-iterable DataContainers.
local function settings_dump(name)
	local ok, s = pcall(function() return Console.GetSettings(name) end)
	if not ok or s == nil then
		print("gc_result: settings " .. tostring(name) .. " — not found")
		return
	end
	local fields = {}
	local mok = pcall(function()
		for k, v in pairs(s) do
			if type(v) ~= "function" and type(v) ~= "userdata" and type(v) ~= "table" then
				fields[#fields + 1] = string.format("%s=%s", tostring(k), tostring(v))
			end
		end
	end)
	print(string.format("gc_result: settings %s | %s", name,
		(#fields > 0) and table.concat(fields, " ") or (mok and "(no scalar fields)" or "(not iterable)")))
end
local SETTINGS_HUNT = { "AutoPlayers", "Whiteshark" }

-- Keep human players on the team GC assigned (their own faction). CO-OP missions have a
-- fixed "which side the players are on" and can reassign the human a beat after spawn —
-- so we re-assert every tick, and log a persistent fight so a wrong `team_one_faction`
-- guess in data/maps.json is obvious from the module log.
--
-- Checks the per-id `human_teams` table FIRST (online two-player: each real human pinned to
-- their own side by EA id), then falls back to the single shared `human_team` (single
-- player / local hotseat: there's only one physical player regardless of which side is
-- active, so one value is enough). Returns 0 ("don't touch") if neither applies to this
-- specific player.
local function wanted_team_for(p)
	local by_id = human_teams[p.playerId]
	if by_id == 1 or by_id == 2 then return by_id end
	if human_team == 1 or human_team == 2 then return human_team end
	return 0
end
local function any_team_pin_active()
	if human_team == 1 or human_team == 2 then return true end
	for _ in pairs(human_teams) do return true end
	return false
end
local human_team_warns = 0
local human_team_accum = 0.0
local HUMAN_TEAM_INTERVAL = 5.0   -- seconds; NEVER hammer SetTeam — that hangs a joining client
local function enforce_human_team(step)
	if not any_team_pin_active() then return end
	human_team_accum = human_team_accum + (step or 0.033)
	if human_team_accum < HUMAN_TEAM_INTERVAL then return end
	human_team_accum = 0.0
	local players = PlayerManager.GetPlayers()
	if players == nil then return end
	for _, p in ipairs(players) do
		pcall(function()
			local want = wanted_team_for(p)
			if not p.isBot and want ~= 0 and (p.team == 1 or p.team == 2) and p.team ~= want then
				local from = p.team
				local ok = pcall(function() p:SetTeam(want) end)
				if human_team_warns < 6 then
					human_team_warns = human_team_warns + 1
					print(string.format("gc_result: HUMAN re-team %d -> %d (id %s) %s (if this keeps repeating, %s is the wrong team_one_faction for this level/mode)",
						from, want, tostring(p.playerId), ok and "" or "(SetTeam FAILED)",
						(want == 1) and team_label_1 or team_label_2))
				end
			end
		end)
	end
end

-- ===========================================================================
-- CAPTURE PROBE — the `probe` command only. Everything tried: docs/SUPREMACY_PHASE.md.
-- Still open: ResourceManager.LookupDataContainer(<EBX path>) resolves real asset paths
-- (pf_kitlimitations_mode1 confirmed) — the gamemode / ticket blueprint might be reachable
-- with the right path. EntityManager:GetList(realm) returns nil (dead). KYBER loads
-- `<level>/Outro_Team<N>` at round end but there's no Lua event for it.
-- ===========================================================================

-- Dump a KYBER bound object's surface: pairs() members, metatable keys (incl. the __name
-- type), and __index if it's a table. Used only by the opt-in probe.
local function dump_surface(o, label)
	if o == nil then return end
	print(string.format("gc_result: probe %s | value=%s type=%s", label, tostring(o), type(o)))
	pcall(function()
		local mt = getmetatable(o)
		if mt == nil then return end
		local mk = {}
		for k, v in pairs(mt) do
			mk[#mk + 1] = (k == "__name") and ("__name=" .. tostring(v)) or (tostring(k) .. "(" .. type(v) .. ")")
		end
		table.sort(mk)
		print(string.format("gc_result: probe %s | metatable: %s", label, table.concat(mk, " ")))
		if type(mt.__index) == "table" then
			local im = {}
			for k in pairs(mt.__index) do im[#im + 1] = tostring(k) end
			table.sort(im)
			print(string.format("gc_result: probe %s | __index: %s", label, table.concat(im, " ")))
		end
	end)
end

-- Real asset paths to try via ResourceManager.LookupDataContainer (which DOES resolve them
-- — pf_kitlimitations_mode1 confirmed). Looking for the gamemode/ticket blueprint + the
-- kit-limitation assets (the potential runtime hero/unit lever).
-- 2026-09-11 (Log -> Probe kit limits, live capture): DEAD END for blind reflection —
-- pf_kitlimitations_mode1 resolves, but its metatable's __index/__newindex are FUNCTIONS,
-- not tables, so dump_surface() (which only enumerates a table __index) finds nothing to
-- list, and none of HERO_FIELD_NAMES below hit either. This DataContainer is backed by a C
-- accessor — matches the official Kyber docs' own warning that a DataContainer's fields are
-- "dynamic... you must know what the names of them are" rather than being a tooling gap.
-- The only way past this is finding the real field names externally (FrostyToolsuite against
-- the actual game's EBX blueprints), not more guessing here.
local RESMGR_NAMES = {
	"gameplay/gamemodes/conquest/conquestgamemode",
	"gameplay/gamemodes/conquest/wsconquestgamemodesettings",
	"addons/mode1/gameplay/gamemodes/mode1",
	"gameplay/gamemodes/shared/wsgamemodesettings",
	"addons/mode1/gameplay/teams/pf_kitlimitations_mode1",
	"gameplay/gamemodes/shared/pf_kitlimitations_planetarybattles",
}
local HERO_FIELD_NAMES = {
	"Enabled", "MaxKitCount", "ApplyMaxKitCount", "TeamId", "Limitations", "MaxCount",
	"Heroes", "AllowHeroes", "HeroCount", "PLANETARY_BATTLES_HERO_COUNT_INITIAL",
	"PLANETARY_BATTLES_HERO_COUNT_LAST_PHASE",
}

-- Opt-in probe suite: the `probe` command, and once when a round end is detected. Not run
-- at load or mid-match — that only fills the log with known-dead output.
local outcome_probe_ran = false
local function outcome_probe(tag)
	if outcome_probe_ran then return end
	outcome_probe_ran = true
	pcall(function()
		-- EntityManager:GetList(realm) — colon; realm is an int (dot-call ate the arg).
		if EntityManager and EntityManager.GetList then
			for realm = 0, 3 do
				local ok, res = pcall(function() return EntityManager:GetList(realm) end)
				if ok and type(res) == "table" then
					local hist = {}
					for i = 1, math.min(#res, 1000) do
						local nm = "?"
						pcall(function()
							local m = getmetatable(res[i])
							nm = tostring((m and m.__name) or res[i].typeName or "?")
						end)
						hist[nm] = (hist[nm] or 0) + 1
					end
					local parts = {}
					for k, v in pairs(hist) do parts[#parts + 1] = k .. ":" .. v end
					table.sort(parts)
					print(string.format("gc_result: probe EntityManager:GetList(%d)@%s len=%d — %s",
						realm, tag, #res, table.concat(parts, " ")))
					if res[1] then dump_surface(res[1], "entity[1] realm" .. realm) end
				elseif not ok then
					print(string.format("gc_result: probe EntityManager:GetList(%d)@%s failed: %s", realm, tag, tostring(res)))
				end
			end
		end
		-- ResourceManager.LookupDataContainer(<asset path>)
		if ResourceManager and ResourceManager.LookupDataContainer then
			for _, nm in ipairs(RESMGR_NAMES) do
				local ok, c = pcall(function() return ResourceManager.LookupDataContainer(nm) end)
				if ok and c ~= nil then
					print(string.format("gc_result: probe LookupDataContainer(%q)@%s -> RESOLVED", nm, tag))
					dump_surface(c, "LDC " .. nm)
					local hits = {}
					for _, k in ipairs(HERO_FIELD_NAMES) do
						local rok, v = pcall(function() return c[k] end)
						if rok and v ~= nil then hits[#hits + 1] = k .. "=" .. tostring(v) end
					end
					if #hits > 0 then
						print(string.format("gc_result: probe LDC %q fields — %s", nm, table.concat(hits, "  ")))
					end
				end
			end
		end
	end)
end

-- (Removed the round-end / bundle-load event-name sweep — 16 candidate names, none ever
-- fired across every capture. KYBER loads `<level>/Outro_Team<N>` at round end and there
-- is apparently no Lua event for it. If bundle-event hunting resumes it's a deliberate
-- probe build, not always-on listeners.)

local function emit_result()
	pending_load = nil   -- the round is over; a `load` that never landed is moot now
	result_seq = result_seq + 1
	local snap = last_snapshot or { [1] = empty_team(), [2] = empty_team() }
	local p1, p2 = snap[1].score, snap[2].score
	local winner, reason = pick_winner(p1, p2)
	if override_winner ~= nil then
		winner, reason = override_winner, "forced"
		override_winner = nil
	end
	if winner == 0 and mode_name == "Blast" and kill_tally[1] ~= kill_tally[2] then
		-- Blast is a straight kill race to 100 — no objective / ticket score, but the team
		-- that got there (highest kills) is unambiguously the winner. Kills stay EXCLUDED for
		-- Supremacy / GA, where a round is won on objectives and kills are the wrong signal
		-- (mis-reported that way before — see pick_winner).
		winner = (kill_tally[1] > kill_tally[2]) and 1 or 2
		reason = string.format("blast kills %d-%d", kill_tally[1], kill_tally[2])
	end
	-- winner_team is the whole answer now. teams.N.score is the end-of-round persistence
	-- score; teams.N.kills is informational only (GC no longer decides anything from it).
	-- persist_* are the 2026-09-1x probe fields (snapshot() above) — a direct read of
	-- ServerPlayer.score/.kills/.deaths/.assists, never wired into pick_winner. Logged so a
	-- captured match can be compared: does persist_kills match kill_tally (the event-based
	-- count)? Does persist_score/persist_deaths ever leave 0 the way plain score/deaths never
	-- have? That comparison is the point — nothing here decides a winner.
	local rep = {
		[1] = { score = p1, kills = kill_tally[1], deaths = snap[1].deaths, players = snap[1].players,
			persist_score = snap[1].persist_score, persist_kills = snap[1].persist_kills,
			persist_deaths = snap[1].persist_deaths, persist_assists = snap[1].persist_assists },
		[2] = { score = p2, kills = kill_tally[2], deaths = snap[2].deaths, players = snap[2].players,
			persist_score = snap[2].persist_score, persist_kills = snap[2].persist_kills,
			persist_deaths = snap[2].persist_deaths, persist_assists = snap[2].persist_assists },
	}
	last_line = result_line({
		seq = result_seq, map = level_name, mode = mode_name,
		teams = rep, winner_team = winner, reason = reason,
	})
	broadcast(last_line)
	print("gc_result: " .. last_line)
	managing = false   -- match is decided; stop touching the server
end

-- Is a match actually running right now? `LoadLevel` only acts on a live server, and
-- PlayerManager.GetPlayers() returns nil / empty at the frontend menu. `level_name ~= ""`
-- means we've seen at least one Level:Loaded this session (host or Arcade / IA start).
local function match_is_live()
	if level_name ~= "" then return true end
	local ok, players = pcall(function() return PlayerManager.GetPlayers() end)
	return ok and players ~= nil and #players > 0
end

-- Has the local human actually spawned into the round yet? Used to decide whether the
-- delayed co-op force-start is still needed; a match already in progress must not be
-- poked with startgame again.
local function human_spawned()
	local ok, players = pcall(function() return PlayerManager.GetPlayers() end)
	if not ok or players == nil then return false end
	for _, p in ipairs(players) do
		if not p.isBot and p.isSpawned then return true end
	end
	return false
end

-- --- commands (GC -> plugin) -------------------------------------------
local function split_ws(s)
	local out = {}
	for w in s:gmatch("%S+") do out[#out + 1] = w end
	return out
end

-- A real numeric value is trusted as-is (clamped only to a sane floor of 1, never to
-- MIN_BOTS) — see MIN_BOTS's own comment for why forcing every count up to 20 was a bug.
-- MIN_BOTS only stands in for a value that failed to parse at all.
local function clamp_bots(v)
	local n = tonumber(v)
	if n == nil then return MIN_BOTS end
	return math.max(1, math.floor(n))
end

local function clamp_bp(v)
	return math.max(0, math.floor(tonumber(v) or DEFAULT_BP_GRANT))
end

local function handle_command(line)
	local verb, rest = line:match("^(%S+)%s*(.-)%s*$")
	if verb == nil then return end
	local a = split_ws(rest)

	if verb == "load" then
		local lvl, mode = a[1], a[2] or ""
		if lvl == nil then return end
		-- A `load` for a DIFFERENT battle while one is still armed means the previous match
		-- ended and GC moved on without ever getting a result (Level:Complete never fired).
		-- Emit it now so it isn't lost — GC drops it if that battle was already resolved.
		if match_armed and level_name ~= "" and lvl ~= level_name then
			print("gc_result: new load while a result was still owed for " .. level_name .. " — emitting it first")
			pcall(emit_result)
			match_armed = false
		end
		if a[3] and a[4] then
			target_bots_t1 = clamp_bots(a[3])
			target_bots_t2 = clamp_bots(a[4])
			if a[5] then aim_t1 = tonumber(a[5]) or aim_t1 end
			if a[6] then aim_t2 = tonumber(a[6]) or aim_t2 end
			-- a[7..10] (bp1 bp2 maxSec margin) are carried for wire compat; all dead levers.
		end
		-- 2026-09-20 (live Bespin Blast): a SECOND `load` for the level we're already managing
		-- (the player clicked Play in KYBER again because the first hadn't visibly filled yet)
		-- re-issued LoadLevel on a live match and the game crashed ~3 s later ("Redirecting crash to
		-- Sentry" right after the same-level reload). The bots had in fact loaded. So a repeat load
		-- of the same level while it's still armed + managed only re-applies bots/aim/labels below;
		-- it never reloads the level.
		local duplicate_load = managing and match_armed and level_name ~= "" and level_name == lvl
		expected_level = lvl
		managed_mode = mode
		match_armed = true
		managing = true
		ground_end_sent = false
		hero_prob = nil   -- per battle: GC re-sends `heroprob` right after this load
		ground_restart_pending = false
		ground_restart_accum = 0.0
		human_teams = {}   -- cleared per match — a stale id pin from a previous battle (a
		                   -- player who left, or a single-player game after an online one)
		                   -- must not silently carry over; GC re-sends fresh `teamid`s
		                   -- (or none, for single player / local hotseat) with every `load`
		local live = match_is_live()
		-- Already sitting on exactly this level+mode from a REAL load (host, or the player
		-- started their offline match on the same map): confirm straight away. A stale
		-- `level_name` left by a previous failed LoadLevel echo does NOT count — real_level
		-- is only set by a Level:Loaded we judged real (see the handler).
		local already_there = live and ((real_level == lvl and real_mode == mode) or duplicate_load)
		pending_load = already_there and nil or { level = lvl, mode = mode, accum = 0, synthetic = false }
		print(string.format("gc_result: load %s %s (bots %d/%d aim %.2f/%.2f) match_live=%s%s",
			lvl, mode, target_bots_t1, target_bots_t2, aim_t1, aim_t2,
			tostring(live), already_there and " (already on this level)" or ""))
		broadcast(string.format('{"type":"load_ack","running":%s,"level":%s,"mode":%s}\n',
			tostring(live), jstr(lvl), jstr(mode)))
		if not live then
			print("gc_result: LoadLevel has no running match to act on — the player must start "
				.. "an Arcade / Instant Action match first (offline), or Host (online).")
		end
		run_start_cmds(true)   -- co-op: threshold only before the level builds
		if duplicate_load and live then
			print("gc_result: duplicate load of " .. lvl .. " while it is already live — NOT reloading the level (that crashed the game)")
		else
			Console.Execute("LoadLevel " .. lvl .. " " .. mode)
		end
		if already_there then
			-- No fresh Level:Loaded coming, so run the managing setup here.
			apply_bp_cap()
			apply_bots()
			apply_difficulty()
			level_name, mode_name = lvl, mode
			broadcast('{"type":"level","map":' .. jstr(lvl) .. ',"mode":' .. jstr(mode) .. '}\n')
		end
	elseif verb == "autoend" then
		print("gc_result: autoend ignored — no time/kill cap in this build")
	elseif verb == "bots" then
		target_bots_t1 = clamp_bots(a[1])
		target_bots_t2 = clamp_bots(a[2] or a[1])
		apply_bots()
	elseif verb == "label" then
		local t = tonumber(a[1])
		local text = rest:match("^%s*%S+%s+(.-)%s*$") or ""
		if t == 1 then team_label_1 = text ~= "" and text or team_label_1
		elseif t == 2 then team_label_2 = text ~= "" and text or team_label_2 end
		print(string.format("gc_result: label — T1=%s T2=%s", team_label_1, team_label_2))
	elseif verb == "bp" then
		bp_grant_t1 = clamp_bp(a[1])
		bp_grant_t2 = clamp_bp(a[2] or a[1])
		print(string.format("gc_result: bp floor -> %d / %d", bp_grant_t1, bp_grant_t2))
	elseif verb == "bpmax" then
		print("gc_result: bpmax ignored — BP control does not work in this KYBER build")
	elseif verb == "humanteam" then
		human_team = math.floor(tonumber(a[1]) or 0)
		if human_team ~= 1 and human_team ~= 2 then human_team = 0 end
		human_team_accum = HUMAN_TEAM_INTERVAL  -- apply on the next tick, not in 5 s
		print(string.format("gc_result: human team -> %s", human_team == 0 and "unset" or tostring(human_team)))
	elseif verb == "teamid" then
		-- Pin ONE specific player (by EA id) to a team — call once per known human for an
		-- online match, instead of `humanteam`'s single shared value (see human_teams' own
		-- declaration comment for why one value can't cover two real, separately-teamed
		-- humans). `teamid <id> 0` un-pins that one id without touching any other.
		local id = tonumber(a[1])
		local team = math.floor(tonumber(a[2]) or 0)
		if id == nil then
			print("gc_result: teamid needs a numeric player id — ignored: " .. rest)
		elseif team == 1 or team == 2 then
			human_teams[id] = team
			human_team_accum = HUMAN_TEAM_INTERVAL  -- apply on the next tick, not in 5 s
			print(string.format("gc_result: team pin — id %d -> team %d", id, team))
		else
			human_teams[id] = nil
			print(string.format("gc_result: team pin cleared — id %d", id))
		end
	elseif verb == "herolock" or verb == "herohash" then
		-- The unit-buying system was removed — heroes are unrestricted (bots included).
		print("gc_result: " .. verb .. " ignored (no unit-buying system)")
	elseif verb == "coopdef" then
		coop_defender = math.floor(tonumber(a[1]) or 0)
		print("gc_result: coop defender team -> " .. tostring(coop_defender))
	elseif verb == "stopeor" then
		local v = tostring(a[1] or "")
		if v == "auto" or v == "" then
			stop_eor_override = nil
		else
			stop_eor_override = (v == "1" or v == "true")
		end
		apply_stop_eor()
		print("gc_result: StopEOR override -> " .. (stop_eor_override == nil and "auto (capital-ship Supremacy only)" or tostring(stop_eor_override)))
	elseif verb == "settings" then
		if a[1] then settings_dump(a[1]) else for _, n in ipairs(SETTINGS_HUNT) do settings_dump(n) end end
	elseif verb == "probe" then
		outcome_probe_ran = false   -- allow a fresh run
		outcome_probe("cmd")
	elseif verb == "start" then
		if is_coop_mode() and human_spawned() then
			print("gc_result: start — co-op match already spawned; not forcing")
		else
			run_start_cmds(false)
			print("gc_result: start (lobby cvars re-run)")
		end
		pending_start = false
	elseif verb == "diff" then
		aim_t1 = tonumber(a[1]) or aim_t1
		aim_t2 = tonumber(a[2]) or aim_t1
		apply_difficulty()
	elseif verb == "say" then
		if rest ~= "" then pcall(function() Console.Execute("Broadcast " .. rest) end) end
	elseif verb == "groundwin" then
		-- GC saw the capital-ship sub-level stream in — a team just won the ground phase of a
		-- Clone Wars Capital Supremacy match. End the round NOW for that team via the
		-- gamemode's own end trigger, skipping the (bot-broken) capital-ship phase.
		-- Kyber.endgameteam1 / Kyber.endgameteam2 are DICE ConsoleCommandTrigger blueprint
		-- entities (not Kyber commands); the user verified they cleanly end the match. Fire
		-- ONCE — re-firing a ConsoleCommandTrigger has crashed the game (SkipTitanPhase1).
		local n = math.floor(tonumber(a[1]) or 0)
		if (n == 1 or n == 2) and not ground_end_sent then
			ground_end_sent = true
			print("gc_result: groundwin -> Kyber.endgameteam" .. tostring(n) .. " (skipping the capital-ship phase)")
			pcall(function() Console.Execute("Kyber.endgameteam" .. tostring(n)) end)
			-- Arm the delayed Restart (see the comment above ground_restart_pending's
			-- declaration) — NOT fired here immediately, so the victory/outro sequence has
			-- time to play and its Outro_Team<N> bundle load has time to reach GC first.
			ground_restart_pending = true
			ground_restart_accum = 0.0
		elseif ground_end_sent then
			print("gc_result: groundwin ignored — already ended this match")
		else
			print("gc_result: groundwin needs team 1 or 2 (got " .. tostring(a[1]) .. ")")
		end
	elseif verb == "end" then
		local w = tonumber(a[1])
		if w == 1 or w == 2 then override_winner = w end
		print("gc_result: end match (winner " .. tostring(a[1] or "by tally") .. ")")
		if match_armed then
			emit_result()   -- sets managing = false
			match_armed = false
		end
		Console.Execute("Restart")   -- single round-end; no Kyber.Restart (that double-advanced -> crash)
	elseif verb == "heroprob" then
		local v = tonumber(a[1])
		if v ~= nil then
			hero_prob = math.max(0.0, math.min(1.0, v))
			apply_difficulty()
		end
	elseif verb == "restart" then
		-- 2026-09-19: playtest — a Supremacy match STILL crashed after it ended. KYBER's own natural
		-- end-of-round (Game ended -> LoadNextLevel of an empty rotation) is the crash (see
		-- docs/SUPREMACY_PHASE.md); once GC has the winner there is nothing left to wait for, so
		-- skip straight past it. Same single Restart the `end` verb uses, minus emitting a result.
		print("gc_result: restart — match over, skipping the natural end-of-round sequence")
		managing = false
		match_armed = false
		Console.Execute("Restart")
	elseif verb == "testeor" then
		-- Diagnostic only — does NOT touch match_armed/managing/emit_result, unlike "end".
		-- `endofround` is a real, native (non-Kyber) console command — found in a live
		-- ArmchairDevelopers/PluginExamples plugin (GunGame), which calls it to conclude its
		-- own custom win condition. Untested here: does it run the game's OWN natural
		-- end-of-round sequence (which might finally fire ServerLevelCompletedMessage /
		-- Level:Complete — unlike "Restart", which may just force a KYBER-side reload that
		-- bypasses it), and does it decide a winner on its own (by score, or arbitrarily)?
		-- Fire it and let the log answer both questions — do not assume the result.
		print("gc_result: testeor -> Console.Execute(\"endofround\") [diagnostic, no result emitted]")
		local ok, err = pcall(function() Console.Execute("endofround") end)
		if not ok then
			print("gc_result: testeor FAILED: " .. tostring(err))
		end
	elseif verb == "hero" then
		-- Diagnostic only — does NOT touch match state or emit a result. Player:
		-- SetCustomizationAsset is a real, officially documented (though marked
		-- EXPERIMENTAL) API — a live PluginExamples capture confirmed
		-- "Gameplay/Kits/Hero/DarthVader/Kit_Hero_DarthVader" actually works. Applies to the
		-- first human (non-bot) player found — there is normally only one during a GC
		-- battle. `a[1]` is the asset path; GC's UI sends it pre-filled with the confirmed
		-- Vader path but lets the user type any other "Gameplay/Kits/Hero/<Name>/
		-- Kit_Hero_<Name>" guess to test live, since nothing else confirms other hero names.
		local asset_path = tostring(a[1] or "")
		if asset_path == "" then
			print("gc_result: hero needs an asset path, e.g. hero Gameplay/Kits/Hero/DarthVader/Kit_Hero_DarthVader")
		else
			local players = PlayerManager.GetPlayers()
			local target = nil
			if players ~= nil then
				for _, p in ipairs(players) do
					if not p.isBot then
						target = p
						break
					end
				end
			end
			if target == nil then
				print("gc_result: hero " .. asset_path .. " — no human player found (not in a live match?)")
			else
				print("gc_result: hero -> " .. target.name .. " : SetCustomizationAsset(" .. asset_path .. ")")
				local ok, err = pcall(function() target:SetCustomizationAsset(asset_path) end)
				if not ok then
					print("gc_result: hero FAILED: " .. tostring(err))
				end
			end
		end
	elseif verb == "bpdump" then
		print("gc_result: bpdump ignored — BP is not readable/writable in this build")
	elseif verb == "ping" then
		broadcast('{"type":"pong"}\n')
	else
		print("gc_result: unknown command '" .. verb .. "'")
	end
end

local function pump_commands()
	if sock_dead then return end
	for i = #clients, 1, -1 do
		local client = clients[i]
		local ok, data = pcall(function() return client.peer:Recv(2048) end)
		if not ok then
			table.remove(clients, i)
		elseif data == "" then
			table.remove(clients, i)
			print("gc_result: GC disconnected")
		elseif type(data) == "string" and #data > 0 then
			client.buf = client.buf .. data
			while true do
				local nl = client.buf:find("\n", 1, true)
				if nl == nil then break end
				local one = client.buf:sub(1, nl - 1):gsub("\r$", "")
				client.buf = client.buf:sub(nl + 1)
				if #one > 0 then
					pcall(handle_command, one)
				end
			end
		end
	end
end

-- --- wiring ------------------------------------------------------------
EventManager.Listen("Level:Loaded", function(level, mode)
	level = level or ""
	mode = mode or ""

	-- KYBER's LoadLevel console command fires Level:Loaded synchronously, THEN attempts the
	-- load — which fails outside a KYBER-hosted match ("you aren't running a server", e.g.
	-- Instant Action). A real switch is seconds of bundle streaming; the echo lands almost
	-- immediately. A target-level event sooner than REAL_LOAD_MIN_S after our `load` is the
	-- echo: apply the cvars that DO still work in Instant Action (bots, aim) but don't tell
	-- GC the map changed, and let the timeout report it honestly.
	if pending_load ~= nil and level == pending_load.level and pending_load.accum < REAL_LOAD_MIN_S then
		pending_load.synthetic = true
		print(string.format(
			"gc_result: Level:Loaded %s in %.2fs — LoadLevel echo, not a real switch (Instant Action / no KYBER server?)",
			level, pending_load.accum))
		if managing then
			apply_bp_cap()
			apply_bots()
			apply_difficulty()
		end
		return
	end

	local requested = (level == expected_level)
	expected_level = nil

	-- A real load of our target (or any real load) — GC hears this as "level" below.
	real_level, real_mode = level, mode
	-- A fresh load can drop the human onto the mission's default (ship-crew) team. Run the
	-- team pin on the very next tick instead of waiting up to HUMAN_TEAM_INTERVAL, so the
	-- player doesn't spend the first seconds looking at the other faction's objectives.
	human_team_accum = HUMAN_TEAM_INTERVAL
	if pending_load ~= nil and level == pending_load.level then
		pending_load = nil
	end

	-- An unrequested Level:Loaded for a DIFFERENT map means KYBER auto-advanced past a
	-- finished round (co-op / GA / Supremacy play to their own end; this is where we report
	-- them). `level_name` can still be "" here when our `load`'s Level:Loaded landed inside
	-- REAL_LOAD_MIN_S and was judged a LoadLevel echo (a hosted server does this) — a long
	-- `managed_elapsed` proves a real match ran under us anyway. Emit, and crucially DON'T
	-- fall through to "managing" this rotation-advance level (that crashed the listen server).
	-- 2026-09-11a briefly added a same-level-reload clause here, theorising co-op has "no
	-- next map" and instead retries the same level on defeat. 2026-09-11b: two same-day live
	-- captures both disproved it for CO-OP specifically — it rotates to a different
	-- (unrelated) next map exactly like every other mode, just taking ~11-14 minutes instead
	-- of the seconds a quick Blast round takes. Removed at the time as unneeded complexity.
	-- 2026-09-16: reinstated, generalised to every mode, after a real Blast round (Jakku,
	-- Takodana) reported NEITHER at its own natural end NOR correctly once it finally did —
	-- the player's own KYBER map rotation looped back to the SAME Blast level, which the old
	-- `level ~= level_name` check can never treat as a round boundary at all (same string,
	-- forever). Unlike co-op's disproven theory, this isn't a guess about how one mode
	-- behaves — an UNREQUESTED Level:Loaded (this handler already knows `requested` is
	-- false), arriving long after this match started (`managed_elapsed >= ECHO_MATCH_MIN_S`,
	-- the same 60s echo-vs-real threshold already trusted for the `level_name == ""` case),
	-- can only be a genuine restart REGARDLESS of whether the level name happens to match —
	-- our own `load`'s own echo is already ruled out by REAL_LOAD_MIN_S above, long before
	-- managed_elapsed could ever reach 60s. This is also what fixes Blast's "eventually
	-- reported 0-0": the round's real kill_tally is read (and only then reset, below) at the
	-- moment this fires — previously, a same-level reload wiped kill_tally to 0/0 on every
	-- pass without this ever counting as the round ending, so by the time the hour-long
	-- runaway cap finally forced a report, whatever partial tally was mid-flight looked tied.
	local prior_round_ended =
		(level_name ~= "" and level ~= level_name)
		or (level_name == "" and managed_elapsed >= ECHO_MATCH_MIN_S)
		or (level_name ~= "" and level == level_name and managed_elapsed >= ECHO_MATCH_MIN_S)
	if match_armed and not requested and prior_round_ended then
		emit_result()   -- sets managing = false
		match_armed = false
	end

	level_name = level
	mode_name = mode
	last_snapshot = nil
	topup_accum = 0.0
	start_accum = 0.0
	managed_elapsed = 0.0
	outcome_probe_ran = false
	pending_start = managing
	kill_tally = { [1] = 0, [2] = 0 }
	report_pending = false
	report_accum = 0.0
	ground_end_sent = false
	ground_restart_pending = false
	ground_restart_accum = 0.0
	spawn_logs = 0
	human_team_warns = 0

	accept_pending()
	broadcast('{"type":"level","map":' .. jstr(level_name) .. ',"mode":' .. jstr(mode_name) .. '}\n')

	-- Only drive a level GC asked us to run. KYBER's own rotation levels are left alone
	-- (force-starting one mid-teardown crashed the listen server).
	if managing then
		print(string.format("gc_result: managing %s (%s) [build %s]", level_name, mode_name, PLUGIN_BUILD))
		print(string.format("gc_result: plan — T1 %s: %d bots aim %.2f | T2 %s: %d bots aim %.2f | human->T%s",
			team_label_1, target_bots_t1, aim_t1, team_label_2, target_bots_t2, aim_t2,
			human_team == 0 and "?" or tostring(human_team)))
		run_start_cmds(true)   -- co-op: do not force-start while the HUD/startup flow builds
		apply_bp_cap()   -- harmless if BP is dead; raises the ceiling if it ever isn't
		apply_bots()
		apply_difficulty()
	else
		print(string.format("gc_result: NOT managing %s — bot fill will not be applied", level_name))
	end
end)

EventManager.Listen("Server:UpdatePre", function(dt)
	accept_pending()
	pump_commands()
	snapshot()

	local step = tonumber(dt) or 0.033

	if ground_restart_pending then
		ground_restart_accum = ground_restart_accum + step
		if ground_restart_accum >= GROUND_RESTART_DELAY_S then
			ground_restart_pending = false
			print("gc_result: groundwin follow-up — Console.Execute(Restart) (giving the outro a defined next level instead of an empty rotation advance)")
			pcall(function() Console.Execute("Restart") end)
		end
	end

	-- A `load` is outstanding and its Level:Loaded never came — LoadLevel had no target
	-- (wrong mode for the running match, or the match ended under us). This loop only ticks
	-- while a match runs, so "dead at the menu" is GC's own deadline to catch, not this.
	if pending_load ~= nil then
		pending_load.accum = pending_load.accum + step
		-- A HUMAN on a team (not just leftover bots from a previous match) means the player
		-- actually loaded into our match.
		local human_in_match = last_snapshot ~= nil
			and ((last_snapshot[1].players + last_snapshot[2].players) - (bots_t1 + bots_t2)) > 0

		if pending_load.synthetic and pending_load.accum >= ADOPT_MIN_S and human_in_match then
			-- KYBER acknowledged our LoadLevel (the echo fired for exactly this level) and a
			-- match is now running with players on teams. On a small/fast map that one echo-
			-- timed Level:Loaded IS the switch — there's no second bundle-streaming event.
			-- Adopt it: tell GC the map's live and manage it like any other.
			level_name, mode_name = pending_load.level, pending_load.mode
			real_level, real_mode = pending_load.level, pending_load.mode
			topup_accum, start_accum, managed_elapsed = 0.0, 0.0, 0.0
			pending_start = false
			kill_tally = { [1] = 0, [2] = 0 }
			pending_load = nil
			print(string.format("gc_result: load %s — no second Level:Loaded, but a match is live; adopting it [build %s]",
				level_name, PLUGIN_BUILD))
			broadcast('{"type":"level","map":' .. jstr(level_name) .. ',"mode":' .. jstr(mode_name) .. '}\n')
			if managing then
				run_start_cmds(false)
				apply_bots()
				apply_difficulty()
			end
		elseif pending_load.accum >= (pending_load.synthetic and SYNTH_FAIL_S or LOAD_TIMEOUT_S) then
			-- We saw the LoadLevel echo but no switch followed and no match is running — SWBF2
			-- isn't actually hosting the target map (not hosting yet, or wrong map/mode).
			local reason = "SWBF2 didn't switch to the battle map. If you're hosting, click "
				.. "Play again; otherwise start the match on the target map/mode first. Bot "
				.. "counts and aim were still applied to the match you're in."
			print(string.format("gc_result: load %s gave up after %.0fs (no real switch, no match live)",
				pending_load.level, pending_load.accum))
			broadcast(string.format('{"type":"load_failed","level":%s,"code":%s,"reason":%s}\n',
				jstr(pending_load.level), jstr("no_switch"), jstr(reason)))
			pending_load = nil
		end
	end

	if not managing then return end
	enforce_human_team(step)   -- co-op can drag the human onto the mission's assault team (throttled)

	topup_accum = topup_accum + step
	if topup_accum >= BOT_TOPUP_INTERVAL then
		topup_accum = 0.0
		bots_sample_log("check")
		-- Re-assert on ANY difference, not just a shortfall. CO-OP's autofill can also
		-- add *too many* bots; with AllowAddAutoFillPlayers now off, re-applying the
		-- ForceFill targets is what pulls an overfilled enemy team back down.
		if bots_t1 ~= target_bots_t1 or bots_t2 ~= target_bots_t2 then
			apply_bots()
		end
		-- Re-assert per-team aim — the phase-2 reset can clear the cvars.
		apply_difficulty()
	end

	if pending_start then
		start_accum = start_accum + step
		if start_accum >= START_DELAY then
			pending_start = false
			if is_coop_mode() and human_spawned() then
				print("gc_result: co-op already spawned — not forcing start")
			else
				run_start_cmds(false)
				print("gc_result: forcing match start")
			end
		end
	end

	managed_elapsed = managed_elapsed + step

	-- The real round-end signal is KYBER's rotation-advance Level:Loaded ("Game ended,
	-- moving to next level") — verified firing at the true end of every match, incl.
	-- Supremacy AFTER the capital-ship phase (2026-09-09 debug capture). The old
	-- EOR-quiet-timer fallback is GONE: it misfired ~7 min early during the capital-ship /
	-- ground-restart lull, reported the wrong result, and cleared `managing` so the real
	-- signal was then ignored. Only a hard runaway cap remains, so GC can't hang forever.
	-- CO-OP uses the same cap as everything else (see the RUNAWAY_CAP_S comment above for
	-- why a shorter co-op-only cap was tried and reverted 2026-09-11b).
	if match_armed and managed_elapsed >= RUNAWAY_CAP_S then
		print(string.format("gc_result: runaway cap — %.0fs managed with no round-end signal: emitting undetermined", managed_elapsed))
		emit_result()   -- winner 0 -> GC shows the manual buttons
		match_armed = false
	end

	-- Refined re-emit after a fast emit (Level:Complete), once the score has had
	-- REPORT_DELAY to populate (higher seq wins on GC).
	if report_pending then
		report_accum = report_accum + step
		snapshot()
		if report_accum >= REPORT_DELAY then
			report_pending = false
			if match_armed then
				emit_result()
				match_armed = false
			end
		end
	end

end)

EventManager.Listen("ServerPlayer:Killed", function(victim, inflictor, weapon)
	pcall(function()
		if inflictor ~= nil and (inflictor.team == 1 or inflictor.team == 2) then
			kill_tally[inflictor.team] = kill_tally[inflictor.team] + 1
			-- Blast only, per BLAST_KILL_TARGET's own comment: don't wait for a round-end
			-- signal that's proven unreliable for this mode — the instant a team reaches the
			-- kill target IS the round ending, full stop. `match_armed` guards against firing
			-- twice (it's the same guard every other emit_result() call site already uses) —
			-- once this fires it goes false, so a kill landing a moment later (network lag,
			-- players still fighting while the level tears down) can't re-trigger it.
			if match_armed and mode_name == "Blast" and kill_tally[inflictor.team] >= BLAST_KILL_TARGET then
				print(string.format("gc_result: Blast reached %d kills (%d-%d) — emitting now, not waiting for a round-end signal",
					BLAST_KILL_TARGET, kill_tally[1], kill_tally[2]))
				snapshot()
				emit_result()
				match_armed = false
			end
		end
	end)
end)

EventManager.Listen("ServerPlayer:Spawned", function(player)
	if not managing then return end
	pcall(function()
		if not player then return end
		-- Put a human on the faction team GC says they should be on (a match can carry a
		-- team over from a co-op / previously-hosted mode). wanted_team_for checks the
		-- per-id human_teams table (online two-player) before the shared human_team value
		-- (single player / local hotseat).
		local want = wanted_team_for(player)
		if not player.isBot and want ~= 0 and player.team ~= want then
			local from = player.team
			local ok = pcall(function() player:SetTeam(want) end)
			print(string.format("gc_result: HUMAN team %s -> %d (id %s, %s)%s",
				tostring(from), want, tostring(player.playerId),
				(want == 1) and team_label_1 or team_label_2,
				ok and "" or " (SetTeam FAILED)"))
		end
		if (player.team == 1 or player.team == 2) and not player.isBot and spawn_logs < 3 then
			spawn_logs = spawn_logs + 1
			print(string.format("gc_result: human spawn on team %d", player.team))
		end
	end)
end)

-- Round-end handler, shared by Level:Complete and the engine end-of-round messages below.
local function on_round_end(tag)
	print("gc_result: round-end signal: " .. tag)
	accept_pending()
	if match_armed then
		snapshot()
		emit_result()
		if not report_pending then
			report_pending = true
			report_accum = 0.0
		end
	end
end

EventManager.Listen("Level:Complete", function() on_round_end("Level:Complete") end)

-- 2026-09-09 debug capture: Level:Complete NEVER fires on this listen server, but the
-- engine sends `OnlineNetworkEndOfRoundStateMessage` + `NetworkMetricsLevelCompleteMessage`
-- exactly once at the true match end (right after `In_VictoryDeclarationTeam<N>Won`), and
-- `WSUINetworkScoreEventMessage` on score / ticket / phase changes. Try binding those
-- engine message classes as events — if KYBER's EventManager surfaces them, one is the
-- reliable round-end trigger (and may carry the winner). Cheap: does nothing unless a
-- binding actually fires.
for _, name in ipairs({ "OnlineNetworkEndOfRoundStateMessage", "NetworkMetricsLevelCompleteMessage" }) do
	pcall(function()
		EventManager.Listen(name, function(a, b, c)
			print(string.format("gc_result: >>> ENGINE MSG %s (%s / %s / %s)", name,
				tostring(a), tostring(b), tostring(c)))
			on_round_end(name)
		end)
	end)
end
pcall(function()
	EventManager.Listen("WSUINetworkScoreEventMessage", function(a, b, c)
		print(string.format("gc_result: >>> SCORE MSG (%s / %s / %s)", tostring(a), tostring(b), tostring(c)))
	end)
end)

Console.Register("gc", "gc_result", "Re-send the last GC match result", {}, function()
	if last_line ~= nil then
		broadcast(last_line)
		return last_line
	end
	return "gc_result: no result yet"
end)
