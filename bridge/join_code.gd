class_name JoinCode
extends RefCounted

## Turns a host's "IPv4 address + port" into a short, typeable code, and back again — the
## thing a host reads out loud (or pastes into chat) and a joiner types into GC's own "Join
## Online Game" screen. This does NOT solve NAT traversal or discovery on its own: it is
## purely a friendlier encoding of an address the joiner still has to be able to reach
## directly (the host forwards a port; see bridge/gc_net.gd's own header for the fuller
## picture and why a direct-connect was chosen over a relay server for the first version).
##
## IPv4 (4 bytes) + port (2 bytes, big-endian) packs into 6 bytes = 48 bits, which Crockford
## base32 (5 bits/symbol, no ambiguous I/L/O/U characters — chosen so a mis-read/mis-typed
## character is either obviously wrong or a bad checksum, never a different-but-plausible
## address) encodes in exactly 10 symbols. Grouped 5+5 with a dash purely for readability
## ("KRSX7-WQ3TN") — the dash carries no data and is stripped on decode.

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"   # Crockford's 32, sans I L O U
const GROUP_SIZE := 5


## "" on a non-IPv4 address (IPv6 isn't supported by this scheme) or an out-of-range port.
static func encode(ipv4: String, port: int) -> String:
	var octets := ipv4.split(".")
	if octets.size() != 4:
		return ""
	var bytes := PackedByteArray()
	for o in octets:
		if not o.is_valid_int():
			return ""
		var v := int(o)
		if v < 0 or v > 255:
			return ""
		bytes.append(v)
	if port < 1 or port > 65535:
		return ""
	bytes.append((port >> 8) & 0xFF)
	bytes.append(port & 0xFF)

	# 6 bytes = 48 bits -> ten 5-bit symbols, most-significant-bit first.
	var bits := 0
	var acc := 0
	var out := ""
	for b in bytes:
		acc = (acc << 8) | b
		bits += 8
		while bits >= 5:
			bits -= 5
			out += ALPHABET[(acc >> bits) & 0x1F]
	if bits > 0:
		out += ALPHABET[(acc << (5 - bits)) & 0x1F]

	var grouped := PackedStringArray()
	var i := 0
	while i < out.length():
		grouped.append(out.substr(i, GROUP_SIZE))
		i += GROUP_SIZE
	return "-".join(grouped)


## {"ok": false} on anything that doesn't decode to a plausible IPv4 + port — a mistyped
## character normally lands outside the alphabet or produces the wrong bit count, not a
## different-but-valid-looking address.
static func decode(code: String) -> Dictionary:
	var cleaned := code.strip_edges().to_upper().replace("-", "").replace(" ", "")
	if cleaned.length() != 10:
		return {"ok": false}

	var acc := 0
	var bits := 0
	var bytes := PackedByteArray()
	for c in cleaned:
		var v := ALPHABET.find(c)
		if v == -1:
			return {"ok": false}
		acc = (acc << 5) | v
		bits += 5
		if bits >= 8:
			bits -= 8
			bytes.append((acc >> bits) & 0xFF)
	if bytes.size() != 6:
		return {"ok": false}

	var ip := "%d.%d.%d.%d" % [bytes[0], bytes[1], bytes[2], bytes[3]]
	var port := (bytes[4] << 8) | bytes[5]
	if port < 1:
		return {"ok": false}
	return {"ok": true, "ip": ip, "port": port}
