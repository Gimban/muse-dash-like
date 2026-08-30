class_name GameManager
extends Node2D

## Central Manager for the 2-channel Action Rhythm Game.
## Handles game states, JSON chart parsing, spawning notes, input detection, and judgments.

@export var note_scene: PackedScene ## Note.tscn PackedScene template
@export var spawn_distance_beats: float = 4.0 ## Spawn notes this many beats before they reach judgment line
@export var judgment_line_x: float = 200.0
@export var note_spawn_x: float = 1280.0
@export var chart_file_path: String = "res://test_chart.json" ## 외부 JSON 채보 파일 경로
@export var obstacle_scene: PackedScene ## Obstacle.tscn PackedScene template
@export var player: Player ## 씬 상의 Player 노드 참조

# Judgment Windows in Beat units (at 120BPM, 0.1 beat is 50ms)
@export var perfect_window: float = 0.12  ## Max beat difference for Perfect (0.08 -> 0.12)
@export var great_window: float = 0.24    ## Max beat difference for Great (0.18 -> 0.24)
@export var miss_window: float = 0.35     ## Max beat difference for Miss (0.30 -> 0.35)
@export var hit_sound_player: AudioStreamPlayer ## 노트를 맞췄을 때 재생할 타격음 플레이어

@onready var rhythm_sync: RhythmSync = $RhythmSync

# Game States
var score: int = 0
var combo: int = 0
var max_combo: int = 0
var perfect_count: int = 0
var great_count: int = 0
var miss_count: int = 0

# Note Queues
var chart_data: Dictionary = {}
var pending_notes: Array = [] ## Notes loaded from JSON, waiting to be spawned: Array of Dictionaries
var active_air_notes: Array[Note] = [] ## Currently moving air notes
var active_ground_notes: Array[Note] = [] ## Currently moving ground notes
var active_obstacles: Array[Obstacle] = [] ## Currently moving obstacles

func _ready() -> void:
	# Check configuration
	if not rhythm_sync:
		push_error("GameManager: RhythmSync child node not found.")
		return
		
	# Connect to RhythmSync beat update signal
	rhythm_sync.beat_updated.connect(_on_beat_updated)
	
	# Player 피격 시그널 연결
	if player:
		player.hit_taken.connect(_on_player_hit_taken)
	else:
		push_warning("GameManager: Player 노드가 지정되지 않았습니다.")
	
	# 외부 JSON 파일 로드 시도, 실패 시 내장 뼈대 채보 로드
	var loaded_chart = load_chart_from_file(chart_file_path)
	if loaded_chart.is_empty():
		push_warning("GameManager: 외부 채보 로드 실패. 내장 뼈대 채보를 로드합니다.")
		loaded_chart = load_chart_skeleton()
		
	init_game(loaded_chart)
	queue_redraw() ## 화면에 판정선 그리기 요청

## Initializes the game with parsed chart data
func init_game(chart: Dictionary) -> void:
	chart_data = chart
	
	if chart.has("bpm"):
		rhythm_sync.bpm = chart["bpm"]
	if chart.has("offset"):
		rhythm_sync.offset_sec = chart["offset"]
		
	# Load notes and sort them by target beat ascending
	pending_notes = chart.get("notes", [])
	pending_notes.sort_custom(func(a, b): return a["beat"] < b["beat"])
	
	score = 0
	combo = 0
	max_combo = 0
	perfect_count = 0
	great_count = 0
	miss_count = 0
	
	active_air_notes.clear()
	active_ground_notes.clear()
	active_obstacles.clear()
	
	rhythm_sync.start_sync()

## Triggered on every beat update from RhythmSync
func _on_beat_updated(current_beat: float) -> void:
	# 1. Spawn notes that are within the scroll range
	while pending_notes.size() > 0:
		var next_note_data = pending_notes[0]
		# Spawn if current beat has crossed: target_beat - spawn_distance_beats
		if current_beat >= next_note_data["beat"] - spawn_distance_beats:
			spawn_note(next_note_data)
			pending_notes.pop_front()
		else:
			break
			
	# 2. Update active obstacles' positions & clean up invalid/inactive notes from queue
	# 큐에서 제거될 공중 롱노트가 있는 경우 플레이어를 즉시 땅에 착지시킵니다.
	for note in active_air_notes:
		if not is_instance_valid(note) or not note.active:
			if is_instance_valid(note) and note.is_hold:
				if player and player.current_state == Player.State.AIR:
					player.dive()
					
	active_air_notes = active_air_notes.filter(func(note): return is_instance_valid(note) and note.active)
	active_ground_notes = active_ground_notes.filter(func(note): return is_instance_valid(note) and note.active)
			
	for obstacle in active_obstacles.duplicate():
		if is_instance_valid(obstacle):
			obstacle.update_position(current_beat)

