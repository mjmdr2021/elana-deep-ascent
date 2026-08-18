# Central home for every cutscene's dialogue lines — pure data, no logic.
# Referenced from the actual cutscene scripts via preload(), same pattern
# already used elsewhere in the project (e.g. glint.gd pulling a constant off
# base_enemy.gd). Keeping content here instead of inline makes it easy to
# read/edit the full script at a glance, and is the natural place to add
# localization/culture handling later (e.g. swapping these for tr() keys)
# without having to go hunting through cutscene logic first.

# ── Opening Cutscene (elana.gd, _start_intro_cutscene) ──────────────────────
const INTRO_PART1: Array = [
	{"speaker": "Elana", "text": "Where am I?"},
	{"speaker": "Elana", "text": "I have to go back to the colony."},
]
const INTRO_PART2: Array = [
	{"speaker": "Elana", "text": "No! I'm trapped!"},
]
const INTRO_PART3A: Array = [
	{"speaker": "Elana", "text": "Wait... what is this?"},
	{"speaker": "Elana", "text": "Hello, what's your name?"},
]
# Glint "speaks" — the speaker_nodes map at the call site floats this over
# her instead of Elana.
const INTRO_PART3B: Array = [
	{"speaker": "Glint", "text": "Meoww meowww"},
	{"speaker": "Elana", "text": "Sorry, I can't understand you."},
	{"speaker": "Elana", "text": "Well, you're shining so bright."},
	{"speaker": "Elana", "text": "I guess I'll call you Glint."},
	{"speaker": "Glint", "text": "Meow meowww"},
	{"speaker": "Elana", "text": "Do you wanna come with me? To find our way out?"},
	{"speaker": "Glint", "text": "Meowwww"},
	{"speaker": "Elana", "text": "Come on Glint, let's find another way."},
]

# ── Stone Being (stone_being.gd) ─────────────────────────────────────────────
# Split around the "*elana looks around*" staging beat (turns to face left
# then right without Glint moving from her locked spot) that happens between
# these two.
const STONE_BEING_INTRO_A: Array = [
	{"speaker": "Stone Being", "text": "Human..."},
	{"speaker": "Elana", "text": "What was that?"},
]
const STONE_BEING_INTRO_B: Array = [
	{"speaker": "Stone Being", "text": "Did you come from the surface?"},
	{"speaker": "Elana", "text": "Did this stone face just talk to me?"},
	{"speaker": "Stone Being", "text": "I need your help."},
	{"speaker": "Stone Being", "text": "For this corruption to end."},
	{"speaker": "Elana", "text": "What? Why me?"},
	{"speaker": "Elana", "text": "Can't you do it yourself?"},
	{"speaker": "Stone Being", "text": "I can't. I've been affected by the corruption in this world."},
	{"speaker": "Stone Being", "text": "I need you to bring me the Corruption Core."},
	{"speaker": "Stone Being", "text": "It is found in the deepest depths of this world."},
	{"speaker": "Elana", "text": "How can I even do that?"},
	{"speaker": "Elana", "text": "I can't even find my way out!"},
	{"speaker": "Stone Being", "text": "Even if you have returned to the surface, the corruption will still spread and destroy the lands."},
	{"speaker": "Stone Being", "text": "Eventually, the whole world."},
	{"speaker": "Stone Being", "text": "The only way to stop it is to bring me the Corruption Core, so that I can destroy it."},
	{"speaker": "Elana", "text": "I guess you are right..."},
	{"speaker": "Elana", "text": "But, how can I even do that?"},
	{"speaker": "Elana", "text": "I'm just a girl."},
	{"speaker": "Stone Being", "text": "Do not worry, human."},
	{"speaker": "Stone Being", "text": "I will share some of my power with you."},
	{"speaker": "Stone Being", "text": "You will be capable of bringing the core back."},
	{"speaker": "Stone Being", "text": "And as for your companion,"},
	{"speaker": "Stone Being", "text": "I shall bestow my power onto it,"},
	{"speaker": "Stone Being", "text": "to help you on your journey."},
]
const STONE_BEING_REACTION: Array = [
	{"speaker": "Elana", "text": "Wait, what's happening?"},
]
const STONE_BEING_POWER_GRANTED: Array = [
	{"speaker": "Stone Being", "text": "Now you have the power to defeat anything that comes in your way."},
	{"speaker": "Elana", "text": "Defeat anything? Are there monsters?"},
	{"speaker": "Stone Being", "text": "The core's corruption has spread to the underground dwellers of this world."},
	{"speaker": "Stone Being", "text": "You may need to defeat them in order to get to the core."},
	{"speaker": "Elana", "text": "How do I even know how to get to the core?"},
	{"speaker": "Stone Being", "text": "The deep hole to our right leads straight into the core,"},
	{"speaker": "Stone Being", "text": "but it's blocked by multiple strong corrupted creatures."},
	{"speaker": "Stone Being", "text": "You may need to find another route, and at the same time,"},
	{"speaker": "Stone Being", "text": "strengthen yourself so you can defeat these creatures."},
	{"speaker": "Stone Being", "text": "Not now though, you are still weak."},
	{"speaker": "Elana", "text": "So, if I jumped in there..."},
	{"speaker": "Elana", "text": "I'll surely die?"},
	{"speaker": "Stone Being", "text": "Definitely."},
	{"speaker": "Elana", "text": "Okay then, I don't want to die.."},
]
const STONE_BEING_AIR_DASH_GRANT: Array = [
	{"speaker": "Stone Being", "text": "I also grant you the ability"},
	{"speaker": "Stone Being", "text": "to air dash!"},
	{"speaker": "Stone Being", "text": "It will be handy on your journey."},
	{"speaker": "Elana", "text": "Thanks? I guess?"},
	{"speaker": "Stone Being", "text": "The fate of the world is on your hands now."},
	{"speaker": "Elana", "text": "I guess I have no choice."},
	{"speaker": "Elana", "text": "Let's do this, Glint!"},
	{"speaker": "Elana", "text": "Let's save the world!"},
]

