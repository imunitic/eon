# 🧙‍♂️ Eon Game Mechanics Discussion (Part 3 – Skills, Crafting, and Itemization)

## 🎯 Skill System Architecture

The goal of the skill system is to keep everything **data-driven**, modular, and consistent with ECS design principles.

Each **skill** is treated as an ECS component, and skill behavior (damage, area, projectile count, etc.) can evolve through **skill levels** or **modifiers**.

### 🧠 Design Notes

- Skills level up through **use** rather than player XP.
- Each skill maintains its own **proficiency rating** which increases whenever the skill successfully hits or executes.
- Leveling follows the same diminishing-returns model used elsewhere for defenses and XP:

  `SkillXPRequired = BaseXP * (1 + L / (K + L))`

- This ensures that skill progression feels consistent with other systems — fast early growth and gradual slowdown.
- Skills may unlock **behavior modifiers** (e.g., “Firebolt splits into 2 projectiles at level 5”) rather than just flat stat increases.

### 🧩 Example ECS Representation

```ocaml
type skill_level = {
  current_xp : float;
  level      : int;
  modifier   : float;
}

type skill = {
  id          : int;
  name        : string;
  level_data  : skill_level;
  on_use      : (world -> entity -> unit);
}
```

The system that manages these would periodically evaluate XP gain, check level thresholds, and apply upgrades via events or commands.

---

## ⚒️ Crafting & Itemization Philosophy

Eon’s itemization is deliberately minimalist — focusing on **player agency** rather than drop RNG.

### 🧱 Core Concepts

- The world only drops **white (base) items**.
- All item advancement is done through **crafting and materials**.
- **Crafting is nearly free**, designed to encourage experimentation rather than hoarding.
- There is no currency or vendor RNG; **materials** act as the universal resource.
- Players can **salvage** unwanted items for materials or extract affixes.
- Affixes are **modular**, attachable, removable, and rerollable.

### 💎 Slot Occupancy Indicators

Items never drop with built-in rarity. Every base arrives as a white shell with eight empty affix slots (4 prefix, 4 suffix). The UI tint simply shows how many of those slots you have filled.

| Color | Slots Occupied | Meaning |
|:------|:----------------|:--------|
| ⚪ White | 0 | Fresh drop — all eight slots open |
| 🔵 Blue | 1 – 4 | Early crafted piece with a few affixes slotted |
| 🟡 Yellow | 5 – 6 | Mid-game item approaching full capacity |
| 🟣 Purple (Epic) | 7 – 8 | Fully occupied prefix/suffix grid |
| 🟤 Gold-brown (Legendary) | 6 + legendary | One legendary craft installed (consumes 1 prefix + 1 suffix) plus up to six other affixes |

- **Legendary crafts** always consume **one prefix slot and one suffix slot** simultaneously.
- Legendary affixes are hybrids, e.g.:
  - `+Fire Damage` + `+Lightning Damage`
  - `Gain Armor when Evading`
  - `Regenerate Energy when Critical Hits occur`

---

## 🧩 Item Structure Example

```ocaml
type affix = {
  name : string;
  tier : int;
  effect : (unit -> unit);  (* later replaced by data-driven behavior *)
}

type item = {
  base_id : int;
  prefixes : affix option array;  (* length = 4 *)
  suffixes : affix option array;  (* length = 4 *)
  legendary : affix option;       (* consumes one prefix + one suffix slot when [Some _] *)
}
```

Color is derived at runtime from how many `prefixes`/`suffixes` are populated and whether `legendary` is set.

---

## ⚗️ Crafting System Behavior

- Crafting operations are deterministic and reversible:
  - **Imbue**: Adds or rerolls an affix using materials.
  - **Extract**: Removes an affix and converts it to a material essence.
  - **Fuse**: Combines two affixes into a hybrid (potential legendary).
- Each crafting action triggers ECS **Events** and **Commands**, allowing simulation replays and rollback safety.

---

## 🌍 Economy & Loot Loop

- **No gold, no vendor RNG** — every material and base item has a clear, consistent source.
- Encourages **knowledge progression** rather than farming efficiency.
- Promotes **build experimentation** and short feedback loops.

