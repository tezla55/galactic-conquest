class_name GcNet
extends RefCounted

## Peer-to-peer link between two GC instances for online play. Two transports:
##
##  - **TCP** (the original path): the host listens, the joiner dials in directly. Needs the
##    host's port forwarded or UPnP-mapped — see bridge/gc_upnp.gd.
##  - **UDP hole punch** (`2026-09-22`, playtest 921: "I don't want users to have to download
##    a program or mess with forwarding ports"): a fallback for when UPnP fails. Both sides
##    learn their own public IP:port via a public STUN server (bridge/gc_stun.gd — no account,
##    no infrastructure of ours), then the JOINER fires small `punch_hello` packets at the
##    host's address; the HOST, the instant it sees one, now knows the joiner's real address
##    too and starts answering with the same `hello` handshake the TCP path already sends.
##    This is genuinely best-effort, not a guaranteed fix — see this file's own header note
##    below for exactly which NAT types it can and can't get through. No relay/rendezvous
##    server either way (see bridge/join_code.gd's header for why: no new infrastructure to
##    run/pay for) — a real TURN-style relay remains the honest "always works" upgrade this
##    project has deliberately not built.
##
## Same shape as KyberLink's own socket handling either way: `poll()` called every frame,
## `_ingest(String)` / `_handle_message(Dictionary)` are the test seams (no real socket in
## CI — see this file's own tests for what that means for the UDP path specifically).
##
## The HOST is the sole authority: only the host ever calls TurnResolver. It creates the
## campaign (`state.two_player = true`, no AI, no starting bonus — a two-player campaign,
## just played over a wire instead of a shared keyboard) once a client connects, and after
## every change sends a full `{"type":"state","state":<GalaxyState.to_dict()>}` snapshot —
## simplest possible protocol for a small, infrequently-changing state; no reason to diff
## when the whole thing is a few KB and moves happen at human speed. The CLIENT never
## mutates its own `state` from local input: every action becomes an
## `{"type":"intent","action":{...}}` message using the exact same action-dict shape
## AiCommander's own plan already does (`{"type":"move","fleet_id":,"dest":}`, `{"type":
## "buy"}`, `{"type":"reinforce","fleet_id":}`, `{"type":"train","fleet_id":}`,
## `{"type":"end_turn"}`, `{"type":"battle_result","victor":}`) — the host applies it
## through the SAME TurnResolver entry points its own local player uses, so no new game
## logic exists anywhere in this file. `hello` (host -> client, once) hands over which
## faction the client is playing and the campaign's initial state in one message.
##
## **UDP hole-punch NAT coverage, honestly**: works whenever at least one side's own NAT is
## "full cone" or "restricted cone" (the large majority of consumer home routers) — the
## joiner's repeated `punch_hello` opens its own NAT's return path, and the host's own reply
## the instant it sees one opens the host's. It CANNOT get through a "symmetric" NAT on
## BOTH ends (each assigns a different external port per destination, so the address either
## side discovered via STUN is never the one the other side's packets actually need), nor
## CGNAT (the ISP's own NAT layer, common on mobile data and some ISPs, which no amount of
## client-side punching can open). Those cases — same as a UPnP-incapable router — fall back
## to the existing manual port-forward / VPN-mesh-tool guidance. This has NOT been verified
## against two real home routers (no second real network to test against here) — the STUN
## byte-level protocol is unit-tested to the letter of RFC 5389, but "does this actually get
## a packet through your specific router" is inherently a live-network question.
##
## **Known gap, UDP path specifically**: unlike TCP, a dropped UDP link has no socket-level
## "the peer is gone" signal — this only detects a failure to connect in the FIRST place
## (the join-side punch timeout), not a mid-session silent drop. Ordinary traffic (state/
## intent/error/hello) is sent twice back-to-back as a cheap loss mitigation and carries a
## monotonic `_seq` the receiver dedupes against — not a full reliable-transport guarantee,
## appropriate for this protocol's low frequency and idempotent full-state snapshots.

signal peer_joined                          ## host: a client just connected
signal joined(host_faction: StringName, my_faction: StringName, campaign_id: StringName, initial_state: Dictionary)
signal state_received(state_dict: Dictionary)
signal intent_received(action: Dictionary)
signal error_received(reason: String)       ## client: the host rejected the last intent
signal disconnected
signal punch_progress(seconds_left: float)  ## client, UDP only: still trying, for a "still attempting…" UI

