class_name RhythmSync
extends Node

## Precise Audio-to-Beat Synchronizer for Godot 4.x.
## This node computes the current song position and translates it into beat units,
## compensating for latency and audio server mixing offsets to prevent sync drift.

signal beat_updated(current_beat: float)

@export var bpm: float = 120.0
@export var offset_sec: float = 0.0 ## Custom calibration offset for audio sync adjustments (in seconds)
@export var audio_player: AudioStreamPlayer

var song_position: float = 0.0 ## Compensated playback position in seconds
var current_beat: float = 0.0 ## Current playback position converted to fractional beats
var is_active: bool = false

func _ready() -> void:
	if not audio_player:
		push_warning("RhythmSync: AudioStreamPlayer is not assigned.")

func _process(_delta: float) -> void:
	if not is_active or not audio_player or not audio_player.playing:
		return
		
	# 1. Get raw playback position from the audio hardware
	var raw_pos = audio_player.get_playback_position()
	
	# 2. Add time elapsed since the audio engine mixed the last buffer block
	# (Prevents staircase-like get_playback_position updates occurring only at buffer mix intervals)
	var mix_offset = AudioServer.get_time_since_last_mix()
	
	# 3. Subtract estimated output latency of the audio device
	var latency = AudioServer.get_output_latency()
	
	# 4. Apply everything, including local offset calibration
	song_position = raw_pos + mix_offset - latency - offset_sec
	
	# 5. Convert playback position in seconds to beats:
	# Beats = seconds * (BPM / 60)
	current_beat = song_position * (bpm / 60.0)
	
	beat_updated.emit(current_beat)

## Start synchronization tracking
func start_sync() -> void:
	is_active = true
	if audio_player and not audio_player.playing:
		audio_player.play()

## Stop synchronization tracking
func stop_sync() -> void:
	is_active = false
	if audio_player and audio_player.playing:
		audio_player.stop()

## Retrieve the current beat position
func get_current_beat() -> float:
	return current_beat
