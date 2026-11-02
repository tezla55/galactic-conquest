class_name GcUpnp
extends RefCounted

## Best-effort automatic port forwarding for online hosting, via UPnP/IGD — the same
## protocol most consumer routers already speak for things like game consoles opening their
## own ports with no manual router login. This is what removes the "forward this port
## yourself" step for the common case: most home routers ship with UPnP on by default.
##
## Deliberately NOT a full NAT-traversal solution — a genuine no-exceptions fix (working
## behind CGNAT, a UPnP-disabled router, or a business network) needs a relay/rendezvous
## server both sides connect OUT to, which CLAUDE.md's online-multiplayer section already
## chose not to build (no infrastructure to run or pay for, matching how KYBER hosting
## itself is peer-hosted). UPnP is the zero-infrastructure middle ground: it fixes the
## common home-network case for free, and degrades to nothing (never a crash, never a hang
## longer than Godot's own UPNP.discover() timeout) everywhere else — main.gd falls back to
## showing the existing manual "forward this port" instructions whenever it doesn't work.
##
## No test seam / no automated test file: unlike bridge/kyber_grpc.gd's discover_port()
## (pure log-text parsing, fully testable headless), there is no pure logic here to isolate
## from the live UPNP class — discover()/add_port_mapping() are real network I/O against
## whatever router (if any) answers on this machine's LAN, the same reason call_rpc()'s own
## real network path has no direct test either. Exercising this for real needs an actual
## router and a live two-PC test, not something headless CI can stand in for.

const DESCRIPTION := "Galactic Conquest"

## Synchronous — discover() alone can take a couple of seconds on some routers (or the full
## timeout on a network with none at all), so callers on the main thread should use
## try_map_port_async() instead; this exists as the plain, testable-in-principle core call.
## Returns {"ok": true} or {"ok": false, "reason": String}.
static func try_map_port(port: int, description: String = DESCRIPTION) -> Dictionary:
	var upnp := UPNP.new()
	var discover_err := upnp.discover()
	if discover_err != UPNP.UPNP_RESULT_SUCCESS:
		return {"ok": false, "reason": "no UPnP-capable router found on this network"}
	var gateway := upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		return {"ok": false, "reason": "this router doesn't support UPnP (or it's turned off)"}
	# Clear any stale mapping from an earlier, uncleanly-ended session first — add_port_mapping
	# can fail with a "conflict" result if one already exists under our own description.
	upnp.delete_port_mapping(port, "TCP")
	var map_err := upnp.add_port_mapping(port, port, description, "TCP", 0)
	if map_err != UPNP.UPNP_RESULT_SUCCESS:
		return {"ok": false, "reason": "the router refused the port-mapping request"}
	return {"ok": true}


## Best-effort cleanup — call when hosting ends (cancelled or disconnected) so a stale
## mapping doesn't linger on the router pointing at a port nothing is listening on anymore.
## Silently does nothing if UPnP isn't available; never surfaced to the player either way.
static func remove_mapping(port: int) -> void:
	var upnp := UPNP.new()
	if upnp.discover() == UPNP.UPNP_RESULT_SUCCESS:
		upnp.delete_port_mapping(port, "TCP")


## `on_done` (Dictionary -> void) runs on the MAIN thread (Callable.call_deferred(), same
## pattern as KyberGrpc.call_rpc_async — safe to touch UI from it) once discovery/mapping
## finishes. Use this from the hosting screen instead of try_map_port() directly — a UPnP
## round-trip against a real router is a genuine multi-second network wait, and CLAUDE.md's
## "never call a blocking OS.execute from _refresh()" rule applies just as hard to a
## blocking UPNP call from _ready()/a button handler.
static var _threads: Array[Thread] = []

static func try_map_port_async(port: int, on_done: Callable, description: String = DESCRIPTION) -> void:
	var thread := Thread.new()
	_threads.append(thread)
	thread.start(func() -> void:
		var result := try_map_port(port, description)
		on_done.call_deferred(result)
		_join_thread.call_deferred(thread)
	)


static func _join_thread(thread: Thread) -> void:
	thread.wait_to_finish()
	_threads.erase(thread)
