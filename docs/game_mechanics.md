# 🧱 Eon Game Mechanics Discussion (Extract from Eon ECS Development :: Part 1)

## ⚔️ Combat and Defense System Design

### 🧮 Unified Defense Rating Formula
We discussed how to replace percentage-based defenses (Armor %, Evasion %, Resistances %) with a single **Defense Rating** system.

**Goal:**  
To make all forms of defense — armor, evasion, and resistances — behave under the same *diminishing returns curve*, so that every point invested in defense gives meaningful protection early on, but with soft caps at higher levels.

**Core Idea:**  
Each defense stat contributes to a total "Defense Rating" (`R`) compared to an attacker’s "Attack Power" (`A`) or the level scaling constant (`K × L`).

Example generic formula:

**Mitigation** = `R / (R + K × L)`

Where:
- `R` — total defense rating (armor, evasion, or resistance)
- `K` — scaling constant controlling progression curve (e.g., how quickly returns diminish)
- `L` — attacker or world level

This can apply to:
- Physical damage → Armor Rating  
- Hit avoidance → Evasion Rating  
- Elemental reduction → Resistance Rating  

Each stat uses the same curve with different constants.

---

### 🧩 Philosophy
- Avoid traditional % caps like “75% resist max”.
- Every defense has diminishing returns built into the curve.
- This allows **unified balancing** and simplifies progression.
- The same curve can later be reused for **Experience Gain**, **Skill Efficiency**, and **Damage Scaling** — for consistent feel across the game.

---

## 💥 Experience Gain and Level Progression

You asked if the same curve could apply to experience gain to control how quickly players reach the level cap.

The idea: reuse the defense curve so leveling feels rewarding and fair — not grindy like *Diablo II* or *PoE*, but not trivial either.

Desired pacing:
> "Level cap should not be a grind to reach, but also not something you hit halfway through the campaign — ideally around 5–6 hours into endgame."

Example concept:

`ExperienceRequiredForNextLevel = BaseXP * (1 + L / (K + L))`

This keeps growth smooth early, then slows progression later in a natural curve, without huge exponential spikes.

---

## ⚙️ Systemic Design Notes

### 🧠 ECS Component Roles
We reaffirmed that:
- **ECS Core** remains minimal — no built-in systems, no assumptions about phases.
- **Engine Layer** implements Systems such as Combat, Movement, Rendering, etc.
- **Game Layer** defines Components like `Health`, `Armor`, `Evasion`, `ElementalResistance`, and their logic through Systems.

### 🪄 Event / Command Flow Example
A typical combat event loop might look like:

