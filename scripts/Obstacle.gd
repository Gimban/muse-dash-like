class_name Obstacle
extends Area2D

## Obstacle object scrolling deterministically on the timeline.
## Detects collision with Player and inflicts damage based on Player's current height state.

@export var target_beat: float = 0.0
@export_enum("Air", "Ground") var lane: String = "Ground"

var spawn_x: float = 1280.0
var target_x: float = 200.0
var scroll_speed_beats: float = 4.0

var active: bool = true

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	monitoring = true
	monitorable = true
	
	# Fallback visual mockup if no custom graphics are attached
	if get_child_count() == 0:
		var visual = ColorRect.new()
		visual.size = Vector2(50.0, 50.0)
		visual.position = Vector2(-25.0, -25.0)
		if lane == "Air":
			visual.color = Color.PURPLE
		else:
			visual.color = Color.DARK_SLATE_GRAY
		add_child(visual)

## Update position on timeline, same deterministic logic as notes
func update_position(current_beat: float) -> void:
	if not active:
		return
		
	var beats_left = target_beat - current_beat
	var progress = 1.0 - (beats_left / scroll_speed_beats)
	
	var display_progress = maxf(0.0, progress)
	position.x = lerp(spawn_x, target_x, display_progress)
	
	# Self-destroy when passing out of judgment zone
	if current_beat > target_beat + 0.35:
		active = false
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if not active:
		return
		
	if area is Player:
		var hit: bool = false
		
		# Ground Obstacle triggers damage when player is GROUNDED
		if lane == "Ground" and area.current_state == Player.State.GROUND:
			hit = true
		# Air Obstacle triggers damage when player is FLOATING in AIR
		elif lane == "Air" and area.current_state == Player.State.AIR:
			hit = true
			
		if hit:
			active = false
			area.take_damage(1)
			queue_free()