> “No more chasing item color tiers — only chasing *meaningful builds.*”

---

## 🧪 Integration with Other Systems

| System | Integration |
|:--------|:-------------|
| Skills | Follow same XP curve (`BaseXP * (1 + L / (K + L))`) |
| Defenses | Unified mitigation formula (`R / (R + K * L)`) |
| Crafting | ECS-driven; actions emit events |
| Loot | Deterministic drops; materials replace randomness |
| Balance | All scaling curves share identical mathematical foundations |

---

## 🔮 Future Expansion Ideas

- **Skill Mods** as items: special augment crystals that modify skill behavior.
- **Set Recipes**: combine specific materials to craft unique items with custom visuals.
- **Legendary Evolution**: legendary items can absorb affixes from others via fusing.
- **Crafting Bench Integration**: later phase adds UI systems (microui or raygui).

---

*Extracted and reconstructed from mid-October 2025 game mechanics discussion.*

## ⚖️ Advanced Item & Crafting Mechanics

### 🧱 Item Affix Structure

Each item can hold up to **8 affixes total** — 4 prefixes and 4 suffixes.

| Slot Type | Max Count | Example Effects |
|:-----------|:-----------|:----------------|
| Prefix | 4 | +Armor, +Fire Damage, +Attack Speed, +Energy Regen |
| Suffix | 4 | of the Bear (HP%), of Precision (Accuracy), of Frost (Cold Res), of Insight (Mana%) |

This allows deep customization while keeping every item deterministic.

---

### 💎 Legendary Crafting Rule

- **Legendary crafting materials** always **consume 2 slots** — one prefix and one suffix.  
- An item can contain **only 1 legendary craft at a time**.  
- However, the player can **overwrite** an existing legendary craft with a new one at any time.  
- This preserves flexibility and prevents “dead gear” situations.

---

### ⚔️ Item Level and Crafting Outcomes

Every white item drops with an **Item Level (iLvl)**.  
Item Level influences both:
1. Which affixes can appear.  
2. The **range** of possible affix values.

Higher iLvl expands the roll range upward but does not guarantee better rolls.

---

### 🧪 Crafting Material Tiers

Crafting materials are divided into **tiers**, each mapped to a range of Item Levels.

| Tier | Item Level Range | Example Material | Notes |
|:------|:----------------:|:----------------:|:------|
| T1 | 1 – 20 | Iron Shard | Early game, low affix range |
| T2 | 21 – 40 | Steel Fragment | Midgame, improved affix scaling |
| T3 | 41 – 60 | Mithril Dust | High tier, enables advanced affixes |
| T4 | 61 – 80 | Orichalcum Core | Endgame |
| T5 | 81 – 100 | Celestial Essence | Late endgame legendary crafts |

When crafting, the system compares the **item’s level** and the **material’s tier** — using both to calculate the quality of the roll.

---

### 🧮 Crafting Formula Concept

The crafting result is influenced by both **character level (cLvl)** and **item level (iLvl)** relative to the material tier constant `K`.

**Chance to hit top range** of an affix:

`TopRollChance = (iLvl + cLvl) / (K + iLvl + cLvl)`

Where:
- `iLvl` — item level  
- `cLvl` — character level  
- `K` — tuning constant defining how quickly the curve softens  

This formula ensures:
- Crafting a low-level item as a high-level player gives slightly better odds.  
- High-tier materials on low-level items still help but can’t fully bypass level limits.  
- There’s always a diminishing-return curve rather than flat success chances.

---

### 🧩 Example Crafting Scenario

| Item Level | Character Level | Material Tier | Top-Roll Chance |
|------------:|----------------:|:---------------|----------------:|
| 10 | 10 | T1 | 33 % |
| 40 | 50 | T3 | 64 % |
| 80 | 90 | T5 | 82 % |

This gives a natural progression where late-game crafting feels rewarding but not guaranteed.

---

## ⚗️ T6 & T7 Crafting Material Tiers

Late-game introduces two additional material tiers that push affix power to new limits — at a cost.