# ── DialogMarker — Glint scout (X) tutorial (dialog_marker.gd) ──────────────
const SCOUT_TUTORIAL: Array = [
	{"speaker": "Elana", "text": "Woah, this is a dark cave."},
	{"speaker": "Elana", "text": "I can't see where we would land."},
	{"speaker": "Elana", "text": "Hmmm..."},
	{"speaker": "Elana", "text": "Hey Glint,"},
	{"speaker": "Elana", "text": "can you help me and"},
	{"speaker": "Elana", "text": "scout the area with your light?"},
]

# ── DialogMarker — Air Dash tutorial (dialog_marker.gd) ─────────────────────
const AIR_DASH_TUTORIAL: Array = [
	{"speaker": "Elana", "text": "I think this is the hole I should not fall into."},
	{"speaker": "Elana", "text": "And it's too far to just jump."},
	{"speaker": "Elana", "text": "I should try the air dash."},
]

# ── LoreNotes — Ritual Node explanation (lore_notes.gd) ─────────────────────
const LORE_RITUAL_NODE_EXPLANATION: Array = [
	{"speaker": "Elana", "text": "Oh look, Glint, a note."},
	{"speaker": "Elana", "text": "It's like it was torn from a notebook."},
	{"speaker": "Elana", "text": "It says..."},
	{"speaker": "Elana", "text": "These \"Ritual Nodes\" that light up—"},
	{"speaker": "Elana", "text": "they apparently store my soul."},
	{"speaker": "Elana", "text": "So when I die, these things revive me,"},
	{"speaker": "Elana", "text": "and I start all over again."},
]

# ── LoreWoodenSign (lore_wooden_sign.gd) ─────────────────────────────────────
const LORE_WOODEN_SIGN: Array = [
	{"speaker": "Elana", "text": "It's a sign."},
	{"speaker": "Elana", "text": "It says..."},
	{"speaker": "Elana", "text": "\"Cave entrance blocked.\""},
	{"speaker": "Elana", "text": "\"Infested with ants...\""},
	{"speaker": "Elana", "text": "...."},
	{"speaker": "Elana", "text": "Why would they block it because of ants?"},
]

# ── Moleman (moleman.gd) ─────────────────────────────────────────────────────
# talk_lines is still @export on moleman.gd — this is only the default value
# for the first placed Moleman; other instances can override it entirely in
# the Inspector without touching this file.
const MOLEMAN_FIRST_TALK: Array = [
	{"speaker": "Moleman", "text": "Hi Human"},
	{"speaker": "Elana", "text": "Woah, you can talk?!"},
	{"speaker": "Moleman", "text": "What do you think we moleman are?"},
	{"speaker": "Moleman", "text": "Savages?!"},
	{"speaker": "Moleman", "text": "We learned from the books"},
	{"speaker": "Moleman", "text": "that you humans abandoned"},
	{"speaker": "Moleman", "text": "Now we know Economics!"},
	{"speaker": "Moleman", "text": "What do you want?"},
	{"speaker": "Elana", "text": "I actually want to pass through"},
	{"speaker": "Elana", "text": "but there's a hard rock blocking the way"},
	{"speaker": "Moleman", "text": "Oh. Those rocks can be destroyed"},
	{"speaker": "Moleman", "text": "We usually use a big hammer"},
	{"speaker": "Moleman", "text": "to destroy those blockers"},
	{"speaker": "Elana", "text": "Oh, I see"},
	{"speaker": "Moleman", "text": "I wouldn't proceed going there anyway"},
	{"speaker": "Moleman", "text": "there's a big scary snake monster in there"},
	{"speaker": "Moleman", "text": "it prevents me from trading to other molemen"},
	{"speaker": "Elana", "text": "I'll see what I can do"},
]
const MOLEMAN_REPEAT_TALK: Array = [
	{"speaker": "Moleman", "text": "Be careful human"},
]
