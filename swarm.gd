extends Node2D

# Drop one of these in the map instead of placing individual Swarmers by
# hand — spawns a cluster of them scattered around this node's position.
const SWARMER_SCENE = preload("res://swarmer.tscn")

@export var swarm_count: int = 5
@export var spawn_radius: float = 40.0

# Applied to every swarmer this spawns — adjust here once instead of having
# to edit swarmer.tscn itself (which would affect every Swarm group in the
# game) or re-tuning each spawned instance by hand.
@export_group("Swarmer Stats")
@export var max_hp: int = 2
@export var defense: int = 0
@export var speed: float = 45.0
@export var chase_speed: float = 70.0
@export var attack_damage: int = 3
@export var xp_reward: int = 53

func _ready() -> void:
	# Editor-only marker so this node is actually visible/selectable while
	# placing it in the map — _ready() never runs while just editing, only
	# once the game is actually playing, so this only ever hides at runtime.
	$EditorLabel.visible = false
	for i in swarm_count:
		var swarmer = SWARMER_SCENE.instantiate()
		swarmer.max_hp = max_hp
		swarmer.defense = defense
		swarmer.speed = speed
		swarmer.chase_speed = chase_speed
		swarmer.attack_damage = attack_damage
		swarmer.xp_reward = xp_reward
		var angle = randf() * TAU
		var dist = randf() * spawn_radius
		swarmer.position = Vector2(cos(angle), sin(angle)) * dist
		add_child(swarmer)
