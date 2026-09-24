class_name QuestTable
extends RefCounted

## "Kill N of this enemy" quest templates, offered by the Quest Giver in a
## fixed rotation. `target_name` must exactly match an Enemy's `enemy_name`
## (including per-zone overrides like "Dire Wolf"/"Bandit Captain"), which is
## how quest progress is matched against kills without needing any new AI
## targeting logic — the character already fights whatever it encounters;
## this just watches for the right name going by.
##
## `requires` is an array of prerequisite quest ids that must all already be
## in the character's completed_quest_ids before this one is offered, in
## addition to (not instead of) `min_level` gating. This turns the flat
## rotation into two short chains that converge on a shared capstone:
##   cull_the_wolves -> dire_wolf_hunt -\
##                                        -> the_crypt_lord -> hero_of_thornfield
##   bandit_trouble  -> captains_head  -/
## The two intro quests (no `requires`) are always available at level 1, so
## the rotation never stalls with nothing to offer.
const QUESTS := [
	{
		"id": "cull_the_wolves", "name": "Cull the Wolves",
		"target_name": "Wolf", "count": 3,
		"xp_reward": 40, "item_reward": "", "min_level": 1, "requires": [],
	},
	{
		"id": "bandit_trouble", "name": "Bandit Trouble",
		"target_name": "Bandit", "count": 2,
		"xp_reward": 50, "item_reward": "", "min_level": 1, "requires": [],
	},
	{
		"id": "dire_wolf_hunt", "name": "Dire Wolf Hunt",
		"target_name": "Dire Wolf", "count": 4,
		"xp_reward": 70, "item_reward": "leather_armor", "min_level": 2,
		"requires": ["cull_the_wolves"],
	},
	{
		"id": "captains_head", "name": "The Captain's Head",
		"target_name": "Bandit Captain", "count": 1,
		"xp_reward": 120, "item_reward": "iron_sword", "min_level": 2,
		"requires": ["bandit_trouble"],
	},
	{
		"id": "the_crypt_lord", "name": "The Crypt Lord",
		"target_name": "Crypt Lord", "count": 1,
		"xp_reward": 200, "item_reward": "amulet_of_wrath", "min_level": 3,
		"requires": ["dire_wolf_hunt", "captains_head"],
	},
	{
		"id": "hero_of_thornfield", "name": "Hero of Thornfield",
		"target_name": "Crypt Lord", "count": 1,
		"xp_reward": 150, "item_reward": "crown_of_thornfield", "min_level": 3,
		"requires": ["the_crypt_lord"],
	},
]
