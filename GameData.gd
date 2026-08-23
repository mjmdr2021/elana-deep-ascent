extends Node

enum EnemyType { PATROL, STATIONARY }
enum EnemyKind { NORMAL, JUMPING }

const MAX_STACK = 5

const WEAPON_DATA = {
	"fist": {
		"attack_speed": 10, "knockback_x": 12.0, "knockback_y": -18.0,
		"has_stun": false, "stun_duration": 0.0, "swing_window": 0.1,
		"heavy_multiplier": 2.0, "color": Color(0.75, 0.75, 0.75), "hitbox_size": Vector2(16, 24),
		"weapon_power": 0.25, "weapon_base_cooldown": 0.325,
	},
	"sword": {
		"attack_speed": 18, "knockback_x": 55.0, "knockback_y": -45.0,
		"has_stun": false, "stun_duration": 0.0, "swing_window": 0.1,
		"heavy_multiplier": 2.0, "color": Color(1.0, 0.85, 0.2), "hitbox_size": Vector2(32, 26),
		"weapon_power": 1.5, "weapon_base_cooldown": 0.55,
	},
	"chain_claw": {
		"attack_speed": 50, "knockback_x": 0.0, "knockback_y": 0.0,
		"has_stun": true, "stun_duration": 0.1, "swing_window": 0.12,
		"heavy_multiplier": 1.5, "color": Color(0.9, 0.5, 0.1), "hitbox_size": Vector2(12, 18),
		"weapon_power": 1.0, "weapon_base_cooldown": 0.45,
	},
	"spear": {
		"attack_speed": 10, "knockback_x": 85.0, "knockback_y": -50.0,
		"has_stun": true, "stun_duration": 0.2, "swing_window": 0.15,
		"heavy_multiplier": 2.5, "color": Color(0.3, 0.7, 1.0), "hitbox_size": Vector2(56, 16),
		"weapon_power": 1.7, "weapon_base_cooldown": 0.55,
	},
	"warhammer": {
		"attack_speed": -30, "knockback_x": 250.0, "knockback_y": -220.0,
		"has_stun": true, "stun_duration": 0.6, "swing_window": 0.2,
		"heavy_multiplier": 3.0, "color": Color(0.85, 0.15, 0.15), "hitbox_size": Vector2(26, 36),
		"weapon_power": 2.2, "weapon_base_cooldown": 1.0,
	},
}

const ORE_REGISTRY = {
	"ore1": "sword",
	"ore2": "chain_claw",
	"ore3": "spear",
	"ore4": "warhammer",
}

const ORE_DURATION = 30.0

# Weapon form is Glint's own HP now — one universal pool, not per-weapon.
# She takes damage per landed hit (amount varies by weapon/light-vs-heavy,
# see WEAPON_HIT_COST) and Elana reverts to fist once she runs out.
const GLINT_BASE_HP: float = 20.0
const GLINT_HP_PER_LEVEL: float = 1.0

# HP Glint loses per enemy struck — claws are light on her, hammers are not,
# and a charged/heavy swing always costs more than a light one.
const WEAPON_HIT_COST: Dictionary = {
	"sword":      { "light": 2.0, "heavy": 3.0 },
	"chain_claw": { "light": 1.0, "heavy": 2.0 },
	"spear":      { "light": 3.0, "heavy": 5.0 },
	"warhammer":  { "light": 4.0, "heavy": 6.0 },
}

const HERB_REGISTRY = {
	"herbElementalFire": preload("res://herb_elemental_fire.gd"),
	"herbElementalFrost": preload("res://herb_elemental_frost.gd"),
	"herbElementalElec": preload("res://herb_elemental_elec.gd"),
	"herbAgility": preload("res://herb_agility.gd"),
	"herbHeal": preload("res://herb_heal.gd"),
	"herbPower": preload("res://herb_power.gd"),
}

# item_id -> which skill tree it resets. Sold by Moleman, consumed like a herb/ore.
const RESPEC_REGISTRY = {
	"respecElana": "elana",
	"respecGlint": "glint",
}

# Collectibles with no quickslot effect — lore notes and future key items.
# _use_selected_item() (hud.gd) checks this and no-ops a click rather than
# consuming/removing one if it's ever dragged into a quickslot manually.
const KEY_ITEM_REGISTRY = {
	"note1": true,
}

