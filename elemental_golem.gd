extends "res://enemy.gd"

# Mini-boss — Elemental Golem. Bigger/tougher than the single-element golems
# (Crystal Golem, Lava Golem), with 4 distinct special attacks instead of
# their single ranged fallback. Ordinary melee (inherited AttackZone/
# attack_damage cycle, overridden below only to hook Shock Coat's punch-
# shock) applies whenever Elana's in melee range, same as any other enemy —
# the 4 specials below only trigger while she's aggro'd (target != null) but
# OUT of melee reach, in a fixed repeating sequence (not random-picked like
# Hollowfang/Elemander):
#   Ground Slam -> Shock Coat -> Overheat -> Winter Slumber -> Overheat ->
#   Shock Coat -> repeat
# On death: permanent +10% all-element resist to Elana (GameData.
# elemental_golem_defeated / ELEMENTAL_GOLEM_RESIST_BONUS, see GameData.gd
# and get_elemental_resist_for()).

const EARTH_MOUND_SCENE = preload("res://elemental_golem_earth_mound.tscn")

@export_group("Ground Slam")
@export var ground_slam_windup: float = 0.6
@export var ground_slam_camera_shake: float = 0.6
@export var earth_mound_count: int = 5
@export var earth_mound_spacing: float = 26.0
# Overlapping ripple, not strictly sequential — each mound starts this long
# after the PREVIOUS ONE STARTED (not after it finishes), so by the time
# mound 2 spawns, mound 1 (0.5s own rise+hold+recede cycle) is still up —
# user's explicit choice, reads as a continuous wave rather than a slower
# one-at-a-time step pattern.
@export var earth_mound_stagger: float = 0.15

@export_group("Shock Coat")
@export var shock_coat_charge_time: float = 1.0
@export var shock_coat_duration: float = 9.0  # 8-10s window, mid-picked

@export_group("Overheat")
@export var overheat_telegraph_time: float = 2.0
@export var overheat_blast_damage: int = 25
@export var overheat_burn_damage: int = 4
@export var overheat_burn_ticks: int = 2  # apply_player_burn ticks 1/sec — 2 ticks = burns for 2s
@export var overheat_camera_shake: float = 0.7
@export var overheat_flash_fade_time: float = 0.4
@export var overheat_knockback_x: float = 100.0
@export var overheat_knockup: float = -150.0

@export_group("Winter Slumber")
@export var winter_slumber_duration: float = 5.0
@export var winter_slumber_heal_pct_per_sec: float = 0.05
@export var winter_slumber_slow_factor: float = 0.5

const TINT_GROUND_SLAM: Color = Color(0.55, 0.4, 0.25, 1.0)
const TINT_SHOCK_COAT: Color = Color(1.0, 0.95, 0.3, 1.0)
const TINT_OVERHEAT: Color = Color(1.0, 0.35, 0.15, 1.0)
const TINT_WINTER_SLUMBER: Color = Color(0.5, 0.8, 1.0, 1.0)

# Fixed rotation, not a random pool — see this file's header comment.
# 1=Ground Slam, 2=Shock Coat, 3=Overheat, 4=Winter Slumber.
# Fixed rotation, not a random pool — see this file's header comment.
# 1=Ground Slam, 2=Shock Coat, 3=Overheat, 4=Winter Slumber.
const ATTACK_SEQUENCE: Array[int] = [1, 2, 3, 4, 3, 2]
# Gap between one special finishing and the next becoming eligible to
# start — keeps her from chaining them with zero breathing room.
const SPECIAL_COOLDOWN_GAP: float = 1.5

var _sequence_pos: int = 0
var _is_using_special: bool = false
var _special_cooldown_timer: float = 0.0
var _shock_coat_active: bool = false
var _shock_coat_timer: float = 0.0
var _base_modulate: Color

@onready var _overheat_zone: Area2D = $OverheatBlastZone
@onready var _slumber_aura: Area2D = $SlumberAura
@onready var _overheat_flash: Sprite2D = $OverheatExplosionFlash
@onready var _slumber_glow: Sprite2D = $SlumberGlow