## Spawns a Note node and adds it to the appropriate lane queue
func spawn_note(note_data: Dictionary) -> void:
	# 장애물 데이터인 경우 별도 함수로 위임
	if note_data.get("type", "") == "Obstacle":
		spawn_obstacle(note_data)
		return
		
	var note_instance: Note
	
	if note_scene:
		note_instance = note_scene.instantiate() as Note
	else:
		# Fallback fallback mock note if packed scene is not assigned (avoids engine crashes)
		note_instance = Note.new()
		var visual_mock = ColorRect.new()
		visual_mock.size = Vector2(60, 60)
		visual_mock.position = Vector2(-30, -30)
		if note_data.get("lane", "Ground") == "Air":
			visual_mock.color = Color.DEEP_SKY_BLUE
		else:
			visual_mock.color = Color.ORANGE_RED
		note_instance.add_child(visual_mock)
		
	# Configure note properties
	note_instance.target_beat = note_data.get("beat", 0.0)
	note_instance.lane = note_data.get("lane", "Ground")
	note_instance.note_type = note_data.get("type", "Normal")
	note_instance.target_x = judgment_line_x
	note_instance.spawn_x = note_spawn_x
	note_instance.scroll_speed_beats = spawn_distance_beats
	
	# 롱 노트(Hold) 속성 설정 및 콜백 연결
	if note_instance.note_type == "Hold":
		note_instance.is_hold = true
		note_instance.duration_beats = note_data.get("duration", 1.0)
		note_instance.hold_tick.connect(_on_hold_tick)
	
	# Setup visual vertical offset based on Lane
	# (Assuming Air lane is Y=200, Ground lane is Y=450 on screen)
	if note_instance.lane == "Air":
		note_instance.position.y = 200.0
		active_air_notes.append(note_instance)
	else:
		note_instance.position.y = 450.0
		active_ground_notes.append(note_instance)
		
	# Listen to the miss signal
	note_instance.note_missed.connect(_on_note_missed)
	
	# 최초 프레임에 화면 좌측(0,0)에 깜빡거리며 스폰되는 현상을 막기 위해 초기 위치 선보정
	note_instance.position.x = note_spawn_x
	if rhythm_sync and rhythm_sync.is_active:
		note_instance.update_position(rhythm_sync.get_current_beat())
	
	# Add to main scene container (or GameManager child)
	add_child(note_instance)

## Standard Input parsing for rhythm action keys (F key = Air, J key = Ground)
func _input(event: InputEvent) -> void:
	if not rhythm_sync.is_active:
		return
		
	# --- KEY PRESS ---
	if event.is_action_pressed("hit_air") or (event is InputEventKey and event.pressed and event.keycode == KEY_F and not event.echo):
		if player:
			player.jump() # 공중 상태 전환
		process_judgment("Air")
	elif event.is_action_pressed("hit_ground") or (event is InputEventKey and event.pressed and event.keycode == KEY_J and not event.echo):
		if player and player.current_state == Player.State.AIR:
			player.dive() # 공중 체류 중 J 누르면 즉시 지상 강하
		process_judgment("Ground")
		
	# --- KEY RELEASE ---
	if event.is_action_released("hit_air") or (event is InputEventKey and not event.pressed and event.keycode == KEY_F):
		process_hold_release("Air")
	elif event.is_action_released("hit_ground") or (event is InputEventKey and not event.pressed and event.keycode == KEY_J):
		process_hold_release("Ground")

## Evaluates hits against active notes in the specified lane
func process_judgment(lane_type: String) -> void:
	var current_beat = rhythm_sync.get_current_beat()
	var target_list = active_air_notes if lane_type == "Air" else active_ground_notes
	
	if target_list.is_empty():
		return # No notes to hit on this lane
		
	# Grab the earliest note in the queue
	var target_note = target_list[0]
	if not is_instance_valid(target_note) or not target_note.active:
		return
		
	var diff_raw = target_note.target_beat - current_beat
	var diff = abs(diff_raw)
	
	# Verify if the note is close enough for a valid judgment
	if diff <= miss_window:
		var judgment = "Miss"
		var timing_info = ""
		
		if diff <= perfect_window:
			judgment = "Perfect"
		elif diff <= great_window:
			judgment = "Great"
		else:
			judgment = "Miss"
			
		# Early / Late 판단 (Perfect나 Great 판정일 때 판단)
		if judgment != "Miss":
			if diff_raw > 0.015:
				timing_info = " (Early)"
			elif diff_raw < -0.015:
				timing_info = " (Late)"
			else:
				timing_info = " (Just)"
				
		var points = 100 if judgment == "Perfect" else (50 if judgment == "Great" else 0)
		add_score(points, judgment, timing_info)
		
		# 타격음 재생 및 화면에 판정 텍스트 피드백 표시
		if judgment != "Miss":
			play_hit_sound()
		show_judgment_text(judgment, lane_type)
		
		# 일반 노트이거나 Miss 판정인 경우에는 즉시 대기 큐에서 제거
		# Holding 상태로 돌입한 롱 노드는 키를 뗐을 때(process_hold_release) 또는 완주 시 제거하도록 유지
		if not target_note.is_hold or judgment == "Miss":
			target_list.pop_front()
			
		target_note.trigger_hit(judgment)
	else:
		# Too early (outside judgment window entirely), ignore
		pass

