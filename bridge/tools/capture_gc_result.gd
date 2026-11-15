extends SceneTree

## Headless capture — saves the first gc_result line the plugin sends to
## tests/fixtures/gc_result_sample.json. Prefer the in-app Log panel's
## "Save last result → fixture" button; this is for CI / no-UI.
##
## PowerShell needs the call operator (&) before the quoted exe path:
##   & "C:\...\Godot_v4.7.2-stable_win64_console.exe" --headless --path E:\Godot\gc `
##       --script res://bridge/tools/capture_gc_result.gd
##   append `-- 45702 120` to override [port] [timeout_seconds].

const OUT_PATH := "res://tests/fixtures/gc_result_sample.json"

var _link: KyberLink
var _deadline_ms := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var port := int(args[0]) if args.size() > 0 else KyberLink.DEFAULT_PORT
	var timeout := float(args[1]) if args.size() > 1 else 120.0
	_deadline_ms = Time.get_ticks_msec() + int(timeout * 1000.0)
	_link = KyberLink.new()
	_link.connect_to("127.0.0.1", port)
	print("[capture] waiting for a gc_result on 127.0.0.1:%d …" % port)


func _process(_delta: float) -> bool:
	_link.poll()
	var result := _link.take_result()
	if not result.is_empty():
		var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
		if f == null:
			push_error("[capture] cannot write %s" % OUT_PATH)
			quit(1)
			return true
		f.store_string(JSON.stringify(result) + "\n")
		f.close()
		print("[capture] saved -> %s" % OUT_PATH)
		print(JSON.stringify(result))
		quit(0)
		return true

	if Time.get_ticks_msec() > _deadline_ms:
		push_error("[capture] timed out — was a KYBER round completing?")
		quit(1)
		return true
	return false
