extends Node

## Pure listener, same rule as every UI script in this project: only listens
## to GameState signals, never touches gameplay state. Owns every
## AudioStreamPlayer in the game and decides what to play and when, so
## nothing else needs to know audio exists.

const SFX_HIT: AudioStream = preload("res://assets/audio/sfx_hit.wav")
const SFX_HEAL: AudioStream = preload("res://assets/audio/sfx_heal.wav")
const SFX_LEVELUP: AudioStream = preload("res://assets/audio/sfx_levelup.wav")
const SFX_QUEST_ACCEPT: AudioStream = preload("res://assets/audio/sfx_quest_accept.wav")
const SFX_QUEST_COMPLETE: AudioStream = preload("res://assets/audio/sfx_quest_complete.wav")
const AMBIENT_OUTDOOR: AudioStream = preload("res://assets/audio/ambient_outdoor.wav")
const AMBIENT_DUNGEON: AudioStream = preload("res://assets/audio/ambient_dungeon.wav")

const AMBIENT_FADE_SECONDS := 2.0
const DUNGEON_ZONE_ID := "sundered_crypt"

var _hit_player: AudioStreamPlayer
var _heal_player: AudioStreamPlayer
var _levelup_player: AudioStreamPlayer
var _quest_player: AudioStreamPlayer
var _ambient_outdoor_player: AudioStreamPlayer
var _ambient_dungeon_player: AudioStreamPlayer
var _last_quest_name := ""
var _ambient_tween: Tween

func _ready() -> void:
	_hit_player = _make_sfx_player(SFX_HIT, -6.0)
	_heal_player = _make_sfx_player(SFX_HEAL, -4.0)
	_levelup_player = _make_sfx_player(SFX_LEVELUP, -2.0)
	_quest_player = _make_sfx_player(SFX_QUEST_ACCEPT, -3.0)
	_ambient_outdoor_player = _make_ambient_player(AMBIENT_OUTDOOR)
	_ambient_dungeon_player = _make_ambient_player(AMBIENT_DUNGEON)
	_ambient_outdoor_player.volume_db = -8.0
	_ambient_dungeon_player.volume_db = -80.0
	_ambient_outdoor_player.play()
	_ambient_dungeon_player.play()

	GameState.damage_dealt.connect(_on_damage_dealt)
	GameState.character_leveled_up.connect(_on_leveled_up)
	GameState.quest_changed.connect(_on_quest_changed)
	GameState.zone_changed.connect(_on_zone_changed)

func _make_sfx_player(stream: AudioStream, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	return player

func _make_ambient_player(stream: AudioStream) -> AudioStreamPlayer:
	# Looping is set on the loaded resource instance rather than relying on
	# per-asset import config (no editor GUI available in this environment
	# to configure it), so every ambient WAV just loops forward from a
	# fresh load regardless of how it was imported.
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	return player

func _on_damage_dealt(_position: Vector2, _amount: int, is_heal: bool) -> void:
	if is_heal:
		_heal_player.play()
	else:
		_hit_player.play()

func _on_leveled_up(_level: int) -> void:
	_levelup_player.play()

## quest_name is "" whenever there's no active quest — that's the signal's
## own encoding for "turned in" (see GameState.quest_changed). A non-empty
## name that's different from what we last saw is a fresh accept.
func _on_quest_changed(quest_name: String, _progress: int, _count: int) -> void:
	if quest_name == "" and _last_quest_name != "":
		_quest_player.stream = SFX_QUEST_COMPLETE
		_quest_player.play()
	elif quest_name != "" and quest_name != _last_quest_name:
		_quest_player.stream = SFX_QUEST_ACCEPT
		_quest_player.play()
	_last_quest_name = quest_name

## Crossfades between the outdoor and dungeon ambient beds rather than
## hard-cutting, so a zone transition doesn't feel like a jump cut.
func _on_zone_changed(zone_id: String) -> void:
	var entering_dungeon := zone_id == DUNGEON_ZONE_ID
	if _ambient_tween:
		_ambient_tween.kill()
	_ambient_tween = create_tween().set_parallel(true)
	_ambient_tween.tween_property(_ambient_outdoor_player, "volume_db", -80.0 if entering_dungeon else -8.0, AMBIENT_FADE_SECONDS)
	_ambient_tween.tween_property(_ambient_dungeon_player, "volume_db", -8.0 if entering_dungeon else -80.0, AMBIENT_FADE_SECONDS)