# ── Elana Skill Tree ─────────────────────────────────────────────────────────
# type: "stat" (1 SP unlocks path, incremental effect)
#       "passive" (1 SP unlocks path, effect not yet implemented)
#       "skill" (must max prereq to unlock, grants ability)
const SKILL_TREE_DATA: Dictionary = {
	# Shared gateway
	"herb_mastery":       { "name": "Herb Mastery",      "type": "stat",    "path": 0, "max_level": 4, "prereq": "", "desc": "+10% herb potency/lvl" },
	"quick_digestion":    { "name": "★ Quick Digestion", "type": "skill",   "path": 0, "max_level": 1, "prereq": "herb_mastery", "desc": "Herb use ignores the item-use cooldown" },
	# Always owned from game start — not spent from SP, no prereq chain.
	"air_dash_node":      { "name": "★ Air Dash",        "type": "skill",   "path": 0, "max_level": 1, "prereq": "", "desc": "Dash once in mid-air (unlocked from the start)" },
	# Life path (1)
	"vitality":           { "name": "Vitality",           "type": "stat",    "path": 1, "max_level": 3, "prereq": "herb_mastery",    "desc": "+15% max HP/lvl" },
	"iron_body":          { "name": "Iron Body",          "type": "passive",  "path": 1, "max_level": 3, "prereq": "vitality",         "desc": "20s no dmg → HP barrier" },
	"herb_heal_plus":     { "name": "Herb Heal+",         "type": "stat",    "path": 1, "max_level": 3, "prereq": "vitality",         "desc": "+15% Heal Herb regen/lvl" },
	"overheal_shield":    { "name": "Overheal Shield",    "type": "passive",  "path": 1, "max_level": 3, "prereq": "herb_heal_plus",  "desc": "+33% overheal→shield/lvl" },
	"last_stand":         { "name": "Last Stand",         "type": "passive",  "path": 1, "max_level": 3, "prereq": "herb_heal_plus",  "desc": "Heal 30-50% HP on low HP" },
	"fortitude":          { "name": "Fortitude",          "type": "stat",    "path": 1, "max_level": 3, "prereq": "herb_heal_plus",  "desc": "+5% dmg reduction/lvl" },
	"elem_resist":        { "name": "Elem Resist",        "type": "passive",  "path": 1, "max_level": 3, "prereq": "fortitude",        "desc": "+10% elemental resist/lvl" },
	"bulwark":            { "name": "Bulwark",            "type": "passive",  "path": 1, "max_level": 3, "prereq": "fortitude",        "desc": "+10% dmg returned/lvl" },
	"life_barrier_skill": { "name": "★ Life Barrier",    "type": "skill",   "path": 1, "max_level": 1, "prereq": "fortitude",        "desc": "Barrier absorbs 70% max HP (Heal Herb)" },
	# Agile path (2)
	"agility":            { "name": "Agility",            "type": "stat",    "path": 2, "max_level": 3, "prereq": "herb_mastery",    "desc": "+10% jump height/lvl" },
	"wall_jump_skill":    { "name": "★ Wall Jump",       "type": "skill",   "path": 2, "max_level": 1, "prereq": "agility",          "desc": "Unlock wall jump" },
	"agility_herb_speed":        { "name": "Agility Herb+",       "type": "stat",    "path": 2, "max_level": 3, "prereq": "agility",          "desc": "+10% move speed (Agility Herb)" },
	"attack_speed_node":  { "name": "Attack Speed",       "type": "stat",    "path": 2, "max_level": 3, "prereq": "agility_herb_speed",      "desc": "+10% atk speed (Agility Herb)" },
	"flash_stun_skill":   { "name": "★ Flash Stun",      "type": "skill",   "path": 2, "max_level": 1, "prereq": "attack_speed_node","desc": "Stun all enemies 3s (Agility Herb)" },
	"luminosity_plus":    { "name": "Luminosity+",        "type": "passive",  "path": 2, "max_level": 3, "prereq": "agility_herb_speed",      "desc": "+1 glow radius tier/lvl; +fog reveal size/lvl" },
	"scouting_distance":  { "name": "Scouting Distance",  "type": "stat",    "path": 2, "max_level": 3, "prereq": "luminosity_plus",  "desc": "+140 scout leash distance/lvl" },
	"phantom_blur":       { "name": "Phantom Blur",       "type": "stat",    "path": 2, "max_level": 3, "prereq": "agility_herb_speed",      "desc": "+8% dodge chance/lvl" },
	"double_jump_skill":  { "name": "★ Double Jump",     "type": "skill",   "path": 2, "max_level": 1, "prereq": "phantom_blur",     "desc": "Unlock double jump" },
	"dodge_roll_skill":   { "name": "★ Dodge Roll",      "type": "skill",   "path": 2, "max_level": 1, "prereq": "phantom_blur",     "desc": "Unlock dodge roll" },
	# Elemental path (3)
	"elemental_potency":         { "name": "Elemental Potency",         "type": "stat",    "path": 3, "max_level": 3, "prereq": "herb_mastery",    "desc": "+10% elemental proj dmg/lvl" },
	"casting_speed":      { "name": "Casting Speed",      "type": "stat",    "path": 3, "max_level": 3, "prereq": "elemental_potency",       "desc": "+15% cast speed/lvl" },
	"double_cast":        { "name": "Double Cast",        "type": "passive",  "path": 3, "max_level": 3, "prereq": "casting_speed",    "desc": "2nd proj at 40/70/100% dmg" },
	"ice_potency":        { "name": "Ice Potency",        "type": "stat",    "path": 3, "max_level": 3, "prereq": "elemental_potency",       "desc": "+10% ice dmg & resist/lvl" },
	"freeze":             { "name": "Freeze",             "type": "passive",  "path": 3, "max_level": 3, "prereq": "ice_potency",      "desc": "+15% freeze chance/lvl" },
	"shield_wall_skill":  { "name": "★ Shield Wall",     "type": "skill",   "path": 3, "max_level": 1, "prereq": "freeze",           "desc": "Summon ice wall (Frost Herb)" },
	"fire_potency":       { "name": "Fire Potency",       "type": "stat",    "path": 3, "max_level": 3, "prereq": "elemental_potency",       "desc": "+10% fire dmg & resist/lvl" },
	"burn":               { "name": "Burn",               "type": "passive",  "path": 3, "max_level": 3, "prereq": "fire_potency",     "desc": "+20% burn DoT dmg/lvl" },
	"fire_blast_skill":   { "name": "★ Fire Blast",      "type": "skill",   "path": 3, "max_level": 1, "prereq": "burn",             "desc": "AOE knockback blast (Fire Herb)" },
	"lightning_potency":  { "name": "Lightning Potency",  "type": "stat",    "path": 3, "max_level": 3, "prereq": "elemental_potency",       "desc": "+10% lightning dmg & resist/lvl" },
	"chain_lightning":    { "name": "Chain Lightning",    "type": "stat",    "path": 3, "max_level": 3, "prereq": "lightning_potency","desc": "+1 chain target/lvl (70% dmg)" },
	"storm_skill":        { "name": "★ Storm",           "type": "skill",   "path": 3, "max_level": 1, "prereq": "chain_lightning",  "desc": "Continuous lightning (Elec Herb)" },
	# Power path (4)
	"power_potency":         { "name": "Power Potency",         "type": "stat",    "path": 4, "max_level": 3, "prereq": "herb_mastery",    "desc": "+10% Power Herb dmg/lvl" },
	"anger_strikes":      { "name": "Anger Strikes",      "type": "passive",  "path": 4, "max_level": 3, "prereq": "power_potency",       "desc": "+1% enemy max HP bonus dmg" },
	"shockwave":          { "name": "Shockwave",          "type": "passive",  "path": 4, "max_level": 3, "prereq": "power_potency",       "desc": "Shockwave at 60/70/80% dmg" },
	"penetration":        { "name": "Penetration",        "type": "stat",    "path": 4, "max_level": 3, "prereq": "power_potency",       "desc": "+2% armor ignore/lvl" },
	"berserker":          { "name": "Berserker",          "type": "passive",  "path": 4, "max_level": 3, "prereq": "penetration",      "desc": "+15/28/40% dmg at low HP" },
	"executioner":        { "name": "Executioner",        "type": "passive",  "path": 4, "max_level": 3, "prereq": "penetration",      "desc": "+5% insta-kill at ≤15% HP" },
	"bloodlust":          { "name": "Bloodlust",          "type": "stat",    "path": 4, "max_level": 3, "prereq": "penetration",      "desc": "+5% lifesteal/lvl" },
	"blood_fury_skill":   { "name": "★ Blood Fury",      "type": "skill",   "path": 4, "max_level": 1, "prereq": "bloodlust",        "desc": "Toggle ×2 dmg, drain 1.5× (Power Herb)" },
}

# ── Glint Skill Tree ─────────────────────────────────────────────────────────
# type: "stat" (incremental effect) / "passive" (effect not yet implemented)
# All nodes open the path forward at 1 SP (no max-prereq "skill" nodes here).
const GLINT_SKILL_TREE_DATA: Dictionary = {
	# Gateway
	"g_ore_mastery":      { "name": "Ore Mastery",        "type": "stat",    "max_level": 6,  "prereq": "",                  "desc": "+5 Glint max HP/lvl" },
	# Branch 1 — Weapon Enhancement (50 SP)
	"g_weapon_damage":    { "name": "Weapon Damage",      "type": "stat",    "max_level": 6,  "prereq": "g_ore_mastery",     "desc": "+10% weapon dmg/lvl" },
	"g_crit_chance":      { "name": "Crit Chance",        "type": "stat",    "max_level": 10, "prereq": "g_weapon_damage",   "desc": "+5% crit chance/lvl" },
	"g_crit_damage":      { "name": "Crit Damage",        "type": "stat",    "max_level": 5,  "prereq": "g_crit_chance",     "desc": "+15% crit dmg mult/lvl" },
	"g_quick_feed":       { "name": "Quick Feed",         "type": "passive", "max_level": 1,  "prereq": "g_ore_mastery",     "desc": "Feeding ores ignores the item-use cooldown" },
	"g_weapon_mastery":   { "name": "Weapon Mastery",     "type": "stat",    "max_level": 2,  "prereq": "g_crit_chance",     "desc": "-50% transform delay/lvl" },
	"g_prime_form":       { "name": "Prime Form",         "type": "stat",    "max_level": 4,  "prereq": "g_weapon_mastery",  "desc": "+5% weapon power/lvl while weapon is fresh (first 10s)" },
	"g_combo_strike":     { "name": "Combo Strike",       "type": "passive", "max_level": 6,  "prereq": "g_weapon_mastery",  "desc": "+4% dmg per combo hit (max = lvl) · breaks after 2s without a hit" },
	"g_lethal_striker":   { "name": "Lethal Striker",     "type": "stat",    "max_level": 4,  "prereq": "g_weapon_mastery",  "desc": "+5% chance/lvl to shatter armor — bonus dmg vs armored foes · very lethal with Penetration" },
	"g_executioner":      { "name": "Executioner",        "type": "passive", "max_level": 6,  "prereq": "g_lethal_striker",  "desc": "+5%/lvl dmg per kill stack (max 5, resets 10s after last kill)" },
	"g_overcharge":       { "name": "Overcharge",         "type": "passive", "max_level": 6,  "prereq": "g_lethal_striker",  "desc": "Re-feeding the same ore stacks +10% dmg (max = lvl)" },
	# Branch 2 — Herb Integration (50 SP)
	"g_herb_integration": { "name": "Herb Integration",   "type": "passive", "max_level": 1,  "prereq": "g_ore_mastery",     "desc": "Enables herb synergy on weapon · +30% glow radius while herb active" },
	"g_herb_elemental":   { "name": "Elemental",          "type": "passive", "max_level": 1,  "prereq": "g_herb_integration","desc": "Enables elemental effect on weapon hit (Elemental Herbs)" },
	"g_slow":             { "name": "Slow",               "type": "passive", "max_level": 8,  "prereq": "g_herb_elemental",  "desc": "Melee hits slow 3s (Frost Herb) · +5% slow/lvl (max 40%)" },
	"g_burn":             { "name": "Burn",               "type": "passive", "max_level": 8,  "prereq": "g_herb_elemental",  "desc": "Melee hits burn 3s (Fire Herb) · +5% tick dmg/lvl" },
	"g_chain":            { "name": "Chain",              "type": "passive", "max_level": 8,  "prereq": "g_herb_elemental",  "desc": "Melee hits arc lightning to +1 enemy/lvl (Elec Herb) · 35% of magic dmg per arc" },
	"g_toxic":            { "name": "Toxic",              "type": "passive", "max_level": 8,  "prereq": "g_herb_integration","desc": "Melee hits poison 8s (Heal Herb) · +2% tick dmg/lvl" },
	"g_lifesteal":        { "name": "Lifesteal",          "type": "passive", "max_level": 8,  "prereq": "g_herb_integration","desc": "+3% melee lifesteal/lvl (Power Herb)" },
	"g_phantom":          { "name": "Phantom",            "type": "passive", "max_level": 8,  "prereq": "g_herb_integration","desc": "+2% phantom strike chance/lvl (Agility Herb) · inherits crit" },
}

