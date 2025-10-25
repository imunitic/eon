## 🧱 Map Crafting & Execution System (Refined Design)

### 🗺️ Concept Overview

Maps are **not inventory items** — they are **temporary crafted instances**.  
The player uses the **Map Forge** to assemble a map blueprint using materials and parameters, then immediately launches the run.

> “You don’t find maps — you forge worlds and step inside them.”

---

### 🏭 The Map Forge

The **Map Forge** is a late-game structure that allows players to:
1. Select a base **zone** (e.g., Ruins, Caves, City Outskirts, Abyss, etc.)  
   - or choose **Random Zone (RNGesus Mode)** for random biome selection.  
2. Insert **Map Crafting Materials** into available slots.  
3. Press **Run** to teleport directly into the crafted map instance.

Maps do not occupy inventory space — they exist only for the duration of the run.

---

### ⚙️ Crafting Structure

Like items, maps have **8 total slots** (4 prefix, 4 suffix), divided by effect type:

| Slot Type | Examples | Notes |
|:-----------|:----------|:------|
| Prefix | Enemy modifiers (damage, health, density, boss count) | Affects encounter difficulty |
| Suffix | Environment / player modifiers (loot chance, regen, hazards) | Affects risk and reward |

Map affixes are added using **map crafting materials** of tiers T1–T7, following the same deterministic rules.

---

### 🌡️ Map Level Calculation

The **Map Level** is calculated at forge time.  
If using **standard materials (T1–T5)**:

`MapLevel = cLvl + (Tier * 5) + RandomVariance`

If using **special high-tier map materials (T6–T7)**:

`MapLevel = cLvl + (Tier * 5) + Σ(MaterialLevelBonus)`

Where:
- `MaterialLevelBonus` is a fixed increment (e.g., +2 or +3 per material used)
- Total map level can exceed 100, scaling up to 140+

Thus, crafting with high-tier or rare materials both **raises difficulty** and **unlocks higher-tier drops** (T6/T7 materials).

---

### 💎 Special Map Crafting Materials

High-end materials act like “level boosters” and affix enhancers simultaneously.

| Material Type | Effect | Level Bonus | Notes |
|:----------------|:--------|:-------------:|:------|
| **Ascendant Shard (T6)** | Adds one powerful map affix (e.g., “+1 Elite Boss”) | +5 | Cannot overwrite once applied |
| **Mythic Core (T7)** | Adds one mythic affix (e.g., “Double Material Drop Chance”) | +10 | Permanent; locks map configuration |
| **Zone Catalyst** | Increases map density or elite count | +2 | Stackable |
| **Temporal Distorter** | Adds time-based modifiers (shorter run, stronger enemies) | +3 | Optional high-risk modifier |

These materials are consumed during crafting — the resulting map cannot be modified afterward.

---

### 🧩 Execution Flow

```text
[Map Forge UI]

1. Select Zone (Ruins / Abyss / Random)
2. Insert Crafting Materials (up to 8)
3. Preview Difficulty: Map Level 124
4. [Forge & Run]
→ Player is teleported into a procedurally generated map instance
```

When the run ends:
- Rewards and materials are distributed.
- The map instance is destroyed.
- Player returns to the forge hub.

---

### 🔮 Progression & Risk

| Map Level | Material Tier | Drop Tier | Permanent Effects |
|:------------|:----------------:|:------------:|:----------------:|
| 100 | T5 | T5 | Normal endgame |
| 110 | T6 | T6 | Ascendant materials drop |
| 125 | T7 | T7 | Mythic materials, permanent affix locks |

---

### ⚠️ Permanence & Risk Rules

- Using **T6/T7** map materials locks the resulting map’s configuration — you can’t “undo” or edit it.
- Such maps often introduce **permanent world modifiers** for the duration of your session (e.g., “Corrupted Maps”).
- These affixes persist for the entire run but are **never stored** once completed.

---

### 🧠 Design Philosophy

> “Map crafting isn’t about chance — it’s about choosing how much danger to face.”

This design keeps **determinism**, **agency**, and **risk** perfectly balanced:
- No RNG portals or map drops.
- The forge is the single source of endgame content.
- High-tier materials simultaneously raise the map level and infuse permanent affixes.

---

### 🧮 Example Map Build

```text
Zone: Abyssal Depths
Base Level: 100
Materials Used:
 - 3x Ascendant Shard (T6)  → +15 Level
 - 2x Zone Catalyst          → +4 Level
 - 1x Mythic Core (T7)       → +10 Level
Final Map Level: 129
Affixes:
 +30% Enemy HP
 +2 Elite Bosses
 +20% Material Drop Rate
 [Permanent: Double Elite Density]
```

Result: a high-risk, high-reward endgame map forged by the player.

## 💾 Map Templates and Reforging System

### 🧩 Overview

