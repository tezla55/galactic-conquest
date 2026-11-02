class_name GcUiSfx
extends Node

## Three one-shot UI cues (`sound/swbf2_ui_sfx_wav/`, from the game's own UI sound bank) —
## confirm (committing an action: Move, Buy fleet, Play in KYBER, starting a campaign…),
## cancel/back (Cancel, **End turn**, Back, closing a modal, Abandon — End turn closes the
## player's phase rather than committing to a further action, so it reads closer to
## Back/Close than to Move/Buy) and select/move (clicking a planet on the map, stepping
## through a wizard's option list). Each plays on its own AudioStreamPlayer (not positional,
## this is UI) so overlapping clicks don't cut each other off, at `VOLUME_SCALE` rather than
## the raw files' full volume (they're loud next to the rest of the mix). Independent of the
## "Music: On/Off" toggle (`2026-09-18`, reverting the original "mute both together" design —
## live playtest feedback was that turning music off shouldn't also silence UI feedback
## clicks) — if a dedicated SFX mute is ever wanted, it needs its own GcPrefs key rather than
## reusing the music one.

const CONFIRM_PATH := "res://sound/swbf2_ui_sfx_wav/ui_planetzoom.wav"
const CANCEL_PATH := "res://sound/swbf2_ui_sfx_wav/ui_menuBack.wav"
const MOVE_PATH := "res://sound/swbf2_ui_sfx_wav/ui_menuMove.wav"

## The raw files play at full (0 dB) volume by default — too loud next to the rest of the
## mix. 60% of that as a LINEAR amplitude (volume_db is logarithmic, so "60%" isn't -60% of
## anything in dB terms — converted via linear_to_db in _make_player).
const VOLUME_SCALE := 0.6

var _confirm: AudioStreamPlayer
var _cancel: AudioStreamPlayer
var _move: AudioStreamPlayer


func _ready() -> void:
	_confirm = _make_player(CONFIRM_PATH)
	_cancel = _make_player(CANCEL_PATH)
	_move = _make_player(MOVE_PATH)


func _make_player(path: String) -> AudioStreamPlayer:
	var stream: AudioStream = load(path)
	var p := AudioStreamPlayer.new()
	if stream == null:
		push_warning("GcUiSfx: %s missing — that cue stays silent" % path)
	else:
		p.stream = stream
	p.bus = "Master"
	p.volume_db = linear_to_db(VOLUME_SCALE)
	add_child(p)
	return p


func _play(p: AudioStreamPlayer) -> void:
	if p.stream != null:
		p.play()


func confirm() -> void:
	_play(_confirm)


func cancel() -> void:
	_play(_cancel)


func move() -> void:
	_play(_move)