var hp = 100
var max_hp = 100
var oxygen: float = 100.0
var max_oxygen: float = 100.0
var inventory_slots: Array = []
var quickslot_slots: Array = []
var xp = 0
var level = 1
var sp = 0
var glint_sp: int = 0
var defense: int = 0
var dodge_chance: float = 0.0
var base_speed: float = 100.0
var attack_speed_stat: int = 10
var weapon_attack_speed: int = 20
var attack_speed_herb_bonus: int = 0
var move_speed_herb_bonus: float = 0.0
var damage_multiplier: float = 1.0
var current_weapon: String = "fist"
var glint_hp: float = 0.0
var glint_max_hp: float = 0.0
var weapon_swing_window: float = 0.1
var weapon_knockback_x: float = 80.0
var weapon_knockback_y: float = -40.0
var weapon_has_stun: bool = false
var weapon_stun_duration: float = 0.0
var weapon_heavy_multiplier: float = 2.0
var weapon_power: float = 1.0
var weapon_base_cooldown: float = 0.65
var weapon_color: Color = Color(0.75, 0.75, 0.75)
var weapon_hitbox_size: Vector2 = Vector2(16, 24)
var hp_regen: float = 0.0
var hp_regen_herb_bonus: float = 0.0
var elemental_active: bool = false
var elemental_element: String = ""
var active_herb = null
var herb_timer: float = 0.0
var herb_max_timer: float = 0.0
var herb_drain_multiplier: float = 1.0
# ── Skill tree state ─────────────────────────────────────────────────────────
var skill_tree_levels: Dictionary = {}
# ── Glint skill tree state ───────────────────────────────────────────────────
var glint_skill_tree_levels: Dictionary = {}
var glint_hp_bonus: float = 0.0
var glint_weapon_dmg_bonus: float = 0.0
var glint_crit_chance: float = 0.0
var glint_crit_dmg_mult: float = 1.5
var glint_armor_ignore_chance: float = 0.0
var glint_fresh_weapon_dmg: float = 0.0
var glint_herb_lifesteal: float = 0.0
var glint_burn_bonus: float = 0.0
var glint_slow_pct: float = 0.0
var glint_toxic_bonus: float = 0.0
var glint_phantom_pct: float = 0.0
var transform_delay_timer: float = 0.0
var glint_overcharge_stacks: int = 0
var glint_combo_stacks: int = 0
var glint_combo_timer: float = 0.0
var glint_exec_stacks: int = 0
var glint_exec_timer: float = 0.0

const TRANSFORM_DELAY: float = 1.0
const FRESH_WEAPON_WINDOW: float = 10.0
const FRESH_WEAPON_HIT_FRACTION: float = FRESH_WEAPON_WINDOW / ORE_DURATION
const GLINT_BURN_BASE: float = 0.10
const GLINT_BURN_TICKS: int = 3
const GLINT_SLOW_DURATION: float = 3.0
const GLINT_POISON_BASE: float = 0.05
const GLINT_POISON_TICKS: int = 8
const GLINT_PHANTOM_DMG: float = 0.5
const GLINT_CHAIN_DMG: float = 0.5 * 0.7  # 50% of magic dmg, then chain-lightning falloff
const COMBO_WINDOW: float = 2.0
const EXEC_WINDOW: float = 10.0
const EXEC_MAX_STACKS: int = 5
# Derived stats from skill tree (recalculated in _apply_skill_node_effect)
var elemental_dmg_bonus: float = 0.0
var damage_reduction_skill: float = 0.0
var armor_penetration: float = 0.0
var lifesteal: float = 0.0
var chain_lightning_count: int = 0
var jump_mult: float = 1.0
var casting_speed_bonus: float = 0.0
var herb_heal_bonus: float = 0.0
var elemental_resist: float = 0.0
var fire_potency_resist: float = 0.0
var frost_potency_resist: float = 0.0
var elec_potency_resist: float = 0.0
const HERB_ELEMENT_RESIST_BASELINE: float = 0.15
var burn_dmg_mult: float = 0.0
var freeze_chance: float = 0.0
var double_cast_mult: float = 0.0
var berserker_mult: float = 0.0
var executioner_chance: float = 0.0
var anger_strikes_pct: float = 0.0
var shockwave_pct: float = 0.0
var herb_duration_bonus: float = 0.0
var attack_speed_node_bonus: int = 0
var agility_herb_speed_bonus: float = 0.0
var glint_luminosity_bonus: float = 0.0
# Scouting Distance (child of Luminosity+) — added to glint.gd's scout
# leash radius, world px/lvl.
var scout_leash_radius_bonus: float = 0.0
# Luminosity+ itself also grows Glint's own fog_of_war.gd erase radius,
# always — not just while scouting (see fog_of_war.gd's _physics_process(),
# fixed 2026-08-20) — world px/lvl, on top of its own existing glow-radius/
# brightness effect.
var scout_fog_erase_bonus: float = 0.0
var power_potency_bonus: float = 0.0
var last_stand_heal_pct: float = 0.0
var last_stand_cd: float = 0.0
var iron_body_pct: float = 0.0
var overheal_conv: float = 0.0
var bulwark_pct: float = 0.0
var passive_shield_hp: float = 0.0
var spawn_point_id = "SpawnDefault"
var respawn_scene = ""
var active_ritual_node = ""
# Position-based, not a marker name — full_map.tscn never actually had a
# "SpawnRight" marker, so the old respawn_spawn_id lookup silently found
# nothing and respawn/Continue always fell through to wherever Elana's node
# happened to sit in the scene. Each Ritual Node writes its own position here.
var respawn_position: Vector2 = Vector2.ZERO
# Base64-encoded PNG — fog_of_war.gd's permanent "explored trail" mask.
# Round-tripped as a plain string so it fits the existing JSON save format
# without a schema change; fog_of_war.gd owns actually reading/painting it.
var fog_mask_png: String = ""
var just_died = false
var default_scene = "res://full_map.tscn"
var default_spawn_id = "SpawnDefault"
# Set by title_screen.gd right before switching to loading_screen.tscn — the
# path loading_screen.gd should threaded-load and switch to next. Not saved
# (transient hand-off only, cleared the instant loading_screen.gd reads it).
var pending_scene_load: String = ""
var use_default_spawn = false
var wall_jump_enabled = false
var double_jump_enabled = false
var elemander_pads_unlocked = false  # Blessing #2 — indefinite wall stick
var golden_cloak_unlocked = false  # Sanctuary secret — floating descent while holding jump
var hollowscale_unlocked = false  # Blessing #1 — +armor, one-hit ward on a flat cooldown
var hollowscale_cooldown: float = 0.0
const HOLLOWSCALE_ARMOR_BONUS: int = 15
const HOLLOWSCALE_RECHARGE: float = 10.0
# Ant Queen mini-boss reward — halves incoming damage from anything tagged
# "hazards" (see elana.gd's take_damage()). Not part of the mandatory-boss
# Blessing track, just a permanent flag set on her on_death().
var ant_queen_defeated = false
const HAZARD_DAMAGE_REDUCTION: float = 0.5
# Elemental Golem mini-boss reward — permanent +10% resist to every element,
# folded into get_elemental_resist_for() below. A separate additive field
# instead of writing directly into elemental_resist (the elem_resist skill
# node's own stat, already clamped 0.0-0.30 by _apply_skill_node_effect())
# so this can't collide with or get overwritten by that clamp.
var elemental_golem_defeated: bool = false
const ELEMENTAL_GOLEM_RESIST_BONUS: float = 0.10
# Single source of truth for how long Elana's "shocked" status (elana.gd's
# apply_shock() — input blocked, momentum NOT zeroed, unlike stun/freeze)
# lasts, shared by every electric source instead of each keeping its own
# separate copy of the same number: Elemander's Electric Storm bolts
# (elemander.gd) and electrified water (terrain_hazards.gd) both read this.
const SHOCK_STUN_DURATION: float = 0.7
var dev_no_cooldowns = false  # Dev toggle — forces every cooldown to stay at 0 while on
var dev_fixed_zoom_1x = false  # Dev toggle — locks camera to 1x zoom instead of the dynamic system
var dev_fixed_zoom_0_1x = false  # Dev toggle (2026-08-22) — locks camera to 0.1x zoom, a very wide debug view
var screen_shake_enabled = true  # Dev toggle — heavy hits/impacts shake the camera
# Overrides the normal per-action camera zoom to a fixed wide arena view once
# set — no auto-clear; reset_boss_camera() (called on boss death or player
# respawn) turns it off.
var boss_zoom_active: bool = false
# Which zoom level boss_zoom_active eases toward (elana.gd's
# _update_camera_lock() reads this instead of a hardcoded constant) --
# defaults to Hollowfang's original 3.5, per-boss overridable (2026-08-22,
# user request: "for boss2hole make it 3 zoom for camera") -- set by
# dialog_marker.gd right before each boss-entrance cutscene flips
# boss_zoom_active on, so a later encounter always gets its own intended
# level instead of inheriting whatever a previous one last left behind.
var boss_zoom_level: Vector2 = Vector2(3.5, 3.5)
# True while the camera should stay clamped to camera_bounds instead of
# following Elana without limit (elana.gd reads this every frame — see
# _update_camera_lock()) — set alongside boss_zoom_active by the boss-arena
# reveal cutscene, cleared the same way. A plain bool, not a Node reference —
# nothing ever reads the boss's own position/transform off it, it's purely
# a presence gate.
var camera_locked: bool = false
# World-space rect the camera is clamped to while camera_locked is true —
# still follows Elana normally moment to moment, just can't drift the view
# past these bounds. An empty Rect2() (size == Vector2.ZERO) means no bounds
# were provided (e.g. a future boss without get_camera_bounds()) — leave
# whatever limits are already applied rather than clamping to a single point.
var camera_bounds: Rect2 = Rect2()
# True only while dialog_marker.gd's CAMERA_PAN cutscene tween is actively
# animating camera_offset_base — elana.gd's _update_camera_lock() stays
# fully hands-off while this is true so it can't fight the tween.
var camera_pan_active: bool = false