func add_score(points: int, judgment: String, timing_info: String = "") -> void:
	if judgment == "Perfect":
		perfect_count += 1
		combo += 1
	elif judgment == "Great":
		great_count += 1
		combo += 1
	else: # Miss
		miss_count += 1
		combo = 0
		
	score += points * (1 + int(combo / 10.0)) # Mini combo multiplier example
	if combo > max_combo:
		max_combo = combo
		
	print("Hit! Score: %d | Combo: %d | Judgment: %s%s" % [score, combo, judgment, timing_info])

func _on_note_missed(note: Note) -> void:
	# Remove the note from the corresponding queue if it was still inside
	if note.lane == "Air":
		active_air_notes.erase(note)
	else:
		active_ground_notes.erase(note)
		
	combo = 0
	miss_count += 1
	print("Missed note! Combo Reset. Total Misses: %d" % miss_count)

## 디스크(res://)에서 외부 JSON 채보 파일을 로드하는 함수
func load_chart_from_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("GameManager: 채보 파일이 존재하지 않습니다: %s" % path)
		return {}
		
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("GameManager: 채보 파일을 열 수 없습니다: %s" % path)
		return {}
		
	var content = file.get_as_text()
	file.close()
	
	var data = JSON.parse_string(content)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("GameManager: 채보 파일 형식이 올바르지 않습니다 (Dictionary 필요). Path: %s" % path)
		return {}
		
	print("GameManager: 성공적으로 채보를 로드했습니다. 노드 개수: %d" % data.get("notes", []).size())
	return data

## SKELETON: Mock loader representing how a JSON chart file gets parsed
func load_chart_skeleton() -> Dictionary:
	var mock_json = """
	{
		"bpm": 130.0,
		"offset": 0.0,
		"notes": [
			{"beat": 4.0, "lane": "Ground", "type": "Normal"},
			{"beat": 6.0, "lane": "Air", "type": "Normal"},
			{"beat": 8.0, "lane": "Ground", "type": "Normal"},
			{"beat": 10.0, "lane": "Ground", "type": "Normal"},
			{"beat": 12.0, "lane": "Air", "type": "Normal"},
			{"beat": 14.0, "lane": "Ground", "type": "Normal"},
			{"beat": 14.5, "lane": "Air", "type": "Normal"},
			{"beat": 15.0, "lane": "Ground", "type": "Normal"}
		]
	}
	"""
	# Parse JSON string using Godot 4 JSON helper
	var dict = JSON.parse_string(mock_json)
	if dict == null:
		push_error("Failed to parse mock JSON.")
		return {}
	return dict

## Godot 2D Canvas를 이용하여 판정선과 레인 타겟을 화면에 실시간으로 그립니다.
func _draw() -> void:
	# 1. 수직 판정선 그리기 (X = judgment_line_x)
	var line_color = Color(1.0, 1.0, 1.0, 0.3) # 반투명한 흰색 선
	var line_width = 3.0
	# 화면 Y축 전체 범위에 걸쳐 세로선 렌더링
	draw_line(Vector2(judgment_line_x, 0.0), Vector2(judgment_line_x, 720.0), line_color, line_width)
	
	# 2. Air 라인 판정 서클 (Y = 200.0) - 크기를 40.0으로 키움
	var air_target_center = Vector2(judgment_line_x, 200.0)
	draw_arc(air_target_center, 40.0, 0.0, TAU, 32, Color.DEEP_SKY_BLUE, 3.0) # 빈 원
	draw_circle(air_target_center, 8.0, Color.DEEP_SKY_BLUE)                 # 중심점
	
	# 3. Ground 라인 판정 서클 (Y = 450.0) - 크기를 40.0으로 키움
	var ground_target_center = Vector2(judgment_line_x, 450.0)
	draw_arc(ground_target_center, 40.0, 0.0, TAU, 32, Color.ORANGE_RED, 3.0) # 빈 원
	draw_circle(ground_target_center, 8.0, Color.ORANGE_RED)                  # 중심점