enum Role { NONE, HOST, CLIENT }
enum Transport { TCP, UDP }

const DEFAULT_PORT := 45703   # distinct from KyberLink's 45702, same machine can run both
const PUNCH_RETRY_MS := 300
const PUNCH_TIMEOUT_MS := 15000

var role: int = Role.NONE
var my_faction: StringName = &""     ## fixed for the whole session once assigned
var peer_connected := false

var _server := TCPServer.new()
var _peer: StreamPeerTCP = null
var _in_buf := ""
var _listen_port := 0
var _client_active := false   ## client only: true from join()/join_udp() until a terminal disconnect fires

var _transport: int = Transport.TCP
var _udp: PacketPeerUDP = null
var _remote_ip := ""
var _remote_port := 0
var _local_udp_port := 0
var _send_seq := 0
var _last_seq_seen := -1
var _last_hello_msg: Dictionary = {}   ## host, UDP only: resent verbatim if the joiner is still punching after we already answered once
var _punch_deadline_ms := 0
var _punch_last_send_ms := 0


## Start listening. `faction` is which side the HOST plays; the joiner gets the other one
## once they connect (see host_send_hello). Does not block — call peer_joined-connected
## checks (or just poll `peer_connected`) each frame.
func host(port: int, faction: StringName) -> bool:
	close()
	role = Role.HOST
	my_faction = faction
	_listen_port = port
	return _server.listen(port) == OK


## Dial the host directly. `join_code.gd` turns a typed code back into ip/port for this.
func join(host_ip: String, port: int) -> bool:
	close()
	role = Role.CLIENT
	_peer = StreamPeerTCP.new()
	_client_active = _peer.connect_to_host(host_ip, port) == OK
	return _client_active


## UDP fallback, host side: binds `local_port` and waits — it does not yet know the joiner's
## address (that arrives reactively, the moment their first `punch_hello` lands; see
## _handle_udp_message). Call GcStun.discover_async(udp_socket(), ...) on the SAME socket
## right after this succeeds, to learn the public IP:port to put in the join code — STUN only
## tells you anything useful about the specific local port it was asked through.
func host_udp(local_port: int, faction: StringName) -> Dictionary:
	close()
	role = Role.HOST
	my_faction = faction
	_transport = Transport.UDP
	_udp = PacketPeerUDP.new()
	var err := _udp.bind(local_port)
	if err != OK:
		role = Role.NONE
		_transport = Transport.TCP
		return {"ok": false, "reason": "couldn't bind local UDP port %d (%s)" % [local_port, error_string(err)]}
	_local_udp_port = local_port
	return {"ok": true}


## UDP fallback, joining side: binds `local_port` and immediately starts firing `punch_hello`
## at the host's (STUN-discovered) address every PUNCH_RETRY_MS, for up to PUNCH_TIMEOUT_MS —
## `peer_joined`/`joined` fire exactly as the TCP path's do the moment the host answers;
## `disconnected` fires if the whole window elapses with no answer (this NAT combination
## needs the manual/VPN fallback instead).
func join_udp(local_port: int, host_ip: String, host_port: int) -> Dictionary:
	close()
	role = Role.CLIENT
	_transport = Transport.UDP
	_udp = PacketPeerUDP.new()
	var err := _udp.bind(local_port)
	if err != OK:
		role = Role.NONE
		_transport = Transport.TCP
		return {"ok": false, "reason": "couldn't bind local UDP port %d (%s)" % [local_port, error_string(err)]}
	_local_udp_port = local_port
	_remote_ip = host_ip
	_remote_port = host_port
	_client_active = true
	_punch_deadline_ms = Time.get_ticks_msec() + PUNCH_TIMEOUT_MS
	_punch_last_send_ms = 0   # fire the first punch_hello on the very next poll(), not after a delay
	return {"ok": true}


## The bound UDP socket, once host_udp()/join_udp() has been called — pass this straight to
## GcStun.discover_async so discovery happens on the SAME local port punching will use.
func udp_socket() -> PacketPeerUDP:
	return _udp


func close() -> void:
	if _peer != null:
		_peer.disconnect_from_host()
	_peer = null
	if _udp != null:
		_udp.close()
	_udp = null
	_server.stop()
	role = Role.NONE
	my_faction = &""
	peer_connected = false
	_client_active = false
	_in_buf = ""
	_transport = Transport.TCP
	_remote_ip = ""
	_remote_port = 0
	_send_seq = 0
	_last_seq_seen = -1
	_last_hello_msg = {}
	_punch_deadline_ms = 0
	_punch_last_send_ms = 0