# Shared reset for the boss-arena camera override — called from both
# hollowfang.gd's _die() and elana.gd's die()/respawn path, so however the
# encounter ends, the camera always returns to normal. Also called from the
# full-game reset() below, so a reset mid-cutscene can't leave stale bounds
# or a stuck camera_pan_active behind.
func reset_boss_camera() -> void:
	boss_zoom_active = false
	camera_locked = false
	camera_bounds = Rect2()
	camera_pan_active = false

# Glint independent scouting — she detaches to roam/light the way ahead while
# Elana stands frozen (but still damageable). glint_scouting covers the whole
# window (roam + return flight); glint_scout_returning narrows it to just the
# beeline-home leg, where she ignores collision and Elana stays uncontrollable
# until she physically arrives back.
var glint_scouting: bool = false
var glint_scout_returning: bool = false
# Set once the "Press X again to return to Elana" hint has been shown, the
# first time she ever enters scout mode — never shown again after that.
var glint_scout_return_hint_shown: bool = false

# Dialogue — in_cutscene freezes Elana the same way glint_scouting does
# (movement/actions locked, gravity still applies). pending_intro is set once
# by "New Game" and consumed by Elana's own _ready() to fire the opening
# sequence exactly once.
var in_cutscene: bool = false
var pending_intro: bool = false
# cutscene_scripted_move lets a cutscene drive velocity.x itself (e.g. a
# forced walk) without the in_cutscene freeze zeroing it back out each frame.
var cutscene_scripted_move: bool = false
# Glint position lock for scripted beats — dynamic mode tracks the opposite
# side of Elana's current facing (a "stays behind you" lock); frozen mode
# leaves her exactly where she is regardless of facing changes, so a turn
# can reveal her instead of her sliding along with it.
var glint_position_locked: bool = false
var glint_lock_follows_facing: bool = true
# Set once the Stone Being cutscene has played — guards it from retriggering
# on later visits, same one-shot pattern as pending_intro.
var stone_being_met: bool = false
# False for the whole prologue (game start through the Stone Being cutscene) —
# HUD stays hidden and menus/attacking stay locked the entire time, not just
# during the two explicit cutscenes. Set true once she's actually granted.
var received_stone_being_power: bool = false
# Set once the Glint-scout (X) tutorial at the dialog_marker has played.
var glint_scout_tutorial_done: bool = false
# Set once the air dash dialog_marker (AIR_DASH_TUTORIAL) has played.
var air_dash_tutorial_done: bool = false
# Set once the camera-pan dialog_marker (Boss1NormalEntranceCutscene) has played.
var camera_pan_intro_done: bool = false
# One-shot world-object interaction hints ("E to pickup" / "Hit to break"),
# shown on whichever herb/ore node has its own show_pickup_hint/
# show_break_hint export flag set true.
var herb_pickup_hint_shown: bool = false
var ore_break_hint_shown: bool = false
var danger_sense_unlocked = false  # Blessing #3 — active, slows all enemies in the room
var danger_sense_cooldown: float = 0.0
var danger_sense_active_timer: float = 0.0  # remaining time in the current slow window
const DANGER_SENSE_COOLDOWN: float = 30.0
const DANGER_SENSE_DURATION: float = 5.0
const DANGER_SENSE_SLOW_FACTOR: float = 0.2
var dodge_enabled = false
var air_dash_enabled = false  # locked until the Stone Being grants it
var show_hp_bars = true
var item_use_cooldown_enabled: bool = true
var room_state = {}  # { "res://scene.tscn": { "NodeName": true } }
var seen_items: Dictionary = {}  # { "herbAgility": true, ... } — first-consume tutorial tooltip
var shop_purchases: Dictionary = {}  # { "res://scene.tscn": { "Moleman::ore1": 3, ... } }

# ── Skill tree API ───────────────────────────────────────────────────────────

# Shared level/prereq logic for both trees (Elana and Glint).
# "skill" nodes need their prereq maxed; everything else needs prereq lvl 1.
func _tree_level(levels: Dictionary, node_id: String) -> int:
	return levels.get(node_id, 0)

func _tree_can_spend(data: Dictionary, levels: Dictionary, points: int, node_id: String) -> bool:
	if points <= 0 or not data.has(node_id):
		return false
	var node: Dictionary = data[node_id]
	if _tree_level(levels, node_id) >= int(node["max_level"]):
		return false
	var prereq: String = node.get("prereq", "")
	if prereq != "":
		var prereq_lvl: int = _tree_level(levels, prereq)
		if node["type"] == "skill":
			if prereq_lvl < int(data[prereq]["max_level"]):
				return false
		elif prereq_lvl < 1:
			return false
	return true

func get_skill_level(node_id: String) -> int:
	return _tree_level(skill_tree_levels, node_id)

func is_skill_unlocked(node_id: String) -> bool:
	return get_skill_level(node_id) >= 1

func can_spend_skill_point(node_id: String) -> bool:
	return _tree_can_spend(SKILL_TREE_DATA, skill_tree_levels, sp, node_id)

func spend_skill_point(node_id: String) -> void:
	if not can_spend_skill_point(node_id):
		return
	sp -= 1
	skill_tree_levels[node_id] = get_skill_level(node_id) + 1
	_apply_skill_node_effect(node_id)

