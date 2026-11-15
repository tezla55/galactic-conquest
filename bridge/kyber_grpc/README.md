# KYBER interface .proto files (vendored, verbatim)

`Proto/kyber_common.proto`, `Proto/kyber_api.proto`, `Proto/kyber_interface.proto` are exact
copies of KYBER's own published gRPC interface definitions, fetched 2026-09-11:

https://github.com/ArmchairDevelopers/Kyber/blob/ver/beta10/Module/Proto/

`LICENSE` is that repo's own GPLv3, copied alongside for attribution. These are schema files
only — used here purely to let `grpcurl` know how to talk to KYBER's own local interface
server; nothing from KYBER's C++ implementation is used or linked. `kyber_api.proto` is
vendored only because `kyber_interface.proto` imports it (unused otherwise — it's the
*cloud* API's schema, a completely different, remote service).

**Why this exists:** `bridge/kyber_grpc.gd` (`KyberGrpc`) is an experimental, parallel path
to `bridge/kyber_plugin/gc_result/` — instead of driving KYBER through an injected Lua
plugin, it calls the **local** gRPC interface the injected `Kyber.dll` module itself hosts
(confirmed via `Module/Source/RPC/InterfaceService.cpp`: plaintext, no TLS, port 3005 by
default, overridable via `KYBER_INTERFACE_PORT`). The user wanted to know whether this route
is more capable than the Lua sandbox we've hit real limits in. **Traced from these exact
`.proto` files, the honest answer is: partially.**

- `kyber_interface.Common/RunCommand` — runs any console command from *outside* the game
  entirely, no plugin required. Same underlying power as `Console.Execute()` in Lua, so it
  sidesteps Lua-sandbox-specific bugs (`TypeInfo:isKindOf` not existing, etc.) for issuing
  commands, but doesn't unlock anything Lua couldn't already do here.
- `kyber_interface.Common/GetInfo` — current server state: id, level/mode, and a player list
  — but `kyber_common.ServerPlayer` only has `id`, `name`, `teamId`. **No kills, deaths, or
  score field exists on it at all** — strictly less than the Lua `Player` binding (which at
  least has those fields, even though `.score`/`.deaths` read 0 for us; `.kills`/`.assists`
  are unconfirmed dead too, `2026-09-11c`).
- **No event-subscription RPC anywhere on this local interface** — confirmed by reading every
  `.proto` file for the `stream` keyword: the only streaming RPC in the whole schema
  (`Proxy.EventSubscription`, `kyber_api.proto`) belongs to KYBER's *remote cloud* API, for
  proxy servers, not the local injected module. So this interface can issue commands and poll
  state, but it has **no way to react to a kill, a spawn, or a round ending** — those need
  `EventManager.Listen` in the Lua plugin, which this cannot replace.

No native gRPC client in Godot/GDScript, so `KyberGrpc` shells out to
[`grpcurl`](https://github.com/fullstorydev/grpcurl) (MIT, a small single-file CLI) per call,
the same pattern `KyberPluginInstaller` already uses for `powershell`/`tasklist`. **You need
to download `grpcurl.exe` yourself** (a Windows release from that repo) and place it at
`tools/grpcurl.exe` in this project — `KyberGrpc.grpcurl_present()` checks for it there and
every call fails with a clear message (naming that exact path) if it's missing.

**Two bugs the first live test caught, both in the `grpcurl` invocation, not the approach:**
1. `-import-path` pointed straight at `Proto/` — wrong. The vendored files' own `import
   "Proto/kyber_common.proto"` statements (copied verbatim from KYBER's `Module/Proto/`
   layout) resolve as `<import-path>/Proto/...`, so import-path has to be the *parent* of
   `Proto/` (`bridge/kyber_grpc/`, not `bridge/kyber_grpc/Proto/`) — confirmed live: pointing
   at `Proto/` directly made grpcurl look for `Proto/Proto/kyber_common.proto` and fail.
2. The JSON request body was passed inline as a `-d` command-line argument — broke the moment
   the value contained a space (`{"command": "AutoPlayers.ForceFillGameplayBotsTeam1 20"}"`),
   with grpcurl itself reporting "Too many arguments" (Windows has no real argv; the child
   re-parses one command-line string, and that value doesn't survive re-quoting reliably).
   **First fix attempt was also wrong**: assumed grpcurl's `-d` supported an `@<path>`
   file-reading form (curl does; grpcurl doesn't — its own `-help` text says `-d`'s only
   special value is a bare `@`, which reads from stdin, nothing else) and routed the body
   through a temp file that way. That produced a NEW, different error the moment it was
   tried live: `error getting request data: invalid character '@' looking for beginning of
   value` — grpcurl was trying to JSON-decode the literal text `@<path>` as the request body,
   because that flag form never existed. **Real fix, found by testing directly against
   grpcurl.exe rather than guessing a third time**: the actual cause of the original "Too
   many arguments" was `OS.execute()` on Windows not escaping embedded `"` characters when
   it quotes a spaced argument for the child's command line — confirmed live that a spaced
   value with NO quote characters at all passes through fine (a real dial attempt happens),
   while the exact same value WITH JSON's own quotes reliably reproduces "Too many
   arguments" (the embedded quotes flip Windows' "am I inside quotes" parsing, so the space
   ends up unprotected and splits the argument in two). Backslash-escaping each `"` as `\"`
   before handing the JSON string to `OS.execute()` — standard Windows/CRT argv escaping —
   fixed it for real: `KyberGrpc._win_arg_escape()`, no temp file needed at all. Known,
   documented limitation: it doesn't also double a backslash that precedes a quote (the full
   MS quoting algorithm's other half), which nothing GC actually sends today needs, but would
   matter for a command value containing a literal backslash right before a quote.

**A third bug, worse than the first two: a dead server froze the whole GC window.**
`call_rpc()` is `OS.execute(..., blocking=true)` on the main thread with no timeout — a real
unreachable server took 13s+ to fail ("context deadline exceeded"), and for that whole time
GC's UI didn't respond at all. Fixed on two levels: `-connect-timeout 3` / `-max-time 6` cap
grpcurl's own dial/call so a dead server fails in seconds instead of indefinitely
(`CONNECT_TIMEOUT_S` / `MAX_TIME_S`); and `call_rpc_async(service_method, body, on_done,
port)` runs the whole blocking call on a background `Thread`, delivering the result on the
main thread via `Callable.call_deferred()` — the Log panel's two gRPC buttons use
`run_command_async` / `get_info_async` now, disabling themselves and showing
"(waiting...)" instead of locking up the window. `call_rpc()` stays synchronous underneath;
the async wrapper just calls it from the worker thread.

**Fourth: not a failed bind at all — the wrong port, every single time.** The `netstat`
check right after the fix above (nothing on 3005, with a real match visibly running) was read
as "the bind silently failed" — traced into KYBER's source
(`Module/Source/Core/Program.cpp`/`InterfaceService.cpp`) and found a real, separate bug
there too: `InterfaceService`'s constructor never checks `builder.BuildAndStart()`'s return
value before unconditionally logging `KYBER_LOG(Info, "[RPC] Started interface server on
port " << port)`, so that line would print regardless of whether the port actually bound.
**That bug is real but turned out not to be what was happening here.** Checking the actual
KYBER log (`%APPDATA%/ArmchairDevelopers/Kyber/Logs/kyber_<date>.log` —
`KyberLogReader.log_path()`) for every `"[RPC] Started interface server on port"` line from
that same day found **nine, one per KYBER relaunch, every one a different port**: 55680,
65474, 63581 (×2), 58147, 51797, 59134, 58281, 52048, 61967 — none of them 3005, and
`KYBER_INTERFACE_PORT=3005` was set every single time. The one active nearest the failed
dial's timestamp was 51797, not 3005. The log's own `"[Engine] Initializing KYBER
v2.0.0-beta8"` line explains why: the installed build is **v2.0.0-beta8**, not the
`ver/beta10` branch this whole investigation (including the `isKindOf` casing chase) was
read from — an older/different build that plainly binds an ephemeral port each launch and
ignores both the fixed 3005 default and the env var override. The bind was very likely
succeeding the whole time; we were just always dialing the wrong number.

**Fix: `KyberGrpc.discover_port()` reads the real port out of KYBER's own log instead of
trusting any fixed number or env var.** It takes the LAST `"[RPC] Started interface server on
port <N>"` line in today's log (a restarted KYBER logs one per launch; only the most recent
describes the currently-running process), reading a tail window that doubles until the
marker turns up or the whole file's covered — the log can be huge with debug logging on (189
MB observed) and this runs on every call, so it deliberately avoids a full linear scan in the
common case. `call_rpc()` / `run_command()` / `get_info()` / their `_async` twins all default
`port` to `-1`, meaning "look it up"; `DEFAULT_PORT` (3005) is now only the last-resort
fallback if the log can't be found or read at all. These lines were already flowing into GC's
own Log panel the whole time (`KyberLogReader.KEEP` already includes `"[RPC]"`) — nobody
had connected them to the gRPC dial failures until checking the raw log file directly.
