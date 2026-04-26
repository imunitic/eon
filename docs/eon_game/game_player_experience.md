# Eon Player Experience Principles

These principles guide every design decision in Eon. When in doubt about a mechanic, feature, or tuning call — check it against these first.

---

## Core Philosophy

> **Eon is built for players who want to enjoy a game, not endure one.**

The challenge in Eon lives in combat, build decisions, and endgame progression — not in navigating friction, punishing ignorance, or wasting the player's time.

---

## 1. The World Is Worth Traversing

Eon has **no teleports of any kind** between maps or zones. The world is meant to be walked through, not skipped.

- Movement speed scales with level (see `game_mechanics.md`) so traversal always feels fluid.
- Map design must earn the player's attention — interesting environments, not corridor spam.
- **Intra-map checkpoints** exist within maps, allowing fast travel to previously reached points *inside* the current map only. This respects player time without undermining the no-teleport philosophy.

The rule: **teleports exist only within a map you have already explored, never as a shortcut to skip content.**

---

## 2. Information Is Not the Enemy

Eon does not hide information from players as a difficulty mechanic.

- **Mob positions are always visible on the map as dots** — players know what they are walking into and can make tactical decisions accordingly. Deaths feel like build or stat failures, not information failures.
- **Fog of war is removed in endgame.** It is interesting exactly once per map. In endgame where players run the same map tiers repeatedly, fog of war wastes time without adding meaningful challenge.
- Stats, mitigation values, and CC durations are surfaced clearly in the UI where possible.

---

## 3. Early Game Is an Empowerment Fantasy

The early game exists to let players fall in love with their build — not to test them before they are ready.

- Pack sizes are small and aggro is staggered — players pull manageable groups, not entire screens.
- Magic mobs in early zones have mild affixes only (movement speed, extra HP) — nothing that creates chaos before the player understands the game.
- Mobs do not path around the player to cut off escape routes early on.
- Elemental damage is tuned for near-zero resistance early — it should feel threatening and readable, not instant death.
- The challenge ramp is deliberate:

| Phase | Feel |
|:------|:-----|
| Early game | Generous, exploratory, forgiving |
| Midgame | Tightening — build decisions start mattering |
| Late game / Maps | Unforgiving — every stat counts |
| Uber content | Humbling — even near-immortal characters are tested |

---

## 4. Gear Should Amplify, Not Gate

Players should never feel stuck or unplayable because they haven't found a specific item yet.

- Core stats (movement speed, defense, elemental resistance baseline) scale with level — gear amplifies what you already have, it does not replace a missing floor.
- No single item slot should be mandatory to function. Boots should make you faster than already good, not make you playable for the first time.
- Crafting is nearly free and encourages experimentation — players are never hoarding materials out of fear.

---

## 5. Power Is the Reward for Investment

Eon does not cap or nerf player power to preserve artificial challenge.

- A fully crafted, deeply optimized character **should** trivialize normal and mid-tier content. That is the reward for the investment.
- The challenge ceiling scales upward — higher map tiers, harder affixes, uber bosses — rather than downward-nerfing the player.
- Achieving near-maximum defenses across all five layers (life, block, resistances, evasion, armor) requires deep crafting investment and is **intentional and celebrated**.

> The game does not stop you from becoming powerful. The hardest content is simply tuned for powerful characters.

---

## 6. Difficulty Is Organic, Not Imposed

Eon has no traditional difficulty modes (Normal / Nightmare / Hell).

- Difficulty emerges from enemy scaling, map tier, and map affixes — not a preset mode selector.
- After level 100, players can optionally raise the world level — increasing monster tier and loot ceiling.
- The player chooses their challenge. Casuals run comfortable tiers. Dedicated players push higher.

> "You don't pick a difficulty — you become the difficulty."

---

## 7. Quests Are About Combat, Not Chores

Eon will never send players on fetch quests, object-smashing runs, or gathering tasks that have nothing to do with killing enemies.

- **All quests are tied to killing something.** If the quest objective exists in the world, it dies when you fight it.
- **No "collect X items from destructible objects"** — smashing crates hoping for a quest drop is not gameplay, it is busywork.
- **No gathering quests** — berry picking, herb collecting, material scrounging belong in a farming sim, not an ARPG.
- **Quest drops and soul collection are auto-picked up** — if killing an enemy is the trigger, the reward should land in your inventory automatically. The player should never have to run around a battlefield clicking corpses to complete an objective.

The rule: **if a quest asks you to collect something, that something comes from a dead enemy and lands in your inventory without extra input.**

> Every moment in Eon should feel like you are playing an action RPG, not doing chores between action RPG sessions.

---

## Summary

| Principle | What It Prevents |
|:----------|:-----------------|
| No teleports + checkpoints | Skipping content while still respecting time |
| Map dots + no endgame fog | Death by ignorance rather than build failure |
| Early game leniency | Punishing players before they understand their build |
| Level-scaling baselines | Mandatory item slots, gear-gating playability |
| Power as reward | Nerfing dedicated players to preserve fake challenge |
| Organic difficulty | Preset mode friction, one-size-fits-all pacing |
| Combat-only quests + auto-pickup | Fetch quests, busywork, clicking corpses to progress |

---

*This document captures the player experience philosophy agreed during Eon's design phase.*