func _apply_skill_node_effect(node_id: String) -> void:
	match node_id:
		"vitality":
			max_hp += 15
			hp = min(hp, max_hp)
		"fortitude":
			damage_reduction_skill = clamp(damage_reduction_skill + 0.05, 0.0, 0.50)
		"agility":
			jump_mult += 0.10
		"phantom_blur":
			dodge_chance = clamp(dodge_chance + 0.08, 0.0, 0.80)
		"elemental_potency":
			elemental_dmg_bonus += 0.10
		"ice_potency":
			elemental_dmg_bonus += 0.10
			frost_potency_resist += 0.10
		"fire_potency":
			elemental_dmg_bonus += 0.10
			fire_potency_resist += 0.10
		"lightning_potency":
			elemental_dmg_bonus += 0.10
			elec_potency_resist += 0.10
		"casting_speed":
			casting_speed_bonus = clamp(casting_speed_bonus + 0.15, 0.0, 0.75)
		"chain_lightning":
			chain_lightning_count += 1
		"penetration":
			match get_skill_level("penetration"):
				1: armor_penetration = 0.20
				2: armor_penetration = 0.35
				3: armor_penetration = 0.50
		"herb_heal_plus":
			herb_heal_bonus = clamp(herb_heal_bonus + 0.15, 0.0, 0.45)
		"elem_resist":
			elemental_resist = clamp(elemental_resist + 0.10, 0.0, 0.30)
		"bloodlust":
			lifesteal = clamp(lifesteal + 0.05, 0.0, 0.15)
		"burn":
			match get_skill_level("burn"):
				1: burn_dmg_mult = 0.12
				2: burn_dmg_mult = 0.24
				3: burn_dmg_mult = 0.36
		"freeze":
			match get_skill_level("freeze"):
				1: freeze_chance = 0.25
				2: freeze_chance = 0.50
				3: freeze_chance = 0.75
		"double_cast":
			match get_skill_level("double_cast"):
				1: double_cast_mult = 0.40
				2: double_cast_mult = 0.70
				3: double_cast_mult = 1.00
		"berserker":
			match get_skill_level("berserker"):
				1: berserker_mult = 0.25
				2: berserker_mult = 0.40
				3: berserker_mult = 0.55
		"executioner":
			match get_skill_level("executioner"):
				1: executioner_chance = 0.08
				2: executioner_chance = 0.15
				3: executioner_chance = 0.22
		"anger_strikes":
			match get_skill_level("anger_strikes"):
				1: anger_strikes_pct = 0.03
				2: anger_strikes_pct = 0.05
				3: anger_strikes_pct = 0.08
		"herb_mastery":
			match get_skill_level("herb_mastery"):
				2: herb_duration_bonus = 5.0
				3: herb_duration_bonus = 10.0
				4: herb_duration_bonus = 20.0
		"power_potency":
			power_potency_bonus = clamp(power_potency_bonus + 0.10, 0.0, 0.30)
		"attack_speed_node":
			attack_speed_node_bonus += 10
		"agility_herb_speed":
			agility_herb_speed_bonus += 10.0
		"luminosity_plus":
			glint_luminosity_bonus += 0.4
			scout_fog_erase_bonus += 15.0
		"scouting_distance":
			scout_leash_radius_bonus += 140.0
		"shockwave":
			match get_skill_level("shockwave"):
				1: shockwave_pct = 0.35
				2: shockwave_pct = 0.50
				3: shockwave_pct = 0.65
		"last_stand":
			match get_skill_level("last_stand"):
				1: last_stand_heal_pct = 0.30
				2: last_stand_heal_pct = 0.40
				3: last_stand_heal_pct = 0.50
		"iron_body":
			match get_skill_level("iron_body"):
				1: iron_body_pct = 0.20
				2: iron_body_pct = 0.40
				3: iron_body_pct = 0.65
		"overheal_shield":
			match get_skill_level("overheal_shield"):
				1: overheal_conv = 0.33
				2: overheal_conv = 0.66
				3: overheal_conv = 1.00
		"bulwark":
			match get_skill_level("bulwark"):
				1: bulwark_pct = 0.08
				2: bulwark_pct = 0.16
				3: bulwark_pct = 0.25
		"wall_jump_skill":
			wall_jump_enabled = true
		"double_jump_skill":
			double_jump_enabled = true
		"dodge_roll_skill":
			dodge_enabled = true

# ── Glint skill tree API ─────────────────────────────────────────────────────

func get_glint_skill_level(node_id: String) -> int:
	return _tree_level(glint_skill_tree_levels, node_id)

# Dev cheat — grants a pile of SP and spends it through the normal
# spend_*_skill_point() path repeatedly until every node in both trees is
# maxed, so prereq chains resolve themselves instead of being hardcoded here.
func dev_max_all_skills() -> void:
	sp = 9999
	glint_sp = 9999
	var changed := true
	while changed:
		changed = false
		for node_id in SKILL_TREE_DATA.keys():
			while can_spend_skill_point(node_id):
				spend_skill_point(node_id)
				changed = true
		for node_id in GLINT_SKILL_TREE_DATA.keys():
			while can_spend_glint_skill_point(node_id):
				spend_glint_skill_point(node_id)
				changed = true
	sp = 0
	glint_sp = 0

func can_spend_glint_skill_point(node_id: String) -> bool:
	return _tree_can_spend(GLINT_SKILL_TREE_DATA, glint_skill_tree_levels, glint_sp, node_id)

func spend_glint_skill_point(node_id: String) -> void:
	if not can_spend_glint_skill_point(node_id):
		return
	glint_sp -= 1
	glint_skill_tree_levels[node_id] = get_glint_skill_level(node_id) + 1
	_apply_glint_node_effect(node_id)

func _apply_glint_node_effect(node_id: String) -> void:
	match node_id:
		"g_ore_mastery":
			glint_hp_bonus += 5.0
		"g_weapon_damage":
			glint_weapon_dmg_bonus += 0.10
		"g_crit_chance":
			glint_crit_chance += 0.05
		"g_crit_damage":
			glint_crit_dmg_mult += 0.15
		"g_lethal_striker":
			glint_armor_ignore_chance += 0.05
		"g_prime_form":
			glint_fresh_weapon_dmg += 0.05
		"g_lifesteal":
			glint_herb_lifesteal += 0.03
		"g_burn":
			glint_burn_bonus += 0.05
		"g_slow":
			glint_slow_pct = clamp(glint_slow_pct + 0.05, 0.0, 0.40)
		"g_toxic":
			glint_toxic_bonus += 0.02
		"g_phantom":
			glint_phantom_pct += 0.02
		# g_weapon_mastery is read from its level in apply_ore.
		# g_herb_integration is read from its level in glint.gd (glow radius).
		# g_overcharge / g_combo_strike / g_executioner are read from their
		# levels by the stack systems (apply_ore / glint_register_hit / _kill).
		# g_chain is read from its level by _glint_chain_arc in elana.gd.

# Every stat _apply_skill_node_effect() can touch, reset to its zero/base
# value — EXCEPT max_hp, which also grows from leveling and must be handled
# separately by whoever calls this (subtract the tree's exact contribution,
# don't hard-reset it). Shared by reset() (new game) and apply_respec().
func _reset_elana_skill_stats() -> void:
	damage_reduction_skill = 0.0
	jump_mult = 1.0
	dodge_chance = 0.0
	elemental_dmg_bonus = 0.0
	frost_potency_resist = 0.0
	fire_potency_resist = 0.0
	elec_potency_resist = 0.0
	casting_speed_bonus = 0.0
	chain_lightning_count = 0
	armor_penetration = 0.0
	herb_heal_bonus = 0.0
	elemental_resist = 0.0
	lifesteal = 0.0
	burn_dmg_mult = 0.0
	freeze_chance = 0.0
	double_cast_mult = 0.0
	berserker_mult = 0.0
	executioner_chance = 0.0
	anger_strikes_pct = 0.0
	herb_duration_bonus = 0.0
	power_potency_bonus = 0.0
	attack_speed_node_bonus = 0
	agility_herb_speed_bonus = 0.0
	glint_luminosity_bonus = 0.0
	scout_leash_radius_bonus = 0.0
	scout_fog_erase_bonus = 0.0
	shockwave_pct = 0.0
	last_stand_heal_pct = 0.0
	iron_body_pct = 0.0
	overheal_conv = 0.0
	bulwark_pct = 0.0
	wall_jump_enabled = false
	double_jump_enabled = false
	dodge_enabled = false

# Every stat _apply_glint_node_effect() can touch — no mixed sources here,
# safe to hard-reset. Shared by reset() and apply_respec().
func _reset_glint_skill_stats() -> void:
	glint_hp_bonus = 0.0
	glint_weapon_dmg_bonus = 0.0
	glint_crit_chance = 0.0
	glint_crit_dmg_mult = 1.5
	glint_armor_ignore_chance = 0.0
	glint_fresh_weapon_dmg = 0.0
	glint_herb_lifesteal = 0.0
	glint_burn_bonus = 0.0
	glint_slow_pct = 0.0
	glint_toxic_bonus = 0.0
	glint_phantom_pct = 0.0

func _ready() -> void:
	inventory_slots.resize(25)
	quickslot_slots.resize(10)
	for i in 25:
		inventory_slots[i] = {"item": "", "count": 0}
	for i in 10:
		quickslot_slots[i] = {"item": "", "count": 0}