```ocaml
(* Combat_system.ml *)
module Combat_system = struct
  let register world =
    let events = World.get_service world `Events |> Option.get in
    let commands = World.get_service world `Commands |> Option.get in
    Events.on events (function
      | `Hit (attacker, target) ->
          let damage = Combat.calculate world attacker target in
          Commands.emit commands (`Apply_damage (target, damage))
      | _ -> ()
    )

  let update _world _dt = ()
end
```

The separation of *Events* (things that already happened) and *Commands* (intentions for next frame) supports deterministic simulation and future replay/debugging.

---

## 🧪 Design Summary

| System | Description | Key Principle |
|---------|--------------|---------------|
| **Combat** | Calculates hit and damage outcomes | Deterministic, data-driven |
| **Defense** | Unified formula for armor, evasion, resistances | Diminishing returns |
| **Leveling** | Based on same diminishing curve as defense | Smooth progression, no grind |
| **ECS Core** | Provides primitives only (World, Entity, System, etc.) | No phases, no assumptions |
| **Engine Layer** | Adds default systems (movement, combat, rendering) | Modular composition |

---

## 🔮 Future Considerations
- Introduce **Dynamic Defense Types** (e.g., *Elemental Resistance Rating*, *Status Resistance Rating*) following the same formula.
- Allow **gear scaling** via rating multipliers instead of flat percentages.
- Potential to unify **offense scaling** too — e.g., critical chance, accuracy, or spell amplification — under similar diminishing or increasing curves.

---

### 💡 Example Progression Visualization
Imagine a curve where:
- Early investment in defense gives noticeable impact.
- Midgame flattens for balance.
- Lategame growth becomes more gradual.

This ensures **consistency across all gameplay layers** — defense, offense, experience, skill growth.

---

*Extracted and reconstructed from the 2025-10-11 conversation (Eon ECS Development :: Part 1).*

# ⚙️ Eon Game Mechanics Discussion (Part 2 – Benchmark Bechamel Setup)

## 🧮 Defense Formula Refinement

In this discussion, we expanded on the **Unified Defense Rating** concept and finalized its balancing behavior.

### 🎯 General Formula

We settled on a family of functions of the form:

`EffectiveReduction = R / (R + K * L)`

or alternatively (for finer scaling control):

`EffectiveReduction = 1 - (K * L) / (R + K * L)`

Both forms are equivalent; the second simply expresses *remaining damage* instead of *mitigation*.

- `R` — total defense rating (Armor, Evasion, Resistance)
- `L` — attacker level or challenge level
- `K` — constant controlling how quickly returns diminish

---

### 🧱 Implementation Notes

1. **Armor, Evasion, Resistances** all plug into this same function.  
   Each uses its own constant `K` (e.g. Armor = 400, Evasion = 200, Resist = 600) tuned for feel and class identity.

2. **No hard caps** (like “75 % max resist”).  
   Instead, effective mitigation asymptotically approaches 1 but never reaches it.

3. **Balancing target:**  
   Mid-tier gear should achieve about 50 % effective mitigation at same-level encounters.  
   Doubling rating should not double mitigation; it should yield +10-15 % gain only.

4. **Scaling per level:**  
   The `L` term can be either the attacker’s level or an “encounter tier” constant.  
   This naturally keeps defense relevant at all stages.

---

### 🧩 Example Table

| Level (L) | Defense (R) | K | Effective Mitigation |
|-----------:|-------------:|:--:|----------------------:|
| 10 | 100 | 200 | 33 % |
| 30 | 600 | 200 | 60 % |
| 60 | 1800 | 200 | 90 % |

This curve visually matches our design goal: steep early gain → flattening endgame.

---

## 🔥 Resistance & Elemental Scaling

Resistances (Fire, Cold, Lightning, Chaos, etc.) follow the same pattern, but ratings are scaled so that each element can have different *growth coefficients* `K`.

Example:
```ocaml
let resist_mitigation rating level k =
  rating /. (rating +. (k *. float level))
```

The ECS component might store per-element values:
```ocaml
type resistances = {
  fire   : float;
  cold   : float;
  lightning : float;
  chaos  : float;
}
```

Then each can be plugged into the same formula independently.

---

## 💥 XP Curve Extension

We explored using the **same diminishing-return function** for experience gain.

### 🎓 Formula Concept

`XPRequired(L) = BaseXP * (1 + L / (K + L))`

- Early levels rise quickly but stay manageable.  
- Midgame introduces a smooth slowdown.  
- Endgame approaches an asymptote rather than an exponential wall.

For example:
| Level | K | XP Required |
|:------:|:--:|------------:|
| 1 | 10 | 110 % of base |
| 20 | 10 | 200 % |
| 40 | 10 | 280 % |
| 80 | 10 | 330 % |

This ensures a satisfying progression where level cap (~100) is reachable in ≈ 5-6 hours of endgame rather than weeks of grind.

---

## ⚙️ Balancing & Tuning

We noted that balancing constants (`K`, `BaseXP`) can be adjusted per-act or per-zone, producing different “feel curves.”  
E.g. Act 1 might use K = 50 to feel fast, Act 4 K = 150 to slow down.

It’s also possible to reuse the same function for **skill experience**, **weapon proficiency**, or **crafting mastery**, keeping the entire game’s growth mathematically consistent.

---

## 🧪 Testing & Benchmarking Notes

This discussion happened in parallel with the setup of the **Bechamel benchmarking suite** for ECS systems.  
We planned to:
- Measure cost of combat calculations under high entity counts.
- Compare SoA vs AoS storage for defense lookups.
- Use QCheck for randomized input verification.

The idea: benchmark *defense calculations* and *combat update systems* as micro-benchmarks to profile ECS iteration cost.

---

## 📈 Visual Intuition

If plotted, the mitigation curve would appear as a concave function:

```
1.0 ────────────────────────────────● asymptote (100%)
     \
      \
       \
        ●───────→ Rating
```

Meaning:
- +100 rating early gives big impact.
- +100 rating later gives minor benefit.

---

## 🧩 Integration Summary

| Aspect | Formula | Notes |
|:--------|:---------|:------|
| Armor / Evasion / Resist | `R / (R + K×L)` | Unified defense curve |
| XP Curve | `Base×(1+L/(K+L))` | Smooth progression |
| Scaling Constant K | Tunable per stat / zone | Controls softness |
| ECS Implementation | Component → System → Event/Command | Deterministic update |
| Benchmarking | Bechamel + QCheck | Validate perf and fairness |

---

*Extracted and reconstructed from the 2025-10-22 conversation (Benchmark Bechamel Setup).*

## 💪 Character Progression Simplification

### 🧠 Design Rationale

Eon abandons traditional RPG attribute systems (`Strength`, `Dexterity`, `Intelligence`) in favor of a **natural, curve-driven stat progression**.  
Since crafting and affix systems already provide enormous flexibility, flat attributes are redundant and only add noise.

> “Progress comes from your choices — not a point-buy spreadsheet.”

---

### ❤️ Core Stats by Level

Each core stat (Health, Energy, Defense, Damage, etc.) increases automatically as the character levels up, following a smooth, deterministic curve.

Example baseline formula:

`Stat(level) = Base + (Growth * level ^ Curve)`

Where:
- `Base` — starting value (e.g., 100 HP)
- `Growth` — scaling factor per level (e.g., 8 HP)
- `Curve` — exponent (1.0 for linear, >1.0 for slightly exponential)

---

### 🛡️ Defense Rating Progression

A small **passive defense increase** is granted on level-up to preserve survivability across content tiers.

Example:

`DefenseBonus(level) = (level * 2.5)`

This bonus feeds directly into the same unified formula:

`EffectiveReduction = R / (R + K * L)`

making level naturally synergize with the defense model without adding separate stats.

---

### ⚖️ Endgame Scaling and Difficulty Philosophy

Eon has **no traditional difficulty settings** (Normal / Nightmare / Hell).  
Instead, difficulty is *organic* — defined by enemy scaling and endgame systems.

#### 🩸 Penalty Curve
After a certain level threshold (e.g., level 90), the player gradually receives **soft penalties** to defense or resistances to simulate endgame attrition:

`DefensePenalty = max(0, (level - 90) * 0.5)`

This gently reduces effective mitigation while rewarding continued crafting investment.

#### 🔥 Monster Scaling System
After reaching level 100 (the soft cap), players can optionally **raise world level** — increasing monster level and loot tier.  
This mimics systems seen in *PoE’s map tiers*, *Titan Quest’s x2/x3 modifiers*, or *W40K: Martyr’s Inoculator difficulty scaling*.

`MonsterLevel = Base + WorldModifier`

Higher world levels increase:
- Enemy stats (HP, damage)
- Crafting material tiers
- Affix range ceilings

---

### 🏃 Movement Speed Progression

Eon has **no teleports of any kind.** The world is meant to be traversed, not skipped. Movement speed is a core stat that scales with level so players never feel like a slug waiting for the right boots drop.

#### Formula

`MovementSpeed(level) = BaseSpeed * (1 + level * 0.005)`

- At level 1: baseline speed (0% bonus)
- At level 60: +30% over baseline
- At level 100: +50% over baseline

Growth is linear and small enough that gear affixes remain meaningful, but large enough that progress always feels tangible.

#### Gear Affixes

Movement speed affixes on gear are **additive on top of the level baseline**. This means:
- You are never hunting boots just to feel playable
- You are hunting boots to feel *faster than already good*

#### Interaction with CC

Chill and slow CC effects reduce current movement speed — meaning they are always felt and never trivial, because movement speed is something the player has genuinely invested in through leveling.

#### Design Philosophy

- No teleports means map design must be worth walking through — this is an intentional constraint that pushes toward interesting environments over corridor spam.
- Early game movement feels fluid by default; gear amplifies it.
- A character should feel progressively faster as they level, without any single item being the difference between playable and frustrating.

---

### 🎯 Philosophy Summary

| Concept | Mechanic | Notes |
|:---------|:----------|:------|
| Attributes | Removed | Simplified in favor of natural progression |
| Leveling | Auto-stat curve | Consistent scaling without manual allocation |
| Crafting | Core augment path | Determines specialization and build identity |
| Defense | Increases naturally | Scales via same unified formula |
| Movement | Level-scaling baseline | No teleports; traversal is intentional |
| Endgame Difficulty | Player-chosen | Dynamic world level modifiers, not static modes |

---

### 💬 Design Note
This model guarantees that:
- Every build scales predictably without stat traps.
- Crafting remains the main customization axis.
- “Difficulty” becomes a tool for player-driven challenge rather than a preset mode.
- The world is worth exploring — movement feels good from level 1.

> “You don’t pick a difficulty — you *become* the difficulty.”
