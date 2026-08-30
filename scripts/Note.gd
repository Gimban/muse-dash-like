class_name Note
extends Node2D

## Note object representing a single beat-bound target in the 2-channel rhythm game.
## Deterministically calculates its X position using current beat vs target beat.
## Supports both normal and hold notes, including dynamic debug body rendering.

signal note_missed(note: Note)
signal hold_tick(note: Note)

@export var target_beat: float = 0.0 ## The beat at which this note should align perfectly with the judgment line
@export_enum("Air", "Ground") var lane: String = "Ground" ## Lane designation: Air (Top, F Key) or Ground (Bottom, J Key)
@export var note_type: String = "Normal" ## Extension slot: "Normal", "Hold", etc.

# Hold Note properties
var is_hold: bool = false
var duration_beats: float = 0.0
var hold_state: String = "None" ## "None", "Holding", "Completed", "Missed"

var spawn_x: float = 1280.0 ## Spawn position on screen (Right edge)
var target_x: float = 200.0 ## Hit target position on screen (Left edge)
var scroll_speed_beats: float = 4.0 ## Number of beats it takes to travel from spawn_x to target_x

var active: bool = true
var hit_state: String = "None" ## "None", "Perfect", "Great", "Miss"
var last_current_beat: float = 0.0 ## 최근 전달받은 오디오 비트 위치 기록
var game_manager: Node = null

func _ready() -> void:
	# 부모 노드를 탐색하여 GameManager 및 RhythmSync 참조를 자동으로 획득
	var parent = get_parent()
	while parent:
		if parent.has_method("load_chart_from_file"): # GameManager 판별
			game_manager = parent
			break
		parent = parent.get_parent()

func _process(_delta: float) -> void:
	# 비활성 상태이면서 Missed 상태도 아니라면 프로세스 스킵
	if not active and hold_state != "Missed":
		return
		
	# GameManager의 싱크 상태를 읽어 독립적으로 화면 갱신 수행
	if game_manager and game_manager.rhythm_sync and game_manager.rhythm_sync.is_active:
		var current_beat = game_manager.rhythm_sync.get_current_beat()
		update_position(current_beat)

## Update the note position based on the current song beat.
## This uses a deterministic calculation to prevent stuttering/frame-rate dependency.
func update_position(current_beat: float) -> void:
	if not active and hold_state != "Missed":
		return
		
	last_current_beat = current_beat
	
	var beats_left = target_beat - current_beat
	var progress = 1.0 - (beats_left / scroll_speed_beats)
	var display_progress = maxf(0.0, progress)
	
	# Holding 상태일 때는 머리를 판정선 X에 강제 고정
	if is_hold and hold_state == "Holding":
		position.x = target_x
	else:
		# 일반 스크롤 중이거나 Missed 상태인 경우 꼬리 끝까지 계속 좌측으로 이동
		position.x = lerp(spawn_x, target_x, display_progress)
	
	if is_hold:
		queue_redraw() # Refreshes hold bar rendering
		
		# Send a signal to add continuous holding scores (ticks)
		if hold_state == "Holding":
			hold_tick.emit(self)
			
			# If current playback crossed end of hold note, auto complete
			var end_beat = target_beat + duration_beats
			if current_beat >= end_beat:
				complete_hold()
				
		# Miss threshold if head is not pressed on time
		elif hold_state == "None" and current_beat > target_beat + 0.35:
			trigger_hold_miss()
			
		elif hold_state == "Missed":
			# Missed 상태에서는 꼬리 끝이 판정선을 지나서 화면 왼쪽 밖으로 나갈 때까지 대기 후 삭제
			var end_beat = target_beat + duration_beats
			if current_beat > end_beat + 0.35:
				queue_free()
	else:
		# Miss Threshold for normal notes
		if current_beat > target_beat + 0.35 and hit_state == "None":
			trigger_miss()

func trigger_miss() -> void:
	hit_state = "Miss"
	active = false
	note_missed.emit(self)
	queue_free()

func trigger_hold_miss() -> void:
	hold_state = "Missed"
	hit_state = "Miss"
	active = false # 판정 대기 큐에서 즉시 배제하기 위해 false 설정
	note_missed.emit(self)
	# queue_free()를 즉시 하지 않고, update_position 내에서 꼬리가 통과할 때까지 스크롤 지속시킴

## Mark note as hit by the manager, saving judgment state
func trigger_hit(judgment: String) -> void:
	hit_state = judgment
	if is_hold:
		if judgment != "Miss":
			hold_state = "Holding"
		else:
			trigger_hold_miss()
	else:
		active = false
		queue_free()

## Completes hold tracking successfully
func complete_hold() -> void:
	hold_state = "Completed"
	active = false
	queue_free()

## Evaluates the note's tail release when user releases keyboard keys early/late
func evaluate_tail_release(release_beat: float, perfect_win: float, great_win: float) -> String:
	if not is_hold or hold_state != "Holding":
		return "Miss"
		
	var end_beat = target_beat + duration_beats
	
	# 1. Released past the end beat -> Perfect
	if release_beat >= end_beat:
		complete_hold()
		return "Perfect"
		
	# 2. Released early -> evaluate deviation distance
	var diff = end_beat - release_beat
	var judgment = "Miss"
	
	if diff <= perfect_win:
		judgment = "Perfect"
		complete_hold()
	elif diff <= great_win:
		judgment = "Great"
		complete_hold()
	else:
		# Too early -> Break hold and trigger miss
		hold_state = "Missed"
		trigger_hold_miss()
		
	return judgment

func _draw() -> void:
	if not is_hold:
		return
		
	# Compute horizontal width in screen pixels based on beat length
	var pixel_per_beat = (spawn_x - target_x) / scroll_speed_beats
	
	# 머리 판정이 완료되어 Holding 중일 때, 꼬리까지 남은 길이비율만큼만 렌더링되게 만듭니다.
	var remaining_beats = duration_beats
	if hold_state == "Holding":
		remaining_beats = maxf(0.0, (target_beat + duration_beats) - last_current_beat)
		
	var hold_width = remaining_beats * pixel_per_beat
	
	var body_color = Color(1.0, 0.9, 0.3, 0.4) # Semi-translucent yellow
	var border_color = Color(1.0, 0.9, 0.3, 0.8)
	
	if hold_state == "Holding":
		body_color = Color(0.3, 1.0, 0.3, 0.4) # Neon green when holding active
		border_color = Color(0.3, 1.0, 0.3, 0.8)
	elif hold_state == "Missed":
		body_color = Color(0.5, 0.5, 0.5, 0.2) # Grayed out on miss
		border_color = Color(0.5, 0.5, 0.5, 0.4)
		
	# Draw hold body rect aligned around horizontal centerline (thick body)
	draw_rect(Rect2(Vector2(0.0, -15.0), Vector2(hold_width, 30.0)), body_color)
	draw_rect(Rect2(Vector2(0.0, -15.0), Vector2(hold_width, 30.0)), border_color, false, 2.0)
	
	# Draw hold tail vertical cap line
	draw_line(Vector2(hold_width, -15.0), Vector2(hold_width, 15.0), Color.YELLOW, 4.0)