func _ready() -> void:
	super._ready()
	_base_modulate = modulate
	# base_enemy.gd's direction defaults to 1 (facing right) — starts facing
	# left instead. Only matters before she acquires a target (enemy.gd's
	# _move() overwrites direction based on the player's actual side once
	# chasing starts) or while idly patrolling with no target at all.
	direction = -1

# enemy.gd's own _update_zones() hardcodes AttackZone.position.x = 12.0 *
# direction, sized for the default 16x16 body — proportionally far too
# close for her 48x48 one, which would put most of AttackZone still
# overlapping her own body instead of reaching out in front of her fists.
func _update_zones() -> void:
	super._update_zones()
	$AttackZone.position.x = 30.0 * direction

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_tick_shock_coat(delta)
	if _is_using_special or is_stunned:
		return
	if target == null or elana_in_attack_zone:
		return
	if _special_cooldown_timer > 0.0:
		_special_cooldown_timer -= delta
		return
	_start_next_special()

func _tick_shock_coat(delta: float) -> void:
	if not _shock_coat_active:
		return
	_shock_coat_timer -= delta
	if _shock_coat_timer <= 0.0:
		_shock_coat_active = false
		modulate = _base_modulate

# Overrides the AttackZone-triggered melee (see base_enemy.gd's own
# _perform_attack()) both to hook Shock Coat's "each punch shocks" and to
# block basic melee entirely while she's mid-special (_move()'s own
# override only stops horizontal movement — base_enemy.gd's attack-windup/
# cooldown cycle is a fully separate system that keeps ticking regardless,
# so without this she could still throw ordinary punches while kneeling for
# Winter Slumber or mid-telegraph on anything else). Still sets
# attack_cooldown here (not just an early return) so the windup/cooldown
# cycle progresses normally instead of looping the windup animation
# indefinitely with no cooldown ever actually starting.
func _perform_attack() -> void:
	if _is_using_special:
		attack_cooldown = get_effective_attack_cooldown()
		return
	var elana = get_tree().get_first_node_in_group("player")
	if elana:
		$WallCheck.target_position = to_local(elana.global_position)
		$WallCheck.force_raycast_update()
		if not $WallCheck.is_colliding():
			if _shock_coat_active:
				elana.take_damage(attack_damage, true, self, "elec")
				elana.apply_shock(GameData.SHOCK_STUN_DURATION)
			else:
				elana.take_damage(attack_damage, false, self)
	attack_cooldown = get_effective_attack_cooldown()

# Rooted in place for the whole telegraph+execution of a special, same
# override-the-per-subclass-hook pattern charger.gd uses for its dash —
# base_enemy.gd's _physics_process() only calls this while not attacking/
# stunned, so this is the one place that needs to know about "using special."
func _move(delta: float) -> void:
	if _is_using_special:
		velocity.x = 0.0
		return
	super._move(delta)

func _start_next_special() -> void:
	_is_using_special = true
	var attack_id: int = ATTACK_SEQUENCE[_sequence_pos]
	_sequence_pos = (_sequence_pos + 1) % ATTACK_SEQUENCE.size()
	match attack_id:
		1:
			await _do_ground_slam()
		2:
			await _do_shock_coat()
		3:
			await _do_overheat()
		4:
			await _do_winter_slumber()
	# Guards against the golem having been freed mid-attack (e.g. a killing
	# blow landing during the telegraph) — same risk dialog_marker.gd's own
	# post-await cutscene code already has to guard against.
	if not is_instance_valid(self):
		return
	modulate = _base_modulate
	_is_using_special = false
	_special_cooldown_timer = SPECIAL_COOLDOWN_GAP

func _do_ground_slam() -> void:
	modulate = TINT_GROUND_SLAM
	await get_tree().create_timer(ground_slam_windup).timeout
	if not is_instance_valid(self):
		return
	var elana = get_tree().get_first_node_in_group("player")
	if elana and elana.has_method("add_camera_trauma"):
		elana.add_camera_trauma(ground_slam_camera_shake)
	# 5 earth mounds step outward from her in whichever direction she's
	# facing, each staggered to start while the previous is still up —
	# see earth_mound_stagger's own comment for why overlapping, not
	# strictly sequential.
	for i in earth_mound_count:
		if not is_instance_valid(self):
			return
		var mound = EARTH_MOUND_SCENE.instantiate()
		mound.position = position + Vector2(direction * earth_mound_spacing * (i + 1), 0.0)
		mound.away_direction = direction
		get_parent().call_deferred("add_child", mound)
		await get_tree().create_timer(earth_mound_stagger).timeout