| Tier | Level Range | Power | Rules |
|:------|:-------------:|:-------:|:------|
| **T6 – Ascendant Materials** | 101–120 | Very High | Can craft up to 2 prefix + 2 suffix affixes. These affixes **cannot be overwritten or salvaged**. |
| **T7 – Mythic Materials** | 121–140 | Extreme | Same limits as T6. Represents the final form of an item — permanent once crafted. |

### ⚠️ Permanence System

- Affixes from T6 and T7 tiers are **irreversible** — they define the item permanently.  
- Only remaining open slots (T1–T5 crafted) may still be modified.  
- Salvaging the item **destroys** the T6/T7 affixes, returning only standard materials.  
- Using these tiers is a *voluntary risk*: the ultimate reward for mastery.

### 🧠 Design Impact

| Aspect | Effect |
|:---------|:--------|
| **Determinism** | Preserved for T1–T5 crafting |
| **Risk / Reward** | Introduced through permanent tiers |
| **Player Agency** | You choose when to “lock in” your build |
| **Economy** | T6/T7 materials become rare and prestigious endgame drops |

> “Once you ascend an item, it becomes a legend — and legends don’t change.”

---

### 🌌 Acquisition of T6 & T7 Materials

T6 and T7 crafting materials exist **only beyond level 100 content** — in the endgame maps system.

#### 🗺️ Endgame Maps

After reaching character level 100, players unlock *Maps*: self-contained high-level zones with increasing monster and loot scaling.

| Map Tier | Monster Level | Material Drop Tier | Notes |
|:-----------|:---------------:|:------------------:|:------|
| T1–T5 | 100 | T5 | Final standard-tier drops |
| **T6** | 110–120 | T6 | Begins dropping Ascendant Materials |
| **T7** | 121–140 | T7 | Exclusive source of Mythic Materials |

Only **map bosses and elite monsters** in T6–T7 maps have a chance to drop these materials, making them a natural bridge between combat difficulty and crafting potential.

---

### ⚔️ Risk–Reward Integration

- Entering higher-tier maps raises both monster level *and* loot tier.  
- Death penalties or map modifiers (optional) can further amplify risk.  
- The player is never forced to progress beyond T5; T6–T7 crafting is an *opt-in mastery system*.

---

### 💎 Progression Loop

```text
Endgame Map → Defeat Elites → Acquire T6/T7 Materials →
Craft Ascendant or Mythic Gear → Push Higher Map Levels →
Unlock New Material Affix Ranges
```

This creates a closed progression cycle that:
1. Rewards skilled play with access to top-tier materials.  
2. Keeps deterministic crafting intact.  
3. Adds a prestige layer to endgame without RNG bloat.

---

### 🌠 Design Intent

> “Power is earned through danger, not dice rolls.”

T6 and T7 materials transform crafting from a utility into a late-game expression of mastery — the point where the player commits their build permanently in exchange for transcendental power.

---

### 🔩 Example

```text
Epic Sword before Ascension:
- +25% Physical Damage
- +15% Attack Speed
- +10% Critical Chance
- +8% Fire Resistance

After applying T6 Material:
- +60% Physical Damage (T6)
- +20% Attack Speed (T6)
[These two affixes are now permanent]
```

This system encourages meaningful long-term decisions, making each crafted weapon or armor piece *feel earned*.

---

### ⚗️ Crafting Workflow Summary

1. Obtain white base item (with iLvl).  
2. Choose crafting material (defines affix pool & range).  
3. Apply crafting → roll affix values using formula above.  
4. Optionally fuse affixes or overwrite with legendary craft.  
5. Re-craft freely; cost is primarily materials, not currency.

---

### 🧩 Integration Overview

| System | Interaction |
|:--------|:-------------|
| Item Level | Defines affix pool & roll range |
| Material Tier | Defines affix quality scaling |
| Character Level | Influences top-range probability |
| Legendary Craft | Consumes 2 affix slots; one per item |
| Re-crafting | Allowed anytime; overwrites existing rolls |

---

> “Crafting should reward investment and knowledge — not luck.”

This completes the advanced crafting model discussed in mid-October, following directly after the white-item and legendary-craft system.