func is_peer_connected() -> bool:
	return peer_connected


func poll() -> void:
	if _transport == Transport.UDP:
		_poll_udp()
		return
	match role:
		Role.HOST:
			_poll_host()
		Role.CLIENT:
			_poll_client()


## GC's own link is strictly 1v1 (see this file's own header) — a third person trying to
## join a game that already has its two commanders would otherwise just hang forever with
## no explanation (`2026-09-21` playtest 921: "what happens if more than one player joins").
## A late arrival is accepted just long enough to say why, then dropped; the real peer
## (and the game) is untouched.
const ALREADY_FULL_REASON := "This game already has two players — Galactic Conquest online play is 1v1."

func _poll_host() -> void:
	if _server.is_connection_available():
		if _peer == null:
			_peer = _server.take_connection()
			peer_connected = true
			peer_joined.emit()
		else:
			var extra := _server.take_connection()
			extra.poll()
			extra.put_data((JSON.stringify({"type": "error", "reason": ALREADY_FULL_REASON}) + "\n").to_utf8_buffer())
			extra.disconnect_from_host()
	if _peer == null:
		return
	_peer.poll()
	match _peer.get_status():
		StreamPeerTCP.STATUS_CONNECTED:
			_drain()
		StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
			if peer_connected:
				_peer = null
				peer_connected = false
				disconnected.emit()   # keep listening — _server itself stays open for a rejoin


func _poll_client() -> void:
	if _peer == null:
		return
	_peer.poll()
	match _peer.get_status():
		StreamPeerTCP.STATUS_CONNECTED:
			peer_connected = true
			_drain()
		StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
			# Fires whether the connection never succeeded at all (host unreachable / not
			# listening / port not forwarded) or dropped after being connected for a while —
			# `_client_active` covers both, where a plain `if peer_connected` (as it read
			# before) only ever caught the second case and left a failed join attempt with
			# no signal at all.
			if _client_active:
				_client_active = false
				peer_connected = false
				disconnected.emit()


func _drain() -> void:
	var available := _peer.get_available_bytes()
	if available > 0:
		var chunk := _peer.get_data(available)
		if chunk[0] == OK:
			_ingest((chunk[1] as PackedByteArray).get_string_from_utf8())


## Every inbound datagram, plus (client, not yet connected) the punch_hello retry loop.
func _poll_udp() -> void:
	if _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		var bytes := _udp.get_packet()
		var from_ip := _udp.get_packet_ip()
		var from_port := _udp.get_packet_port()
		_handle_udp_datagram(bytes, from_ip, from_port)

	if role == Role.CLIENT and not peer_connected and _client_active:
		var now := Time.get_ticks_msec()
		if now >= _punch_deadline_ms:
			_client_active = false
			disconnected.emit()
		elif now - _punch_last_send_ms >= PUNCH_RETRY_MS:
			_punch_last_send_ms = now
			punch_progress.emit(maxf(0.0, float(_punch_deadline_ms - now) / 1000.0))
			_udp.set_dest_address(_remote_ip, _remote_port)
			_udp.put_packet(JSON.stringify({"type": "punch_hello"}).to_utf8_buffer())


func _handle_udp_datagram(bytes: PackedByteArray, from_ip: String, from_port: int) -> void:
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return
	var msg: Dictionary = parser.data
	var kind := String(msg.get("type", ""))
	if kind == "punch_hello":
		_handle_punch_hello(from_ip, from_port)
		return
	# Ordinary traffic: only from the address we've already settled on (host) / dialled
	# (client) — a stray packet from anywhere else on the same port is never mistaken for
	# the real peer. The client has no TCP-style "socket connected" fact to key off of, so
	# its FIRST real message (normally `hello`) from the address it dialled is what actually
	# marks it connected here — a message from anywhere else is dropped, not trusted.
	if role == Role.CLIENT and not peer_connected:
		if from_ip != _remote_ip or from_port != _remote_port:
			return
		peer_connected = true
	elif peer_connected and (from_ip != _remote_ip or from_port != _remote_port):
		return
	# Deduped by the embedded `_seq` (see _send_udp) — a message we've already processed (a
	# redundant send, or the host resending a stale `_last_hello_msg` the joiner already got)
	# is silently dropped rather than re-applied.
	var seq := int(msg.get("_seq", -1))
	if seq >= 0:
		if seq <= _last_seq_seen:
			return
		_last_seq_seen = seq
	_handle_message(msg)