func add_item(item_id: String) -> bool:
	# Quickslots first — a matching stack there, then an empty quickslot —
	# only falls through to the main inventory once the quickslots are full.
	for slot in quickslot_slots:
		if slot["item"] == item_id and slot["count"] < MAX_STACK:
			slot["count"] += 1
			return true
	for slot in quickslot_slots:
		if slot["item"] == "":
			slot["item"] = item_id
			slot["count"] = 1
			return true
	for slot in inventory_slots:
		if slot["item"] == item_id and slot["count"] < MAX_STACK:
			slot["count"] += 1
			return true
	for slot in inventory_slots:
		if slot["item"] == "":
			slot["item"] = item_id
			slot["count"] = 1
			return true
	return false

# Inventory-only variant of add_item() — for pickups that should never land
# in a quickslot in the first place (lore notes, future key items), instead
# of relying on the quickslots-happen-to-be-full fallthrough add_item() uses.
func add_item_to_inventory(item_id: String) -> bool:
	for slot in inventory_slots:
		if slot["item"] == item_id and slot["count"] < MAX_STACK:
			slot["count"] += 1
			return true
	for slot in inventory_slots:
		if slot["item"] == "":
			slot["item"] = item_id
			slot["count"] = 1
			return true
	return false

# Fully clears the given tree: refunds every invested SP, reverses every
# stat those levels granted, and resets max_hp by exactly what Vitality
# contributed (not a hard reset — leveling's own +5/level must survive).
func apply_respec(item_id: String) -> void:
	if not RESPEC_REGISTRY.has(item_id):
		return
	if RESPEC_REGISTRY[item_id] == "elana":
		max_hp -= get_skill_level("vitality") * 15
		var refund = 0
		for node_id in skill_tree_levels.keys():
			if node_id != "air_dash_node":  # always owned, never actually spent
				refund += skill_tree_levels[node_id]
		sp += refund
		skill_tree_levels.clear()
		skill_tree_levels["air_dash_node"] = 1
		_reset_elana_skill_stats()
		hp = min(hp, max_hp)
	else:
		var refund = 0
		for lvl in glint_skill_tree_levels.values():
			refund += lvl
		glint_sp += refund
		glint_skill_tree_levels.clear()
		_reset_glint_skill_stats()

func xp_to_next() -> int:
	return level * 100

func gain_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		sp += 2
		glint_sp += 2
		max_hp += 5
		hp = max_hp

# Dev cheat — jumps straight to level 100, granting the same per-level
# rewards gain_xp() would (SP/max_hp), without looping through actual XP.
func dev_set_max_level() -> void:
	while level < 100:
		level += 1
		sp += 2
		glint_sp += 2
		max_hp += 5
	xp = 0
	hp = max_hp

# Dev cheat — the inverse of dev_set_max_level()/dev_max_all_skills():
# back to level 1, xp/sp/glint_sp zeroed, every skill point unspent and
# every skill-derived stat cleared. Same skill_tree_levels/glint_skill_
# tree_levels/_reset_*_skill_stats() pattern reset() and apply_respec()
# already use — deliberately narrower than reset() itself, though: this
# only touches level/xp/hp/skills, not inventory/unlocks/room_state/save
# data, so it's a level-and-skills-only rollback, not a fresh new game.
func dev_reset_to_level_1() -> void:
	level = 1
	xp = 0
	max_hp = 100
	hp = 100
	sp = 0
	glint_sp = 0
	skill_tree_levels.clear()
	skill_tree_levels["air_dash_node"] = 1  # always owned, not spent from SP
	glint_skill_tree_levels.clear()
	_reset_elana_skill_stats()
	_reset_glint_skill_stats()

func get_attack_damage() -> int:
	return 10 + (level - 1)

# Universal Elemental Resist (elem_resist node) always applies. On top of that,
# the matching herb grants a flat baseline + its Potency skill scaling — the
# "same-element = reduced" rule established for Elemander, made real here.
func get_defense() -> int:
	return defense + (HOLLOWSCALE_ARMOR_BONUS if hollowscale_unlocked else 0)

func get_elemental_resist_for(element: String) -> float:
	var resist = elemental_resist + (ELEMENTAL_GOLEM_RESIST_BONUS if elemental_golem_defeated else 0.0)
	if active_herb != null:
		match element:
			"fire":
				if active_herb.item_id == "herbElementalFire":
					resist += HERB_ELEMENT_RESIST_BASELINE + fire_potency_resist
			"frost":
				if active_herb.item_id == "herbElementalFrost":
					resist += HERB_ELEMENT_RESIST_BASELINE + frost_potency_resist
			"elec":
				if active_herb.item_id == "herbElementalElec":
					resist += HERB_ELEMENT_RESIST_BASELINE + elec_potency_resist
	return clamp(resist, 0.0, 0.95)

func get_magic_damage() -> int:
	return int(float(10 + (level - 1)) * (1.0 + elemental_dmg_bonus))

func get_weapon_power() -> float:
	var power = weapon_power
	if glint_fresh_weapon_dmg > 0.0 and current_weapon != "fist" \
			and glint_hp > 0.0 \
			and glint_hp > glint_max_hp * (1.0 - FRESH_WEAPON_HIT_FRACTION):
		power *= 1.0 + glint_fresh_weapon_dmg
	return power

func apply_herb(item_id: String) -> void:
	if not HERB_REGISTRY.has(item_id):
		return
	var herb = HERB_REGISTRY[item_id].new()
	if active_herb != null:
		if active_herb.item_id == item_id:
			herb_timer += herb.duration + herb_duration_bonus
			herb_max_timer = herb_timer
			print("[herb] stacked %s | timer: %.1fs" % [item_id, herb_timer])
			return
		active_herb.remove_effect()
	active_herb = herb
	herb_timer = herb.duration + herb_duration_bonus
	herb_max_timer = herb_timer
	herb.apply_effect()
	print("[herb] applied %s | timer: %.1fs" % [item_id, herb_timer])

func _apply_weapon_stats(weapon_id: String) -> void:
	var data = WEAPON_DATA[weapon_id]
	current_weapon = weapon_id
	weapon_attack_speed = data["attack_speed"]
	weapon_knockback_x = data["knockback_x"]
	weapon_knockback_y = data["knockback_y"]
	weapon_has_stun = data["has_stun"]
	weapon_stun_duration = data["stun_duration"]
	weapon_swing_window = data["swing_window"]
	weapon_heavy_multiplier = data["heavy_multiplier"]
	weapon_power = data["weapon_power"]
	weapon_base_cooldown = data["weapon_base_cooldown"]
	weapon_color = data["color"]
	weapon_hitbox_size = data["hitbox_size"]

func equip_weapon(weapon_id: String) -> void:
	if not WEAPON_DATA.has(weapon_id):
		return
	_apply_weapon_stats(weapon_id)

# Everything that clears when the weapon form ends, in one place
func _clear_weapon_state() -> void:
	glint_hp = 0.0
	glint_max_hp = 0.0
	transform_delay_timer = 0.0
	glint_overcharge_stacks = 0
	_apply_weapon_stats("fist")

func cancel_ore() -> void:
	_clear_weapon_state()

func cancel_herb() -> void:
	if active_herb != null:
		active_herb.remove_effect()
		active_herb = null
	herb_timer = 0.0
	herb_max_timer = 0.0

# Glint's max HP — one universal pool, grows from character level and from
# the Ore Mastery skill. Independent of which weapon is equipped.
func get_glint_max_hp() -> float:
	return GLINT_BASE_HP + float(level - 1) * GLINT_HP_PER_LEVEL + glint_hp_bonus

# How much HP a single hit costs Glint with the currently equipped weapon —
# 0 for fist (no weapon, nothing to cost).
func get_weapon_hit_cost(is_heavy: bool) -> float:
	if not WEAPON_HIT_COST.has(current_weapon):
		return 0.0
	var costs = WEAPON_HIT_COST[current_weapon]
	return costs["heavy"] if is_heavy else costs["light"]

func apply_ore(item_id: String) -> void:
	if not ORE_REGISTRY.has(item_id):
		return
	var weapon_id = ORE_REGISTRY[item_id]
	if current_weapon != weapon_id or glint_hp <= 0.0:
		glint_overcharge_stacks = 0
		equip_weapon(weapon_id)
		transform_delay_timer = TRANSFORM_DELAY * (1.0 - 0.5 * get_glint_skill_level("g_weapon_mastery"))
	else:
		# Overcharge — re-feeding the same ore while still active builds a damage stack
		glint_overcharge_stacks = min(glint_overcharge_stacks + 1, get_glint_skill_level("g_overcharge"))
	glint_max_hp = get_glint_max_hp()
	glint_hp = glint_max_hp
	print("[ore] fed %s | Glint HP: %.0f | overcharge: %d" % [weapon_id, glint_hp, glint_overcharge_stacks])