## 🎨 Visual Rarity and Affix Slot Occupancy

Eon removes traditional *rarity-based drops*.  
All items drop as **white bases** — the only rarity distinction is **visual**, determined by how many affix slots are currently occupied.

| Color | Visual Tier | Prefix/Suffix Slots Used | Notes |
|:-------|:-------------|:------------------------:|:------|
| ⚪ White | Normal | 0/0 | Base item — all 8 slots free |
| 🔵 Blue | Magic | 2/2 | Early crafted item |
| 🟡 Yellow | Rare | 3/3 | Midgame crafted item |
| 🟣 Purple | Epic | 4/4 | Full affix item (max roll potential) |
| 🟤 Golden-Brown | Legendary | 3/3 + 1 legendary (consumes 2 slots) | Single unique hybrid affix |

This creates a **visual rarity progression** that maps directly to mechanical depth — not to random drop tables.

---

### 💡 Epic vs. Legendary Design Philosophy

- **Legendary items** are not automatically the strongest gear.  
- Because legendary crafts consume **two affix slots**, a legendary can hold **fewer total affixes** (6 normal slots + 1 legendary) compared to an **epic** (8 normal slots).  
- As a result, **well-crafted epic gear can outperform legendaries** in many builds, especially where synergy between affixes is more valuable than a single hybrid effect.

This design keeps the focus on **build expression** and **crafting mastery**, rather than chasing rarity colors.

---

### 🧩 Example Comparison

| Type | Prefix Slots | Suffix Slots | Legendary Slot | Total Effects | Notes |
|:------|:--------------|:--------------|:----------------:|:----------------:|:------|
| **Epic (🟣)** | 4 | 4 | — | 8 | Highest customization potential |
| **Legendary (🟤)** | 3 | 3 | 1 (2 slots) | 7 | Unique hybrid, fewer total effects |

---

### ⚙️ Player Experience Goals

- Players **craft the identity** of an item rather than chase RNG drops.  
- **Colors represent potential**, not static rarity categories.  
- Encourages late-game theorycrafting, item fusing, and optimization loops.  
- **Legendaries** serve as build-defining items, not simple stat upgrades.  
- **Epics** remain viable endgame gear — sometimes *better*, depending on build.

---

> “Power comes from synergy, not color.”

---

This visual rarity system replaces the old rarity hierarchy, tying item color purely to **affix occupancy** and **crafting evolution** rather than drop randomness.

## 🌳 Skill Trees and Skill Crafting System

### 🧩 Core Concept

Each active skill in Eon has its **own skill tree**, similar in structure to *Last Epoch* or *Grim Dawn*.
- The tree defines **modifiers, not upgrades** — players tailor how a skill behaves rather than simply scaling numbers.
- Every skill tree caps at **level 20**.
- Progression through the tree consumes *skill points* earned as that skill gains proficiency XP.

---

### 📈 Skill Drop System

Skills themselves are **loot drops**, just like crafting materials.

| Source | Drop Type | Notes |
|:---------|:-----------|:------|
| Enemies / chests | Skill Gem | Contains base skill + random level roll |
| Bosses / quests | Unique Skill | Guaranteed thematic drops |
| Crafting | Skill Imprint | Crafted or upgraded version of an existing skill |

When a skill drops, its **initial level** is determined by both **character level (cLvl)** and **area level (aLvl)**:

`SkillDropLevel = (cLvl + aLvl) / 2 ± RandomVariance`

This ensures skills scale with world progression while maintaining some randomness.

---

### 🧮 Skill Level Formula

Each skill follows the same diminishing-returns model for leveling:

`SkillXPRequired = BaseXP * (1 + L / (K + L))`

This keeps all skill progression curves aligned with character leveling and crafting systems.

---

### 🧱 Skill Tree Example

```text
Fireball Skill Tree
 ├─ Increased Radius
 ├─ Ignite Chance
 ├─ Lesser Multiple Projectiles (LMP)
 └─ Burn Duration
```

Each node is represented internally as an ECS component that modifies the skill’s behavior graph when activated.

---

### 💠 Skill Crafting Materials

