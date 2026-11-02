class_name GalaxyMusic
extends Node

## Loops sound/galaxy_map_music.wav under the interface: a second player starts the track
## from the top while the first is still playing its tail, and the two are cross-faded with
## an **equal-power** curve (cos/sin, not a linear dB ramp — that dips to near-silence at
## the midpoint and sounds like a gap) so the loop is genuinely seamless. Also ducks to
## silence while a battle is running or the window is unfocused.

const STREAM_PATH := "res://sound/galaxy_map_music.wav"
const XFADE := 4.5           ## seconds the tail and the fresh top play over each other
const DUCK_IN := 0.7          ## seconds to fade the music back up (window focus / battle end)
const DUCK_OUT := 1.8         ## seconds to fade it down (window unfocused / battle start)
const MUSIC_DB := -9.0
const SILENT_DB := -62.0

var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _active: AudioStreamPlayer
var _idle: AudioStreamPlayer
var _len := 0.0
var _xfade_t := -1.0         ## >= 0 while a crossfade is in progress
var _duck := 1.0            ## 1 = full music, ~0 = silent (eased toward _want)
var _want := 1.0            ## target for _duck: 1 play, 0 stop
var _started := false


func _ready() -> void:
	var stream: AudioStream = load(STREAM_PATH)
	if stream == null:
		push_warning("GalaxyMusic: %s missing — no music" % STREAM_PATH)
		set_process(false)
		return
	_len = stream.get_length()
	_a = _make_player(stream)
	_b = _make_player(stream)
	_active = _a
	_idle = _b


func _make_player(s: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = "Master"
	p.volume_db = SILENT_DB
	add_child(p)
	return p


## Begin (or resume) the loop from the top.
func start() -> void:
	if _active == null or _started:
		return
	_started = true
	_want = 1.0
	_duck = 1.0
	_active.play(0.0)


## on = play the interface music; off = fade to silence (battle running / window unfocused).
func set_playing(on: bool) -> void:
	_want = 1.0 if on else 0.0


func _process(delta: float) -> void:
	if _active == null:
		return
	var ramp := DUCK_IN if _want > _duck else DUCK_OUT
	_duck = move_toward(_duck, _want, delta / ramp)

	# Fully faded out → pause both players so nothing decodes during a long match.
	if _duck <= 0.001:
		_active.stream_paused = true
		_idle.stream_paused = true
		return
	_active.stream_paused = false
	_idle.stream_paused = _xfade_t < 0.0

	var active_base := MUSIC_DB
	var idle_base := SILENT_DB

	if _xfade_t < 0.0 and _active.playing and not _active.stream_paused:
		if _len - _active.get_playback_position() <= XFADE:
			_xfade_t = 0.0
			_idle.stream_paused = false
			_idle.play(0.0)

	if _xfade_t >= 0.0:
		_xfade_t += delta
		var k := clampf(_xfade_t / XFADE, 0.0, 1.0)
		# Equal-power: gains sum to constant perceived loudness — no dip at the midpoint.
		active_base = MUSIC_DB + linear_to_db(maxf(cos(k * PI * 0.5), 0.0001))
		idle_base = MUSIC_DB + linear_to_db(maxf(sin(k * PI * 0.5), 0.0001))
		if k >= 1.0:
			_xfade_t = -1.0
			_active.stop()
			var t := _active
			_active = _idle
			_idle = t
			active_base = MUSIC_DB
			idle_base = SILENT_DB

	var duck_db := linear_to_db(maxf(_duck, 0.0001))
	_active.volume_db = active_base + duck_db
	_idle.volume_db = idle_base + duck_db