func _do_shock_coat() -> void:
	modulate = TINT_SHOCK_COAT
	await get_tree().create_timer(shock_coat_charge_time).timeout
	if not is_instance_valid(self):
		return
	_shock_coat_active = true
	_shock_coat_timer = shock_coat_duration
	# Stays tinted for the buff's whole duration, not just the charge —
	# _tick_shock_coat() reverts it once the buff itself expires, not here.

func _do_overheat() -> void:
	modulate = TINT_OVERHEAT
	# No warning telegraph — user's explicit choice (2026-08-20): only the
	# explosion itself gets a visual, right when it actually goes off.
	await get_tree().create_timer(overheat_telegraph_time).timeout
	if not is_instance_valid(self):
		return
	# The explosion itself shakes the camera — unconditional, not gated on
	# actually landing a hit, same as how a real AOE blast would rumble the
	# screen regardless of whether Elana happened to be standing in it.
	var elana_for_shake = get_tree().get_first_node_in_group("player")
	if elana_for_shake and elana_for_shake.has_method("add_camera_trauma"):
		elana_for_shake.add_camera_trauma(overheat_camera_shake)
	# Everyone currently inside the blast zone at the impact moment, not
	# just whoever triggered it — same convention hollowfang.gd's Cave
	# Disruptor uses get_overlapping_bodies() for.
	for body in _overheat_zone.get_overlapping_bodies():
		if body.is_in_group("player"):
			body.take_damage(overheat_blast_damage, true, self, "fire")
			body.apply_player_burn(overheat_burn_damage, overheat_burn_ticks)
			# Radial push away from the blast center (her own position, not
			# a fixed facing direction like Ground Slam's mounds — an
			# explosion pushes outward regardless of which way she's
			# standing relative to it), plus a modest knockup.
			var away: Vector2 = (body.global_position - global_position)
			var away_dir: Vector2 = away.normalized() if away.length() > 0.0 else Vector2(direction, 0.0)
			body.apply_knockback(away_dir * overheat_knockback_x + Vector2(0.0, overheat_knockup), 0.4)
	# Flash appears exactly at the blast moment, fades out over
	# overheat_flash_fade_time — the only Overheat visual now, per the
	# no-telegraph decision above.
	_overheat_flash.visible = true
	_overheat_flash.modulate.a = 1.0
	var flash_tween := create_tween()
	flash_tween.tween_property(_overheat_flash, "modulate:a", 0.0, overheat_flash_fade_time)
	flash_tween.tween_callback(func(): _overheat_flash.visible = false)

func _do_winter_slumber() -> void:
	modulate = TINT_WINTER_SLUMBER
	# Persistent glow for the whole kneel, matching the aura's real 150px
	# radius (SlumberAura's own CircleShape2D) — shows the affected area the
	# whole time she's vulnerable/healing, not just a one-off flash like
	# Overheat's (that one's momentary; this one's a standing effect).
	_slumber_glow.visible = true
	var elapsed: float = 0.0
	while elapsed < winter_slumber_duration:
		var step: float = min(0.1, winter_slumber_duration - elapsed)
		await get_tree().create_timer(step).timeout
		if not is_instance_valid(self):
			return
		elapsed += step
		hp = min(max_hp, hp + max_hp * winter_slumber_heal_pct_per_sec * step)
		for body in _slumber_aura.get_overlapping_bodies():
			if body.is_in_group("player"):
				# Same continuous-reapply-with-short-duration trick pollen_
				# puffer.gd's cloud uses — decays out naturally ~0.3s after
				# leaving the aura instead of needing explicit removal.
				# element="frost" (like Ice Wisp/Frost Beam) so herbElemental
				# Frost immunity actually applies to a frost-themed slow.
				body.apply_slow(winter_slumber_slow_factor, 0.3, "frost")
	_slumber_glow.visible = false

func on_death() -> void:
	GameData.elemental_golem_defeated = true
	GameData.spawn_float_text("Elemental Resist +10%!", global_position, Color(0.8, 0.6, 1.0))