# Called once per enemy landed on (or once per successful block) — Glint
# takes damage, but a swing already in progress always finishes at full
# power even if this drops her HP to/below zero (see check_weapon_depletion).
func glint_take_hit(cost: float = 1.0) -> void:
	if current_weapon == "fist":
		return
	glint_hp -= cost

# Called after a swing, block, or thrown-chain hit fully resolves — reverts
# to fist if Glint ran out of HP during it, instead of interrupting mid-swing.
func check_weapon_depletion() -> void:
	if current_weapon != "fist" and glint_hp <= 0.0:
		_clear_weapon_state()
		print("[ore] Glint HP depleted | reverted to fist")

func clear_combat_stacks() -> void:
	glint_combo_stacks = 0
	glint_combo_timer = 0.0
	glint_exec_stacks = 0
	glint_exec_timer = 0.0

func glint_register_hit() -> void:
	if current_weapon == "fist" or get_glint_skill_level("g_combo_strike") <= 0:
		return
	glint_combo_stacks = min(glint_combo_stacks + 1, get_glint_skill_level("g_combo_strike"))
	glint_combo_timer = COMBO_WINDOW

func glint_register_kill() -> void:
	if current_weapon == "fist" or get_glint_skill_level("g_executioner") <= 0:
		return
	glint_exec_stacks = min(glint_exec_stacks + 1, EXEC_MAX_STACKS)
	glint_exec_timer = EXEC_WINDOW

func _process(delta: float) -> void:
	transform_delay_timer = max(0.0, transform_delay_timer - delta)
	if glint_combo_timer > 0.0:
		glint_combo_timer -= delta
		if glint_combo_timer <= 0.0:
			glint_combo_stacks = 0
	if glint_exec_timer > 0.0:
		glint_exec_timer -= delta
		if glint_exec_timer <= 0.0:
			glint_exec_stacks = 0
	if active_herb != null:
		herb_timer -= delta * herb_drain_multiplier
		if herb_timer <= 0.0:
			active_herb.remove_effect()
			active_herb = null
			herb_timer = 0.0
			herb_drain_multiplier = 1.0

func reset() -> void:
	level = 1
	max_hp = 100
	hp = 100
	xp = 0
	sp = 0
	glint_sp = 0
	defense = 0
	dodge_chance = 0.0
	if active_herb != null:
		active_herb.remove_effect()
		active_herb = null
	herb_timer = 0.0
	herb_max_timer = 0.0
	elemental_active = false
	elemental_element = ""
	damage_multiplier = 1.0
	_apply_weapon_stats("fist")
	glint_hp = 0.0
	glint_max_hp = 0.0
	hp_regen = 0.0
	hp_regen_herb_bonus = 0.0
	attack_speed_herb_bonus = 0
	move_speed_herb_bonus = 0.0
	spawn_point_id = "SpawnDefault"
	respawn_scene = ""
	active_ritual_node = ""
	respawn_position = Vector2.ZERO
	fog_mask_png = ""
	just_died = false
	use_default_spawn = true
	room_state = {}
	seen_items = {}
	shop_purchases = {}
	for i in 25:
		inventory_slots[i] = {"item": "", "count": 0}
	for i in 10:
		quickslot_slots[i] = {"item": "", "count": 0}
	skill_tree_levels.clear()
	skill_tree_levels["air_dash_node"] = 1  # always owned, not spent from SP
	glint_skill_tree_levels.clear()
	_reset_elana_skill_stats()
	_reset_glint_skill_stats()
	transform_delay_timer = 0.0
	glint_overcharge_stacks = 0
	clear_combat_stacks()
	elemander_pads_unlocked = false
	golden_cloak_unlocked = false
	ant_queen_defeated = false
	elemental_golem_defeated = false
	hollowscale_unlocked = false
	hollowscale_cooldown = 0.0
	danger_sense_unlocked = false
	danger_sense_cooldown = 0.0
	danger_sense_active_timer = 0.0
	dev_no_cooldowns = false
	air_dash_enabled = false
	stone_being_met = false
	received_stone_being_power = false
	glint_scout_tutorial_done = false
	air_dash_tutorial_done = false
	camera_pan_intro_done = false
	reset_boss_camera()
	herb_pickup_hint_shown = false
	ore_break_hint_shown = false
	glint_scout_return_hint_shown = false
	last_stand_cd = 0.0
	passive_shield_hp = 0.0

# ── Save / Load ──────────────────────────────────────────────────────────────
# Single slot, autosaved at Ritual Nodes only (no manual save). Only "source
# of truth" progress is persisted — most combat stat bonuses (wall_jump_enabled,
# elemental_dmg_bonus, glint_hp_bonus, etc.) are *derived* from skill_tree_levels
# / glint_skill_tree_levels via _apply_skill_node_effect()/_apply_glint_node_effect(),
# so load_game() rebuilds them by replaying those exactly like dev_max_all_skills()
# does, instead of hand-saving ~50 redundant fields that could drift out of sync.
const SAVE_PATH := "user://savegame.json"

func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game() -> void:
	var data := {
		"level": level, "xp": xp, "sp": sp, "glint_sp": glint_sp,
		"hp": hp,
		"inventory_slots": inventory_slots, "quickslot_slots": quickslot_slots,
		"skill_tree_levels": skill_tree_levels, "glint_skill_tree_levels": glint_skill_tree_levels,
		"air_dash_enabled": air_dash_enabled,
		"elemander_pads_unlocked": elemander_pads_unlocked,
		"golden_cloak_unlocked": golden_cloak_unlocked,
		"hollowscale_unlocked": hollowscale_unlocked,
		"ant_queen_defeated": ant_queen_defeated,
		"elemental_golem_defeated": elemental_golem_defeated,
		"danger_sense_unlocked": danger_sense_unlocked,
		"spawn_point_id": spawn_point_id, "respawn_scene": respawn_scene,
		"respawn_position": [respawn_position.x, respawn_position.y],
		"active_ritual_node": active_ritual_node,
		"default_scene": default_scene, "default_spawn_id": default_spawn_id,
		"room_state": room_state, "seen_items": seen_items, "shop_purchases": shop_purchases,
		"stone_being_met": stone_being_met,
		"received_stone_being_power": received_stone_being_power,
		"glint_scout_tutorial_done": glint_scout_tutorial_done,
		"air_dash_tutorial_done": air_dash_tutorial_done,
		"camera_pan_intro_done": camera_pan_intro_done,
		"herb_pickup_hint_shown": herb_pickup_hint_shown,
		"ore_break_hint_shown": ore_break_hint_shown,
		"glint_scout_return_hint_shown": glint_scout_return_hint_shown,
		"fog_mask_png": fog_mask_png,
	}
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("GameData.save_game(): failed to open save file for writing")
		return
	file.store_string(JSON.stringify(data))
	file.close()