## Host, UDP only: the moment ANY punch_hello arrives, its sender IS the joiner — GC never
## needed to know that address in advance (see this file's header on why the joiner has to
## be the one dialling blind). First contact: latch the address and announce peer_joined
## exactly like the TCP path does (main.gd's existing handler then calls host_send_hello()
## with no changes needed there at all). Later contact from the SAME address, after we've
## already answered once: the joiner is still retrying because our answer hasn't reached
## them yet — resend it, rather than make them wait out the rest of their own timeout.
func _handle_punch_hello(from_ip: String, from_port: int) -> void:
	if role != Role.HOST:
		return
	if not peer_connected:
		_remote_ip = from_ip
		_remote_port = from_port
		peer_connected = true
		peer_joined.emit()
	elif _udp != null and from_ip == _remote_ip and from_port == _remote_port and not _last_hello_msg.is_empty():
		_udp.set_dest_address(_remote_ip, _remote_port)
		var raw := JSON.stringify(_last_hello_msg).to_utf8_buffer()
		_udp.put_packet(raw)
		_udp.put_packet(raw)


## Host -> client, once, right after peer_joined: assigns the client's faction and hands
## over the freshly-created campaign in one message.
func host_send_hello(host_faction: StringName, campaign_id: StringName, initial_state: Dictionary) -> bool:
	return _send({
		"type": "hello",
		"host_faction": String(host_faction),
		"campaign_id": String(campaign_id),
		"state": initial_state,
	})


func send_state(state_dict: Dictionary) -> bool:
	return _send({"type": "state", "state": state_dict})


func send_intent(action: Dictionary) -> bool:
	return _send({"type": "intent", "action": action})


## Host -> client: the last intent didn't apply (out of turn, invalid move, broke, …) so the
## client's screen can say why instead of the action just silently not happening.
func host_send_error(reason: String) -> bool:
	return _send({"type": "error", "reason": reason})


func _send(msg: Dictionary) -> bool:
	if _transport == Transport.UDP:
		return _send_udp(msg)
	if _peer == null or not peer_connected:
		return false
	var err := _peer.put_data((JSON.stringify(msg) + "\n").to_utf8_buffer())
	return err == OK


## Sent TWICE back-to-back (cheap loss mitigation — see this file's header) with a monotonic
## `_seq` the far end dedupes against. `hello` is cached verbatim so a joiner who is still
## punching after we've already answered gets it resent without GC noticing or doing anything
## (see _handle_punch_hello).
func _send_udp(msg: Dictionary) -> bool:
	if _udp == null or not peer_connected:
		return false
	msg = msg.duplicate(true)
	msg["_seq"] = _send_seq
	_send_seq += 1
	if String(msg.get("type", "")) == "hello":
		_last_hello_msg = msg.duplicate(true)
	_udp.set_dest_address(_remote_ip, _remote_port)
	var raw := JSON.stringify(msg).to_utf8_buffer()
	var ok1 := _udp.put_packet(raw) == OK
	var ok2 := _udp.put_packet(raw) == OK
	return ok1 or ok2


# --- internals (also the test seam: _ingest / _handle_message take raw text / a parsed dict,
# no socket needed — the UDP path's own datagram handling above is a thin wrapper around the
# exact same _handle_message, kept in sync by construction rather than duplicated) ----------

func _ingest(text: String) -> void:
	_in_buf += text
	while true:
		var nl := _in_buf.find("\n")
		if nl == -1:
			break
		var line := _in_buf.substr(0, nl).strip_edges()
		_in_buf = _in_buf.substr(nl + 1)
		if not line.is_empty():
			_handle_line(line)


func _handle_line(line: String) -> void:
	var parser := JSON.new()
	if parser.parse(line) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return
	_handle_message(parser.data as Dictionary)


func _handle_message(msg: Dictionary) -> void:
	match String(msg.get("type", "")):
		"hello":
			var host_faction := StringName(msg.get("host_faction", &""))
			my_faction = Faction.opponent(host_faction)
			joined.emit(host_faction, my_faction, StringName(msg.get("campaign_id", &"")),
				(msg.get("state", {}) as Dictionary))
		"state":
			state_received.emit(msg.get("state", {}))
		"intent":
			intent_received.emit(msg.get("action", {}))
		"error":
			error_received.emit(String(msg.get("reason", "The host rejected that.")))