Special crafting materials can **modify skill trees** by replacing or transforming nodes.

Example:
- A rare drop called `Greater Conflux Catalyst` might allow replacing *LMP* with *GMP* on the Fireball tree.

```text
Before:  Fireball → LMP (shoots 3 projectiles)
After:   Fireball → GMP (shoots 5 projectiles, –15 % damage)
```

Rules:
- Each skill can have **one crafted override per branch**.
- Overwriting is reversible by salvaging the skill, reclaiming the catalyst material.
- The overwritten node is stored as metadata so it can be restored later.

---

### ⚗️ Skill Crafting Workflow

1. Obtain a skill drop (e.g. `Fireball Gem Lv 10`).
2. Acquire a compatible skill-crafting material.
3. Use the crafting UI to **bind** the material to a node.
4. The skill tree updates immediately in-game, emitting ECS `SkillModified` events.
5. Salvaging the skill refunds materials and resets the node.

---

### 🧙‍♀️ Skill Trees as ECS Data

Each skill tree is stored as a graph resource:

```ocaml
type skill_node = {
  id       : int;
  name     : string;
  unlocked : bool;
  effect   : (world -> entity -> unit);
}

type skill_tree = {
  skill_id : int;
  nodes    : skill_node list;
  max_lvl  : int;   (* always 20 *)
}
```

When the player gains skill XP or applies crafting, systems modify this resource directly.

---

### 🔮 Design Philosophy

- Skills, materials, and crafting all belong to the same **loot ecosystem**.
- Every formula across XP, crafting, and skill trees uses the same **curve family** for consistency.
- The player’s creativity, not RNG, defines power.
- **Modularity first**: skills are data assets, their trees and nodes are editable via external data files or mod scripts.

> “A Fireball isn’t one skill — it’s a framework waiting for discovery.”

---

### 🧩 Integration Overview

| Feature | Formula | Notes |
|:---------|:---------|:------|
| Skill XP | `BaseXP * (1 + L / (K + L))` | Diminishing returns curve |
| Skill Drop Level | `(cLvl + aLvl) / 2 ± variance` | Dynamic scaling |
| Skill Tree Cap | 20 levels | Consistent across all skills |
| Node Override | Via skill-crafting materials | Replace or transform existing node |
| Overwrite Rule | One per branch, reversible | Prevents permanent lock-ins |

---

This system ties together **skill progression, itemization, and crafting**, completing the core gameplay loop.

## 🧱 Item Level Cap and Endgame Balance

### 🧩 Hard Item Level Cap

- The maximum **Item Level (iLvl)** is **90**.  
- No item, regardless of player level or map level, can drop or be crafted above iLvl 90.

> “Beyond level ninety, power no longer grows — only mastery does.”

---

### ⚙️ Purpose of the Cap

| Goal | Description |
|:------|:-------------|
| **Prevent Power Creep** | Stops runaway scaling from 100 + maps creating absurd stat ranges. |
| **Stabilize Crafting** | Keeps affix formulas and tier ranges fixed; T6/T7 materials focus on permanence, not endless inflation. |
| **Maintain Item Identity** | Items stay tied to material tier, not to infinite item-level escalation. |
| **Encourage Map Progression** | Players run high-level maps for rare materials and affix locks — not higher iLvls. |

---

### 🧮 Example Interaction

| Map Level | Material Tier | Max Item iLvl | Notes |
|:------------|:---------------|:----------------:|:------|
| 100 | T5 | 90 | Normal endgame cap |
| 120 | T6 | 90 | Ascendant materials, no iLvl gain |
| 130 + | T7 | 90 | Mythic materials, permanence only |

Even in 130 + maps, item rolls and affix pools are governed by iLvl 90 limits.  
Only the *quality* of materials and permanence rules change at T6/T7.

---

### 💡 Design Philosophy

- Level 100 + maps are for **crafting depth**, not **stat inflation**.  
- The journey beyond 100 is about optimizing, specializing, and committing to final forms of gear.  
- The hard iLvl cap separates **progression** (experience) from **perfection** (crafting mastery).

> “At ninety, the forge stops shaping you — and you start shaping the forge.”

