class_name Player
extends Area2D

## Player controller handling state transitions (GROUND/AIR),
## airtime floating timer, quick diving, and hit events.

signal hit_taken(damage_amount: int)

enum State { GROUND, AIR }

@export var player_x: float = 140.0 ## 캐릭터의 X 축 고정 위치 (판정선 왼쪽 근처)
@export var ground_y: float = 450.0
@export var air_y: float = 200.0
@export var air_duration: float = 0.35

var current_state: State = State.GROUND
var air_timer: float = 0.0

func _ready() -> void:
	# Set initial position
	position.x = player_x
	position.y = ground_y
	monitoring = true
	monitorable = true

func _process(delta: float) -> void:
	if current_state == State.AIR:
		air_timer -= delta
		if air_timer <= 0.0:
			dive()

## Transitions player to AIR state and sets float timer
func jump() -> void:
	current_state = State.AIR
	position.y = air_y
	air_timer = air_duration
	print("Player: AIR 상태 전이 (공중 체류)")

## Transitions player back to GROUND state (landing/diving)
func dive() -> void:
	current_state = State.GROUND
	position.y = ground_y
	air_timer = 0.0
	print("Player: GROUND 상태 전이 (착지/강하)")

## Called when an obstacle collides with the player
func take_damage(amount: int = 1) -> void:
	hit_taken.emit(amount)
	print("Player: 피격! 데미지 누적: %d" % amount)