Once a player successfully forges a map configuration, they can **save it as a Map Template**.

Templates preserve every parameter used in the forge process:
- Selected **zone** or biome  
- All **affixes and materials** used (by tier and quantity)  
- The resulting **map level** and difficulty rating  

> “Master a forge once — and you can recreate worlds at will.”

---

### ⚙️ Saving Templates

After crafting a map, the player can choose **[Save as Template]** in the Forge interface.

- Templates are stored as blueprints, not items.  
- Each template records:
  ```ocaml
  type map_template = {
    name        : string;
    zone        : string;
    affixes     : map_affix list;
    materials   : (material * int) list;
    base_level  : int;
    total_level : int;
  }
  ```
- Templates can be renamed, shared, and versioned (e.g., *“Abyss 125 – Double Boss”*).

---

### 🔁 Reforging Templates

When re-crafting from a saved template:
1. The Forge checks whether the player has **enough materials** for all listed slots.  
2. If yes → the map is instantly forged and launched.  
3. If not → missing materials are highlighted, and the map cannot be started.

Map Templates do **not** consume storage space — they are lightweight records.

---

### 🧱 Limitations

| Rule | Description |
|:------|:-------------|
| **Material Gate** | You must possess all required materials; no substitutes. |
| **T6/T7 Affix Locks** | Templates containing T6/T7 materials still produce **permanent maps** — risk remains. |
| **Scaling** | Templates automatically adjust final level if your character level changed since creation. |
| **Editability** | You can edit a template before re-forging (e.g., swap one affix). Edited templates save as new versions. |

---

### 🗂️ Template Management

The Forge provides a simple management UI:

```text
[Saved Map Templates]
────────────────────────────────────────
1. Abyss 125 – Double Boss [T6+T7]
2. Desert 110 – Material Farm
3. Frozen Wastes 120 – XP Focus
────────────────────────────────────────
[Load] [Edit] [Rename] [Delete]
```

---

### 🧠 Design Impact

- Encourages **strategic map design** rather than random grinding.  
- Provides **repeatable endgame runs** for farming specific materials or affixes.  
- Reduces downtime between sessions — forge, run, repeat.  
- Enables **community sharing** of map templates (future idea).

> “The greatest explorers don’t find maps — they build them, perfect them, and run them until the forge cools.”

---

### 🔮 Future Extensions

- **Template Sharing:** export/import blueprints as JSON for modding or co-op play.  
- **Forge Upgrades:** unlock more template slots or categories (XP maps, boss maps, material maps).  
- **Template Analytics:** show average clear time, loot yield, or material cost efficiency.

---

*This completes the map-crafting loop: players create, optimize, and perpetually refine their own endgame worlds.*

## 🔓 Map Forge Unlock & Early Progression Integration

### 🧩 Unlock Condition

- The **Map Forge** becomes available **after defeating the Act 1 boss**.  
- Upon victory, the player receives a **guaranteed Map Crafting Material** that matches their current character level.

> “The Forge awakens, its surface glowing — a world inside a world now within your grasp.”

This moment serves as both a narrative and mechanical milestone:
- Symbolizes mastery over the early game.
- Rewards the player with tangible endgame potential.
- Introduces map crafting organically, not through a tutorial popup.

---

### 🧱 Early Forge Access Rules

| Stage | Availability | Drop Behavior | Notes |
|:--------|:--------------|:----------------|:------|
| **Pre-Act 1** | Inactive | No map materials drop | Forge dormant, foreshadowed in story |
| **Post-Act 1 Boss** | Unlocked | First guaranteed map material drop | Player introduced to map crafting |
| **Act 2–4** | Fully functional | Map materials drop normally | Player may level through maps instead of story |
| **Endgame (100+)** | Full access | T6/T7 materials enabled | Complete deterministic endgame loop |

---

### 💎 Drop Rate Philosophy

- **Map crafting materials** share the same drop tables as **normal crafting materials**,  
  but have a **slightly lower base chance** (≈ 0.8 × normal rate).  
- This ensures:
  - Normal crafting remains the main progression path early on.
  - Map crafting feels special, not mandatory.
- As player level and zone level increase, map material drop chance scales up proportionally.

Example scaling function:

`MapMatDropChance = BaseChance * (1 + (ZoneLevel / 200))`

---

### 🧠 Design Rationale

- Keeps **campaign relevant** for story-focused players.  
- Introduces **Forge Mode** naturally after the first major victory.  
- Lets **system-focused players** pivot into alternative leveling immediately after Act 1.  
- Prevents early game overwhelm while preserving freedom and replayability.  

> “Defeat the first guardian — and earn the right to forge your own path.”

---

### 🧩 Future Variation

- **Hardcore variant:** early unlock possible via hidden quest or special crafting discovery.  
- **NG+ option:** start with the Forge unlocked from level 1 for alternate playthroughs.


