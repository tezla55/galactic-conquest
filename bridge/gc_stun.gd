class_name GcStun
extends RefCounted

## A minimal STUN (RFC 5389) client — just enough to ask a public STUN server "what does my
## own address look like from outside my router?" (a Binding Request/Response), which is the
## first half of UDP hole punching (bridge/gc_holepunch.gd does the second half: getting a
## packet through the NAT to a specific peer once both sides know where the other is).
##
## Deliberately not a general STUN/TURN/ICE implementation — one request type, one attribute
## family (IPv4 XOR-MAPPED-ADDRESS, with a fallback to the older plain MAPPED-ADDRESS some
## STUN servers still send), no authentication, no fragmentation. That is genuinely all a
## Binding Request needs: https://www.rfc-editor.org/rfc/rfc5389 §6, §15.1-15.2.
##
## Packet building/parsing here is pure (no socket) and unit-tested directly — the actual
## "send this over a UDP socket and wait" is a thin, untestable-headless wrapper below, same
## split as bridge/gc_upnp.gd's try_map_port() (pure, testable-in-principle) vs.
## try_map_port_async() (real I/O, no test seam).

const MAGIC_COOKIE := 0x2112A442
const BINDING_REQUEST := 0x0001
const BINDING_SUCCESS := 0x0101
const BINDING_ERROR := 0x0111
const ATTR_MAPPED_ADDRESS := 0x0001
const ATTR_XOR_MAPPED_ADDRESS := 0x0020
const FAMILY_IPV4 := 0x01

## A public server list needing no account and no infrastructure of our own — Google's public
## STUN service, used by countless WebRTC apps for exactly this. Several entries so one being
## down/blocked doesn't sink the whole attempt; tried in order by the async wrapper below.
## `2026-09-24` (playtest 922): a player on a wireless connection saw hole-punching fail at
## the very first step ("no STUN server answered") — all three original entries were Google's
## own anycast service on the SAME port (19302), so a block of that one endpoint/port fails
## all three identically. Two more, from different operators on different ports (Cloudflare's
## own public STUN, and Nextcloud's, notably on 443 — a port far more likely to survive a
## strict UDP allowlist than 19302/3478), give a second and third independent thing to try.
## Doesn't fix a network with NO outbound UDP allowed anywhere (nothing can, short of a relay
## reachable over a protocol that network already permits) — see gc_net.gd's own header.
const PUBLIC_SERVERS: Array[Dictionary] = [
	{"host": "stun.l.google.com", "port": 19302},
	{"host": "stun1.l.google.com", "port": 19302},
	{"host": "stun2.l.google.com", "port": 19302},
	{"host": "stun.cloudflare.com", "port": 3478},
	{"host": "stun.nextcloud.com", "port": 443},
]


## A fresh Binding Request: {"packet": PackedByteArray, "transaction_id": PackedByteArray}.
## `transaction_id` is 12 random bytes the caller must keep to match against the reply
## (parse_binding_response rejects a response for any other transaction — stray/late traffic
## on the same socket, e.g. an old server's slow reply after a timeout, must never be
## mistaken for the current one).
static func build_binding_request() -> Dictionary:
	var txn := Crypto.new().generate_random_bytes(12)
	var packet := PackedByteArray()
	packet.resize(20)
	_put_u16(packet, 0, BINDING_REQUEST)
	_put_u16(packet, 2, 0)   # message length — no attributes on a plain request
	_put_u32(packet, 4, MAGIC_COOKIE)
	for i in 12:
		packet[8 + i] = txn[i]
	return {"packet": packet, "transaction_id": txn}


## {"ok": true, "ip": String, "port": int} on a Binding Success Response for `expected_txn`
## naming OUR public IPv4 address as seen by the server; {"ok": false, "reason": String}
## otherwise (wrong transaction, an error response, IPv6-only, or a malformed/foreign packet
## — anything that isn't unambiguously "this is our answer" is rejected, not guessed at).
static func parse_binding_response(bytes: PackedByteArray, expected_txn: PackedByteArray) -> Dictionary:
	if bytes.size() < 20:
		return {"ok": false, "reason": "too short for a STUN header"}
	var msg_type := _get_u16(bytes, 0)
	var msg_len := _get_u16(bytes, 2)
	var cookie := _get_u32(bytes, 4)
	if cookie != MAGIC_COOKIE:
		return {"ok": false, "reason": "not a STUN message (bad magic cookie)"}
	var txn := bytes.slice(8, 20)
	if txn != expected_txn:
		return {"ok": false, "reason": "transaction id doesn't match our request"}
	if msg_type == BINDING_ERROR:
		return {"ok": false, "reason": "server returned a STUN error response"}
	if msg_type != BINDING_SUCCESS:
		return {"ok": false, "reason": "not a Binding Success Response"}
	if bytes.size() < 20 + msg_len:
		return {"ok": false, "reason": "truncated attribute section"}

	# Walk the TLV attributes; XOR-MAPPED-ADDRESS is preferred (RFC 5389), MAPPED-ADDRESS
	# (RFC 3489, no XOR obfuscation) is the fallback some older/simpler servers still send.
	var mapped := {}
	var pos := 20
	var end := 20 + msg_len
	while pos + 4 <= end:
		var attr_type := _get_u16(bytes, pos)
		var attr_len := _get_u16(bytes, pos + 2)
		var val_start := pos + 4
		if val_start + attr_len > end:
			break   # malformed length — stop rather than read past the declared attribute section
		if attr_type == ATTR_XOR_MAPPED_ADDRESS and attr_len >= 8:
			var r := _parse_address_attr(bytes, val_start, true)
			if bool(r.get("ok", false)):
				return r   # preferred — take it immediately, don't keep scanning
		elif attr_type == ATTR_MAPPED_ADDRESS and attr_len >= 8 and mapped.is_empty():
			mapped = _parse_address_attr(bytes, val_start, false)
		pos = val_start + attr_len
		if attr_len % 4 != 0:
			pos += 4 - (attr_len % 4)   # attributes are padded to a 4-byte boundary
	if bool(mapped.get("ok", false)):
		return mapped
	return {"ok": false, "reason": "no IPv4 address attribute in the response"}


