extends StaticBody2D

@export var max_hp: int = 40
@export var regen_rate: float = 8.0       # HP restored per second once regen kicks in
@export var regen_delay: float = 1.5      # seconds since the last hit before regen starts
@export var contact_damage: int = 0       # 0 = no damage on contact (non-spiky variant)

const CONTACT_TICK_INTERVAL: float = 0.5

var hp: float
var _time_since_last_hit: float = 0.0
var _contact_tick_timer: float = 0.0
var original_color: Color
var _flash_material: ShaderMaterial = null

func _ready():
	if GameData.is_removed(get_tree().current_scene.scene_file_path, name):
		queue_free()
		return
	# Only the spiky variant (contact_damage > 0) ever actually becomes the
	# attacker in a take_damage() call, but tagging the whole class is
	# harmless — Ant Queen's death reward halves damage from this group.
	add_to_group("hazards")
	hp = max_hp
	original_color = $ColorRect.color
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		_flash_material = ShaderMaterial.new()
		_flash_material.shader = preload("res://hit_flash.gdshader")
		sprite.material = _flash_material

func _process(delta: float) -> void:
	_time_since_last_hit += delta
	if _time_since_last_hit >= regen_delay and hp < max_hp:
		hp = min(hp + regen_rate * delta, max_hp)

	if contact_damage > 0 and has_node("ContactArea"):
		_contact_tick_timer -= delta
		if _contact_tick_timer <= 0.0:
			for body in $ContactArea.get_overlapping_bodies():
				if body.is_in_group("player") and body.has_method("take_damage"):
					body.take_damage(contact_damage, false, self, "")
					_contact_tick_timer = CONTACT_TICK_INTERVAL
					break

func on_elemental_hit(_element: String, hit_direction: int, damage: int, attacker: Node = null) -> void:
	on_hit(hit_direction, damage, true, attacker)

# Which weapons/damage types can actually hurt this gate — sword, spear, and
# chain claw only; hammer, fist, and any elemental/magic hit bounce off
# harmlessly. Overridable, not hardcoded here, so a subclass (rock_gate.gd)
# can swap in its own entirely different rule (warhammer-only) instead of
# stacking on top of this one — a plain warhammer-only gate would otherwise
# get rejected twice: once by rock_gate's own check, then again by this
# base rule (warhammer isn't in the sword/spear/chain_claw list either).
func _is_valid_hit(is_magic: bool) -> bool:
	if is_magic:
		return false
	return GameData.current_weapon in ["sword", "spear", "chain_claw"]

func on_hit(hit_direction: int, damage: int, is_magic: bool = false, _attacker: Node = null) -> void:
	if hp <= 0:
		return
	if not _is_valid_hit(is_magic):
		return
	hp -= damage
	GameData.spawn_damage_number(damage, global_position)
	_time_since_last_hit = 0.0
	if hp <= 0:
		GameData.mark_removed(get_tree().current_scene.scene_file_path, name)
		queue_free()
		return
	if _flash_material != null:
		_flash_material.set_shader_parameter("flash_amount", 1.0)
	else:
		$ColorRect.color = Color.RED
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(self):
		if _flash_material != null:
			_flash_material.set_shader_parameter("flash_amount", 0.0)
		else:
			$ColorRect.color = original_color