# Returns true on success. Leaves state untouched (returns false) if there's
# no save file or it's unreadable/corrupt.
func load_game() -> bool:
	if not has_save_file():
		return false
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var text = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false

	reset()

	level = parsed.get("level", level)
	xp = parsed.get("xp", xp)
	sp = parsed.get("sp", sp)
	glint_sp = parsed.get("glint_sp", glint_sp)
	inventory_slots = parsed.get("inventory_slots", inventory_slots)
	quickslot_slots = parsed.get("quickslot_slots", quickslot_slots)
	skill_tree_levels = parsed.get("skill_tree_levels", skill_tree_levels)
	glint_skill_tree_levels = parsed.get("glint_skill_tree_levels", glint_skill_tree_levels)
	air_dash_enabled = parsed.get("air_dash_enabled", air_dash_enabled)
	elemander_pads_unlocked = parsed.get("elemander_pads_unlocked", elemander_pads_unlocked)
	golden_cloak_unlocked = parsed.get("golden_cloak_unlocked", golden_cloak_unlocked)
	hollowscale_unlocked = parsed.get("hollowscale_unlocked", hollowscale_unlocked)
	ant_queen_defeated = parsed.get("ant_queen_defeated", ant_queen_defeated)
	elemental_golem_defeated = parsed.get("elemental_golem_defeated", elemental_golem_defeated)
	danger_sense_unlocked = parsed.get("danger_sense_unlocked", danger_sense_unlocked)
	spawn_point_id = parsed.get("spawn_point_id", spawn_point_id)
	respawn_scene = parsed.get("respawn_scene", respawn_scene)
	var pos_arr = parsed.get("respawn_position", null)
	if pos_arr is Array and pos_arr.size() == 2:
		respawn_position = Vector2(pos_arr[0], pos_arr[1])
	fog_mask_png = parsed.get("fog_mask_png", fog_mask_png)
	active_ritual_node = parsed.get("active_ritual_node", active_ritual_node)
	default_scene = parsed.get("default_scene", default_scene)
	default_spawn_id = parsed.get("default_spawn_id", default_spawn_id)
	room_state = parsed.get("room_state", room_state)
	seen_items = parsed.get("seen_items", seen_items)
	shop_purchases = parsed.get("shop_purchases", shop_purchases)
	stone_being_met = parsed.get("stone_being_met", stone_being_met)
	received_stone_being_power = parsed.get("received_stone_being_power", received_stone_being_power)
	glint_scout_tutorial_done = parsed.get("glint_scout_tutorial_done", glint_scout_tutorial_done)
	air_dash_tutorial_done = parsed.get("air_dash_tutorial_done", air_dash_tutorial_done)
	camera_pan_intro_done = parsed.get("camera_pan_intro_done", camera_pan_intro_done)
	herb_pickup_hint_shown = parsed.get("herb_pickup_hint_shown", herb_pickup_hint_shown)
	ore_break_hint_shown = parsed.get("ore_break_hint_shown", ore_break_hint_shown)
	glint_scout_return_hint_shown = parsed.get("glint_scout_return_hint_shown", glint_scout_return_hint_shown)

	# Rebuild every derived stat from the restored skill trees — same replay
	# technique dev_max_all_skills() uses (reset to baseline, then re-spend).
	_reset_elana_skill_stats()
	_reset_glint_skill_stats()
	for node_id in skill_tree_levels.keys():
		for i in int(skill_tree_levels[node_id]):
			_apply_skill_node_effect(node_id)
	for node_id in glint_skill_tree_levels.keys():
		for i in int(glint_skill_tree_levels[node_id]):
			_apply_glint_node_effect(node_id)

	hp = min(int(parsed.get("hp", max_hp)), max_hp)
	_apply_weapon_stats("fist")
	return true

# Shared by title_screen.gd's Continue and elana.gd's die() — both need to
# load the last save, then land the player back at wherever they last saved
# (a Ritual Node's respawn_scene/position if one's set, otherwise a fresh
# default_scene spawn), and queue that scene for loading_screen.tscn to pick
# up. Used to be two near-identical hand-copies of this exact decision tree;
# extracted here so a future change to the load/respawn logic only needs to
# happen once. Deliberately doesn't touch the scene tree itself (HUD refresh
# and the actual change_scene_to_file call stay with each caller) since one
# needs the scene change deferred and the other doesn't.
func load_and_prepare_respawn() -> bool:
	if not load_game():
		return false
	if respawn_scene != "":
		# reset() (called inside load_game()) leaves use_default_spawn true —
		# clear it so the next scene's spawn check falls through to
		# just_died instead, landing the player at respawn_position.
		use_default_spawn = false
		just_died = true
	else:
		use_default_spawn = true
	pending_scene_load = respawn_scene if respawn_scene != "" else default_scene
	return true

# Lives here (AutoLoad) so the unfreeze survives scene changes — if Elana owns
# the coroutine and is freed mid-hitstop, time_scale stays 0 forever.
func hitstop(duration: float = 0.07) -> void:
	Engine.time_scale = 0.0
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0

func calc_damage(raw: float, defense: float) -> int:
	return max(1, int(raw * 100.0 / (defense + 100.0)))

func make_styled_button(label: String, min_size: Vector2 = Vector2(200, 36), font_size: int = 14) -> Button:
	var btn = Button.new()
	btn.text = label
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.1, 0.14)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.32, 0.32, 0.44)
	normal.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", normal)
	var hover = normal.duplicate()
	hover.bg_color = Color(0.16, 0.16, 0.22)
	hover.border_color = Color(0.58, 0.58, 0.78)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed_style = normal.duplicate()
	pressed_style.bg_color = Color(0.08, 0.08, 0.11)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_color_override("font_color", Color(0.92, 0.87, 0.72))
	btn.add_theme_font_size_override("font_size", font_size)
	return btn

var window_mode: int = 0
var window_resolution: Vector2i = Vector2i(1280, 720)
const RESOLUTIONS: Array = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const RESOLUTION_LABELS: Array = ["1280×720 (720p)", "1600×900 (900p)", "1920×1080 (1080p)"]

func set_window_mode(mode: int) -> void:
	window_mode = mode
	match mode:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(window_resolution)
			var screen_size = DisplayServer.screen_get_size()
			DisplayServer.window_set_position((screen_size - window_resolution) / 2)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func set_window_resolution(res: Vector2i) -> void:
	window_resolution = res
	if window_mode == 0:
		DisplayServer.window_set_size(res)
		var screen_size = DisplayServer.screen_get_size()
		DisplayServer.window_set_position((screen_size - res) / 2)

func make_stun_indicator() -> Label:
	var label = Label.new()
	label.text = "★★★"
	label.position = Vector2(-16, -40)
	label.z_index = 5
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.2))
	return label

# Same-frame handoff, not saved: elana.gd's crit-rolling functions set this
# explicitly (true or false) right before calling enemy.on_hit(), and
# hit_handler.gd's _apply_damage() reads-and-clears it the instant it spawns
# the resulting damage number — narrower than threading an is_crit param
# through every on_hit()/on_elemental_hit() implementer project-wide.
var last_hit_is_crit: bool = false
const CRIT_DAMAGE_COLOR: Color = Color(1.0, 0.9, 0.15)

func spawn_damage_number(amount: int, pos: Vector2, color: Color = Color.WHITE) -> void:
	spawn_float_text(str(amount), pos, color)

# Consume-and-clear last_hit_is_crit and spawn the resulting number in one
# call — hit_handler.gd, hollowfang.gd, and elemander.gd each independently
# hand-copied this exact "yellow if crit, else white, then clear the flag"
# sequence (any enemy not routed through hit_handler.gd needed its own
# copy or the flag would leak into whatever gets hit next). One shared
# place now, so a future change to crit-color logic only needs to happen
# once instead of three times staying in sync by hand.
func spawn_crit_aware_damage_number(amount: int, pos: Vector2) -> void:
	var color: Color = CRIT_DAMAGE_COLOR if last_hit_is_crit else Color.WHITE
	last_hit_is_crit = false
	spawn_damage_number(amount, pos, color)

func spawn_float_text(text: String, pos: Vector2, color: Color = Color.WHITE) -> void:
	var label = Label.new()
	label.text = text
	label.position = pos + Vector2(-8, -24)
	label.z_index = 10
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	get_tree().current_scene.add_child(label)
	var tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", pos.y - 54, 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.7)
	tween.chain().tween_callback(label.queue_free)

func mark_removed(scene_path: String, node_name: String) -> void:
	if not room_state.has(scene_path):
		room_state[scene_path] = {}
	room_state[scene_path][node_name] = true

func is_removed(scene_path: String, node_name: String) -> bool:
	if not room_state.has(scene_path):
		return false
	return room_state[scene_path].has(node_name)

# Reuses room_state's existing per-scene/per-node dict (same one is_removed/
# mark_removed use, namespaced with a prefix so it can't collide with an
# ordinary "destroyed" entry) — rolled once per node, cached here so
# re-entering the room doesn't re-roll it, cleared on reset() (New Game)
# same as everything else room_state tracks, and persists across Continue
# since room_state is already part of the save data.
func get_random_choice(scene_path: String, node_name: String, choice_count: int) -> int:
	if not room_state.has(scene_path):
		room_state[scene_path] = {}
	var key = "RandomChoice::" + node_name
	if not room_state[scene_path].has(key):
		room_state[scene_path][key] = randi() % choice_count
	return room_state[scene_path][key]

# Per-shop-instance purchase counters (e.g. Moleman's limited ore/herb stock).
# Persists across trade sessions, doesn't replenish.
func get_purchased_count(scene_path: String, key: String) -> int:
	if not shop_purchases.has(scene_path):
		return 0
	return shop_purchases[scene_path].get(key, 0)

func add_purchased_count(scene_path: String, key: String, amount: int) -> void:
	if not shop_purchases.has(scene_path):
		shop_purchases[scene_path] = {}
	shop_purchases[scene_path][key] = get_purchased_count(scene_path, key) + amount

# Returns true only the first time a given item_id is passed in.
func mark_item_seen(item_id: String) -> bool:
	if seen_items.has(item_id):
		return false
	seen_items[item_id] = true
	return true
