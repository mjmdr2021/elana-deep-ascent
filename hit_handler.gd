extends Node

@onready var _enemy = get_parent()
@onready var _visual = get_parent().get_node_or_null("AnimatedSprite2D")
var _flash_material: ShaderMaterial = null

func _ready() -> void:
	if _visual == null:
		_visual = get_parent().get_node_or_null("ColorRect")
	if _visual != null and not (_visual is ColorRect):
		_flash_material = ShaderMaterial.new()
		_flash_material.shader = preload("res://hit_flash.gdshader")
		_visual.material = _flash_material

# ColorRect uses .color directly; sprites tint via .modulate — same visual
# intent (flash then restore), just the right property for whichever
# placeholder/real-art node this enemy actually has. Used for the persistent
# state tint (frozen-blue / normal), not the momentary hit flash below.
func _set_flash_color(color: Color) -> void:
	if not is_instance_valid(_visual):
		return
	if _visual is ColorRect:
		_visual.color = color
	else:
		_visual.modulate = color

# Momentary full-red overlay on the moment of impact. ColorRect just sets its
# color directly (the outer function's later restore call resets it). Sprites
# use hit_flash.gdshader, which mixes toward red regardless of the underlying
# pixel color (a true overlay, unlike .modulate's multiply) — layered on top
# of whatever persistent modulate tint is already active (e.g. frozen-blue).
func _flash_hit() -> void:
	if not is_instance_valid(_visual):
		return
	if _visual is ColorRect:
		_visual.color = Color.RED
		return
	if _flash_material == null:
		return
	_flash_material.set_shader_parameter("flash_amount", 1.0)
	await get_tree().create_timer(0.15).timeout
	if is_instance_valid(_flash_material):
		_flash_material.set_shader_parameter("flash_amount", 0.0)

func _get_enemy_max_hp() -> float:
	var v = _enemy.get("max_hp")
	if v != null:
		return float(v)
	var v2 = _enemy.get("MAX_HP")
	return float(v2) if v2 != null else 100.0

func _apply_damage(hit_direction: int, damage: int) -> int:
	if _enemy.hp <= 0:
		return 0
	# Generic directional-defense hook — checked against the enemy's facing
	# BEFORE the flinch/recoil line below overwrites it, so an enemy like
	# Shield-bearer sees how it was actually standing when the hit landed.
	# Lets any enemy reduce/block damage by hit direction without
	# hit_handler.gd needing to know about shields specifically.
	if _enemy.has_method("modify_incoming_damage"):
		damage = _enemy.modify_incoming_damage(hit_direction, damage)
		if damage <= 0:
			return 0
	_enemy.direction = -hit_direction
	# Executioner — instakill at ≤15% HP
	if GameData.executioner_chance > 0.0:
		var emax: float = _get_enemy_max_hp()
		if emax > 0 and _enemy.hp <= emax * 0.15 and randf() < GameData.executioner_chance:
			var kill_dmg: int = int(_enemy.hp)
			_enemy.hp = 0
			GameData.spawn_damage_number(kill_dmg, _enemy.global_position, Color(1.0, 0.1, 0.5))
			return kill_dmg
	var effective_defense = float(_enemy.defense) * (1.0 - GameData.armor_penetration)
	var final_damage = GameData.calc_damage(float(damage), effective_defense)
	_enemy.hp -= final_damage
	_enemy.regen_delay_timer = 3.0
	GameData.spawn_damage_number(final_damage, _enemy.global_position)
	return final_damage

func _die() -> void:
	if _enemy.get("immortal"):
		return
	GameData.mark_removed(get_tree().current_scene.scene_file_path, _enemy.name)
	GameData.glint_register_kill()
	GameData.gain_xp(_enemy.xp_reward)
	# Generic death hook — any enemy subclass can implement on_death() to
	# react to its own death (Splitter spawning smaller copies, a future
	# Exploder's AOE burst, etc.) without hit_handler.gd needing to know
	# about any of them specifically.
	if _enemy.has_method("on_death"):
		_enemy.on_death()
	_flash_hit()
	await get_tree().create_timer(0.5).timeout
	_enemy.queue_free()