static func _parse_address_attr(bytes: PackedByteArray, at: int, xor: bool) -> Dictionary:
	var family := bytes[at + 1]
	if family != FAMILY_IPV4:
		return {"ok": false, "reason": "IPv6 address (not supported)"}
	var port := _get_u16(bytes, at + 2)
	var a0 := bytes[at + 4]
	var a1 := bytes[at + 5]
	var a2 := bytes[at + 6]
	var a3 := bytes[at + 7]
	if xor:
		port ^= (MAGIC_COOKIE >> 16) & 0xFFFF
		a0 ^= (MAGIC_COOKIE >> 24) & 0xFF
		a1 ^= (MAGIC_COOKIE >> 16) & 0xFF
		a2 ^= (MAGIC_COOKIE >> 8) & 0xFF
		a3 ^= MAGIC_COOKIE & 0xFF
	return {"ok": true, "ip": "%d.%d.%d.%d" % [a0, a1, a2, a3], "port": port}


static func _put_u16(b: PackedByteArray, at: int, v: int) -> void:
	b[at] = (v >> 8) & 0xFF
	b[at + 1] = v & 0xFF

static func _put_u32(b: PackedByteArray, at: int, v: int) -> void:
	b[at] = (v >> 24) & 0xFF
	b[at + 1] = (v >> 16) & 0xFF
	b[at + 2] = (v >> 8) & 0xFF
	b[at + 3] = v & 0xFF

static func _get_u16(b: PackedByteArray, at: int) -> int:
	return (b[at] << 8) | b[at + 1]

static func _get_u32(b: PackedByteArray, at: int) -> int:
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]


# --- real I/O: no test seam, same reasoning as gc_upnp.gd's async wrapper -------------------

const REQUEST_TIMEOUT_MS := 1500
const MAX_RETRIES_PER_SERVER := 2

## Discovers this machine's own public IP:port as seen from outside, for the UDP socket
## `udp` (already `bind()`'d to the local port that will actually be used for hole punching —
## STUN only tells you anything useful about the SAME local port/socket you go on to punch
## with; discovering a DIFFERENT socket's mapping is useless the instant that socket closes,
## and worse than useless if a symmetric NAT hands out a different external port per socket).
## Tries each of PUBLIC_SERVERS in turn. `on_done` (Dictionary -> void) runs on the caller's
## own poll — this is synchronous-blocking (wait_for on the socket), so call it from a Thread
## exactly like GcUpnp.try_map_port_async, never from _process()/a button handler directly.
static func discover(udp: PacketPeerUDP) -> Dictionary:
	for server in PUBLIC_SERVERS:
		for _attempt in MAX_RETRIES_PER_SERVER:
			var req := build_binding_request()
			udp.set_dest_address(String(server["host"]), int(server["port"]))
			if udp.put_packet(req["packet"]) != OK:
				continue
			var deadline := Time.get_ticks_msec() + REQUEST_TIMEOUT_MS
			while Time.get_ticks_msec() < deadline:
				if udp.get_available_packet_count() > 0:
					var reply := udp.get_packet()
					var parsed := parse_binding_response(reply, req["transaction_id"])
					if bool(parsed.get("ok", false)):
						return parsed
					# Not our answer (stray/late packet) — keep waiting out this deadline.
				OS.delay_msec(20)
	return {"ok": false, "reason": "no STUN server answered — outbound UDP may be blocked"}


static var _threads: Array[Thread] = []

static func discover_async(udp: PacketPeerUDP, on_done: Callable) -> void:
	var thread := Thread.new()
	_threads.append(thread)
	thread.start(func() -> void:
		var result := discover(udp)
		on_done.call_deferred(result)
		_join_thread.call_deferred(thread)
	)


static func _join_thread(thread: Thread) -> void:
	thread.wait_to_finish()
	_threads.erase(thread)
