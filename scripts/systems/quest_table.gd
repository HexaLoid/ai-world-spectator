class_name QuestTable
extends RefCounted

## Simple "kill N of this enemy" quest templates, offered by the Quest
## Giver in a fixed rotation. `target_name` must exactly match an Enemy's
## `enemy_name` (including per-zone overrides like "Dire Wolf"/"Bandit
## Captain"), which is how quest progress is matched against kills without
## needing any new AI targeting logic — the character already fights
## whatever it encounters; this just watches for the right name going by.
const QUESTS := [
	{
		"id": "cull_the_wolves", "name": "Cull the Wolves",
		"target_name": "Wolf", "count": 3,
		"xp_reward": 40, "item_reward": "", "min_level": 1,
	},
	{
		"id": "bandit_trouble", "name": "Bandit Trouble",
		"target_name": "Bandit", "count": 2,
		"xp_reward": 50, "item_reward": "", "min_level": 1,
	},
	{
		"id": "dire_wolf_hunt", "name": "Dire Wolf Hunt",
		"target_name": "Dire Wolf", "count": 4,
		"xp_reward": 70, "item_reward": "leather_armor", "min_level": 2,
	},
	{
		"id": "captains_head", "name": "The Captain's Head",
		"target_name": "Bandit Captain", "count": 1,
		"xp_reward": 120, "item_reward": "iron_sword", "min_level": 2,
	},
	{
		"id": "the_crypt_lord", "name": "The Crypt Lord",
		"target_name": "Crypt Lord", "count": 1,
		"xp_reward": 200, "item_reward": "amulet_of_wrath", "min_level": 3,
	},
]