func _get_element_mult(element: String) -> float:
	match element:
		"fire":
			return float(_enemy.get("fire_resist")) if _enemy.get("fire_resist") != null else 1.0
		"frost":
			return float(_enemy.get("frost_resist")) if _enemy.get("frost_resist") != null else 1.0
		"elec":
			return float(_enemy.get("elec_resist")) if _enemy.get("elec_resist") != null else 1.0
	return 1.0

func on_elemental_hit(element: String, hit_direction: int, damage: int) -> void:
	var mult: float = _get_element_mult(element)
	if mult <= 0.0:
		return
	var scaled_damage: int = max(1, int(round(float(damage) * mult)))
	if _apply_damage(hit_direction, scaled_damage) == 0:
		return
	# Burn (fire hits)
	if element == "fire" and GameData.burn_dmg_mult > 0.0:
		var tick_dmg: int = max(1, int(float(scaled_damage) * GameData.burn_dmg_mult))
		if _enemy.has_method("apply_burn"):
			_enemy.apply_burn(tick_dmg)
	# Freeze (frost hits) — immune timer prevents multi-roll from same bolt
	if element == "frost" and GameData.freeze_chance > 0.0:
		var fi = _enemy.get("freeze_immune_timer")
		if (fi == null or fi <= 0.0) and randf() < GameData.freeze_chance:
			_enemy.is_stunned = true
			_enemy.stun_timer = max(_enemy.stun_timer, 2.0)
			_enemy.velocity = Vector2.ZERO
			_enemy.is_frozen = true
			_enemy.set("freeze_immune_timer", 3.0)
	if _enemy.hp <= 0:
		_die()
		return
	_flash_hit()
	await get_tree().create_timer(0.1).timeout
	_set_flash_color(Color(0.4, 0.75, 1.0) if _enemy.is_frozen else _enemy.original_color)

func on_hit(hit_direction: int, damage: int = 10, is_magic: bool = false) -> void:
	if _apply_damage(hit_direction, damage) == 0:
		return
	# Anger Strikes — bonus % of enemy max HP, Power Herb only
	if GameData.anger_strikes_pct > 0.0 and GameData.active_herb != null and GameData.active_herb.item_id == "herbPower":
		var bonus: int = max(1, int(_get_enemy_max_hp() * GameData.anger_strikes_pct))
		_enemy.hp -= bonus
		GameData.spawn_damage_number(bonus, _enemy.global_position + Vector2(0, -14), Color(0.7, 0.2, 1.0))
	if _enemy.hp <= 0:
		if not is_magic:
			if GameData.weapon_knockback_x != 0.0 or GameData.weapon_knockback_y != 0.0:
				_enemy._pending_knockback = Vector2(hit_direction * GameData.weapon_knockback_x, GameData.weapon_knockback_y)
			if GameData.weapon_has_stun:
				_enemy.is_stunned = true
		_die()
		return
	_flash_hit()
	if is_magic:
		await get_tree().create_timer(0.1).timeout
		_set_flash_color(Color(0.4, 0.75, 1.0) if _enemy.is_frozen else _enemy.original_color)
	else:
		if GameData.weapon_knockback_x != 0.0 or GameData.weapon_knockback_y != 0.0:
			_enemy._pending_knockback = Vector2(hit_direction * GameData.weapon_knockback_x, GameData.weapon_knockback_y)
		_enemy.is_stunned = true
		var stun_indicator = null
		if GameData.weapon_has_stun:
			stun_indicator = GameData.make_stun_indicator()
			_enemy.add_child(stun_indicator)
		await get_tree().create_timer(0.2).timeout
		_set_flash_color(Color(0.4, 0.75, 1.0) if _enemy.is_frozen else _enemy.original_color)
		if GameData.weapon_has_stun:
			if is_instance_valid(_enemy):
				_enemy.velocity.x = 0
			await get_tree().create_timer(GameData.weapon_stun_duration).timeout
			if is_instance_valid(stun_indicator):
				stun_indicator.queue_free()
		if is_instance_valid(_enemy):
			_enemy.is_stunned = false
