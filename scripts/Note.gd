class_name Note
extends Node2D

## Note object representing a single beat-bound target in the 2-channel rhythm game.
## Deterministically calculates its X position using current beat vs target beat.

signal note_missed(note: Note)

@export var target_beat: float = 0.0 ## The beat at which this note should align perfectly with the judgment line
@export_enum("Air", "Ground") var lane: String = "Ground" ## Lane designation: Air (Top, F Key) or Ground (Bottom, J Key)
@export var note_type: String = "Normal" ## Extension slot: "Normal", "Hold", etc.

var spawn_x: float = 1280.0 ## Spawn position on screen (Right edge)
var target_x: float = 200.0 ## Hit target position on screen (Left edge)
var scroll_speed_beats: float = 4.0 ## Number of beats it takes to travel from spawn_x to target_x

var active: bool = true
var hit_state: String = "None" ## "None", "Perfect", "Great", "Miss"

func _ready() -> void:
	# Initialize visual representation or offset adjustments if needed
	pass

## Update the note position based on the current song beat.
## This uses a deterministic calculation to prevent stuttering/frame-rate dependency.
func update_position(current_beat: float) -> void:
	if not active:
		return
		
	# progress reaches 1.0 when current_beat == target_beat
	# progress is 0.0 when current_beat == target_beat - scroll_speed_beats
	var beats_left = target_beat - current_beat
	var progress = 1.0 - (beats_left / scroll_speed_beats)
	
	# Clamp position so notes don't fly off too far to the right before they are supposed to move
	# but allow them to move past the target_x to the left for late hit/miss evaluation
	var display_progress = maxf(0.0, progress)
	position.x = lerp(spawn_x, target_x, display_progress)
	
	# Miss Threshold (e.g., 0.35 beats late)
	# If the current beat has passed the target beat by a certain margin and it hasn't been hit, it's a Miss.
	if current_beat > target_beat + 0.35 and hit_state == "None":
		trigger_miss()

func trigger_miss() -> void:
	hit_state = "Miss"
	active = false
	note_missed.emit(self)
	# Deactivate visual elements or queue_free() from the manager
	queue_free()

## Mark note as hit by the manager, saving judgment state
func trigger_hit(judgment: String) -> void:
	hit_state = judgment
	active = false
	# Play hit animation/particle effects here
	queue_free()