## 화면에 판정 피드백 텍스트(Tween 애니메이션)를 띄웁니다.
func show_judgment_text(judgment: String, lane: String) -> void:
	var label = Label.new()
	label.text = judgment
	
	# 판정별 고유 색상 설정
	var color = Color.WHITE
	match judgment:
		"Perfect": color = Color.GOLD
		"Great": color = Color.GREEN_YELLOW
		"Miss": color = Color.RED
		
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 32) # 가시성 있게 크기 지정
	
	# 판정 링 위쪽에 텍스트 위치 선정
	var target_y = 120.0 if lane == "Air" else 370.0
	label.position = Vector2(judgment_line_x - 60.0, target_y)
	
	add_child(label)
	
	# Tween 애니메이션: 0.4초 동안 30픽셀 부드럽게 상승하며 투명해지고 소멸
	var tween = create_tween()
	tween.tween_property(label, "position:y", target_y - 30.0, 0.4)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(label.queue_free)

## 타격 시 오디오 효과음을 재생합니다.
func play_hit_sound() -> void:
	if hit_sound_player:
		hit_sound_player.play()

## 장애물 인스턴스 스폰 및 큐 등록
func spawn_obstacle(data: Dictionary) -> void:
	var obstacle_instance: Obstacle
	if obstacle_scene:
		obstacle_instance = obstacle_scene.instantiate() as Obstacle
	else:
		# Fallback mock obstacle
		obstacle_instance = Obstacle.new()
		
	obstacle_instance.target_beat = data.get("beat", 0.0)
	obstacle_instance.lane = data.get("lane", "Ground")
	obstacle_instance.target_x = judgment_line_x
	obstacle_instance.spawn_x = note_spawn_x
	obstacle_instance.scroll_speed_beats = spawn_distance_beats
	
	if obstacle_instance.lane == "Air":
		obstacle_instance.position.y = 200.0
	else:
		obstacle_instance.position.y = 450.0
		
	active_obstacles.append(obstacle_instance)
	
	# 최초 프레임에 화면 좌측(0,0)에 깜빡거리며 스폰되는 현상을 막기 위해 초기 위치 선보정
	obstacle_instance.position.x = note_spawn_x
	if rhythm_sync and rhythm_sync.is_active:
		obstacle_instance.update_position(rhythm_sync.get_current_beat())
		
	add_child(obstacle_instance)
	print("GameManager: Obstacle 스폰 (Lane: %s, Beat: %.1f)" % [obstacle_instance.lane, obstacle_instance.target_beat])

## 롱 노트의 꼬리 릴리즈 판정 처리
func process_hold_release(lane_type: String) -> void:
	var target_list = active_air_notes if lane_type == "Air" else active_ground_notes
	if target_list.is_empty():
		return
		
	var active_note = target_list[0]
	if is_instance_valid(active_note) and active_note.is_hold and active_note.hold_state == "Holding":
		var current_beat = rhythm_sync.get_current_beat()
		var judgment = active_note.evaluate_tail_release(current_beat, perfect_window, great_window)
		
		# 꼬리 릴리즈 결과 반영
		if judgment == "Perfect":
			add_score(50, "Hold End", " (Perfect)") # 꼬리 성공 보너스 점수
			play_hit_sound()
		elif judgment == "Great":
			add_score(25, "Hold End", " (Great)")
			play_hit_sound()
		else:
			combo = 0
			miss_count += 1
			print("GameManager: Hold 조기 떼기 Miss!")
			show_judgment_text("Miss", lane_type)
			
		target_list.pop_front()

## Hold 노트를 유지하는 동안 지속적인 Tick 보상 가산
func _on_hold_tick(note: Note) -> void:
	score += 1
	# 공중 롱노트를 정상적으로 누르고 있는 동안에는 플레이어가 땅으로 떨어지지 않고 계속 공중에 체류하도록 타이머 리셋
	if note.lane == "Air" and player and player.current_state == Player.State.AIR:
		player.air_timer = player.air_duration

## 플레이어가 장애물에 충돌했을 때 호출되는 콜백
func _on_player_hit_taken(damage: int) -> void:
	combo = 0
	miss_count += 1
	score = max(0, score - 50) # 피격 시 감점
	print("GameManager: 플레이어 피격 감지! 콤보 리셋 및 감점 (-50)")
	show_judgment_text("HIT!", "Air" if player.current_state == Player.State.AIR else "Ground")
