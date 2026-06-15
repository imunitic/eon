# Combat System Design: Damage, Mitigation, and Scaling

This document summarizes a complete, rating-based combat math framework inspired by *Path of Exile*’s armor model but generalized for a cleaner and more tunable system.

---

## 🔍 Variable Clarification: Understanding `L`

Throughout Eon’s design documentation, the variable **`L`** has appeared in two related contexts:

1. **World / Enemy Level Context**  
   - In progression and defense formulas, `L` represents the *enemy or world level* — a macro measure of the danger the player faces.  
   - It defines how defensive ratings scale against overall world difficulty.

2. **Combat Hit Context**  
   - In runtime combat resolution, `L` represents the *effective incoming threat level* — the power of a specific hit or attack.  
   - It can be derived from attacker level, attack base damage, and relevant modifiers.

To unify both usages:

```
L_eff = Effective Incoming Threat Level
      = AttackerPower * AttackModifiers * LevelScaling
```

You can treat **enemy/world level** as the baseline approximation of `L_eff`, while the actual **attack power** becomes the runtime value.  
In other words:

| Context | Meaning of `L` | Purpose |
|:----------|:----------------|:---------|
| **System-Level Balancing** | Enemy or world level | Used for tables, UI hints, and global tuning |
| **Runtime Combat** | Effective hit power | Used in final mitigation calculation |

Both describe *incoming threat magnitude* — one abstract, one concrete — so they are compatible and interchangeable depending on the calculation layer.

---

## 1. Core Mitigation Formula

The fundamental idea is to express **damage mitigation** as a ratio between a *defensive rating* and the *incoming threat*.

`Mitigation = R / (R + K * L)`

**Where:**
- `R` — Defense Rating (e.g. armor, resistance, etc.)
- `L` — Incoming threat level (damage or power of the hit)
- `K` — Scaling constant controlling how sharply the defense drops off against stronger hits

### Example
| Armor | Hit | Mitigation | Notes |
|--------|-----|-------------|-------|
| 10 000 | 200 | 83% | Very effective |
| 10 000 | 2 000 | 33% | Moderate |
| 10 000 | 10 000 | 9% | Weak vs big hits |

The same functional form works for **all** defense types by changing `K` and interpreting `R`/`L` appropriately.

---

## 2. General Damage Scaling Formula

To mirror mitigation on the *offensive* side, use a similar structure:

`EffectiveDamageMultiplier = A / (A + Kd * D)`

**Where:**
- `A` — Attacker’s offensive rating (Attack Power, Spell Power, etc.)
- `D` — Defender’s toughness
- `Kd` — Offensive scaling constant

Then total base damage:

`EffectiveBaseDamage = B * (A / (A + Kd * D))`

---

## 3. Full Combat Resolution Pipeline

Combine damage scaling and mitigation into one sequence.

### Step 1: Effective Base Damage
`EffBase = B * (A / (A + Kd * D))`

### Step 2: Mitigation
`M = R / (R + Km * EffBase)`

### Step 3: Final Damage
`FinalDamage = EffBase * (1 - M)`

**Combined Formula:**

`FinalDamage = B * (A / (A + Kd * D)) * (1 - (R / (R + Km * B * (A / (A + Kd * D)))))`

### Example

| Variable | Value | Description |
|-----------|--------|-------------|
| `B` | 1000 | Base weapon damage |
| `A` | 200 | Attacker power |
| `D` | 100 | Defender toughness |
| `R` | 500 | Defender armor |
| `Kd` | 1 | Damage constant |
| `Km` | 1 | Mitigation constant |

**Computation**

1. `EffBase = 1000 * 200 / (200 + 100) = 667`
2. `M = 500 / (500 + 667) = 0.428`
3. `Final = 667 * (1 - 0.428) = 381`

✅ **Final Damage = 381**

---

## 4. Critical Hits

### 4.1 Guaranteed Crit
Multiply base damage by the crit multiplier **before** mitigation.

`Bcrit = B * c`

`EffBase = (B * c) * (A / (A + Kd * D))`

### 4.2 Expected (Average) Crit Damage
For deterministic simulations or DPS displays:

`Bavg = B * (1 + p * (c - 1))`

Where:
- `p` = crit chance
- `c` = crit multiplier

---

## 5. Crit Chance via Rating System

Use the same diminishing-returns structure for critical chance.

`CritChance = C / (C + Kc * Rc)`

Where:
- `C` = attacker’s crit rating
- `Rc` = defender’s crit resistance rating
- `Kc` = crit scaling constant

### With Base Crit Chance
`FinalCritChance = BaseCrit + (1 - BaseCrit) * (C / (C + Kc * Rc))`

---

## 6. Unified Defense System

| Attack Type | Defense Stat | Formula | Description |
|--------------|---------------|----------|-------------|
| **Physical Damage** | **Armor** | `R / (R + K * D)` | Strong vs small hits |
| **Elemental Damage** | **Elemental Resistances** | same | Fire, Cold, Lightning |
| **DoT Damage** | **DoT Resistance** | same | Bleed, Poison, Burn |
| **Critical Damage** | **Crit Resistance** | same | Reduces crit chance or effect |
| **Debuffs / Statuses** | **Debuff Resistance** | same | Resist freeze, stun, shock, etc. |

All use the same rating-based diminishing-return behavior.

---

## 7. Independent Tuning with `K`

Each defense can have its own `K` constant.

| Defense | Suggested `K` | Notes |
|----------|----------------|-------|
| Armor (Physical) | 1.0 | Baseline |
| Elemental Resistances | 0.8 | Slightly easier to scale |
| DoT Resistance | 0.5 | DoTs tick often; stronger per point |
| Crit Resistance | 1.5 | Harder to scale; keeps crits dangerous |
| Debuff Resistance | 1.2 | Keeps ailments relevant |

---

## 8. Base Ratings and Level Scaling

Provide small **level-based rating bonuses** so players don’t need every stat on gear.

| Defense | Example Base Formula | Intention |
|----------|----------------------|------------|
| Armor | `10 * Level` | Core defense with modest scaling |
| Elemental Resist | `5 * Level` | Helps reduce gear pressure |
| DoT Resistance | `3 * Level` | Keeps sustained damage fair |
| Crit Resistance | `2 * Level` | Niche defense |
| Debuff Resistance | `4 * Level` | Avoids status spam frustration |

Total rating = `gear_rating + level_rating`

---

## 9. Player-Friendly Display

Internally you use **ratings**, but you can display them as approximate percentages relative to enemy level:

> “Fire Resistance: 320 (≈68% mitigation vs Level 30 enemies)”

This keeps the math flexible while remaining intuitive to the player.

---

## 10. Summary

You’ve built a unified, rating-based combat model:

`Mitigation or Chance = R / (R + K * L)`

**Highlights**
- All defenses are *ratings*, not fixed %.
- Each uses the same diminishing-returns shape.
- Each has its own `K` for independent tuning.
- Level grants small baseline ratings.
- Crits are applied *before* mitigation.
- Average crit damage = `1 + p * (c - 1)`.

This framework is:
- **Elegant** – consistent math across all mechanics.  
- **Balanced** – diminishing returns prevent extremes.  
- **Player-friendly** – less gear stress, natural progression.  
- **Developer-friendly** – easy to tune globally via `K`.

---

## 11. Crowd Control Duration

CC duration uses the same diminishing-returns family, outputting seconds instead of damage reduction.

### Formula

`CCDuration = max(Floor, MaxDuration * (1 - R / (R + K * L)))`

**Where:**
- `R` — Debuff Resistance rating
- `L` — CC threat level (determined by mob type and rarity)
- `K` — scaling constant per CC type
- `MaxDuration` — upper bound for this CC type
- `Floor` — minimum duration, always non-zero

This is the *remaining damage* form of the core formula applied to time.

### Design Principles

- **Trash mobs** have low `L` → even modest Debuff Resistance reduces duration to near the floor.
- **Elites** have moderate `L` → Debuff Resistance starts mattering on gear.
- **Bosses** have high `L` → duration approaches `MaxDuration`; Debuff Resistance is a real build decision.
- CC is **never completely negated** — the floor preserves the tactical signal that something hit you.

### Per-CC-Type Parameters

| CC Type | MaxDuration | Floor | Suggested K | Notes |
|:--------|------------:|------:|:-----------:|:------|
| Stun    | 1.5s        | 0.1s  | 1.2         | Brief flinch at high resistance |
| Freeze  | 3.0s        | 0.2s  | 1.0         | Visually noticeable even when resisted |
| Chill   | 5.0s        | 0.3s  | 0.8         | Long but less punishing; higher floor acceptable |
| Shock   | 2.0s        | 0.1s  | 1.0         | Short with high resistance |

### Example

Character with `R = 400` Debuff Resistance hit by a boss freeze (`L = 600`, `K = 1.0`, `MaxDuration = 3.0s`, `Floor = 0.2s`):

1. `Ratio = 400 / (400 + 1.0 * 600) = 0.4`
2. `Raw = 3.0 * (1 - 0.4) = 1.8s`
3. `Final = max(0.2, 1.8) = 1.8s`

Same character hit by a trash mob freeze (`L = 80`):

1. `Ratio = 400 / (400 + 80) = 0.833`
2. `Raw = 3.0 * (1 - 0.833) = 0.5s`
3. `Final = max(0.2, 0.5) = 0.5s`

Stack more Debuff Resistance and the trash freeze collapses toward the 0.2s floor.

### Block Recovery

Block recovery is treated as a **self-imposed CC triggered by a successful block**. The same formula applies:

`BlockRecoveryDuration = max(Floor, MaxDuration * (1 - R / (R + K * L)))`

Where `L` is derived from the blocked hit's power — a light trash swing barely interrupts you, a heavy boss slam locks your shield arm for a meaningful moment.

This means **no separate block recovery stat is needed**. Debuff Resistance naturally serves shield builds alongside its other roles:

| Build | Why Debuff Resistance matters |
|:------|:------------------------------|
| Any build | Reduces CC duration from mob attacks |
| Shield build | Also reduces block recovery lockout |
| Endgame | Real optimization target vs boss CC and heavy hits |

One stat, three coherent expressions of the same mechanic.

### Endgame Hook

Legendary affixes or endgame passives can reduce the `Floor` itself — a meaningful chase mechanic for CC-sensitive builds, without ever granting full immunity.

---

## 12. Block Mechanics

Block is a defensive layer available to all weapon types, with effectiveness varying by weapon category. It is **not a binary on/off** — it has a chance to trigger and a mitigation mode that depends on build choices.

### Block Chance

Block chance follows the same rating formula:

`BlockChance = B / (B + K * L)`

**Where:**
- `B` — Block Rating (from weapon type, gear affixes, Debuff Resistance investment)
- `L` — Attacker threat level
- `K` — scaling constant

Block chance is **capped per weapon type**:

| Weapon Type | Block Chance Cap | Notes |
|:------------|:----------------:|:------|
| Shield | 50% | Primary block identity |
| Two-hander | 25% | Can block, lower ceiling |
| Dual wield | 0% | No block; pure offense |

### Standard Block

On a successful block, the hit is **fully negated**. Cap is 50%.

Shield builds lean on this — high block chance, full negation, recovery governed by Debuff Resistance.

### Glancing Blows (Legendary Affix)

A legendary affix can convert a build to **Glancing Blows** mode, changing the block paradigm entirely:

- Block chance cap raises to **85%**
- Successful blocks **no longer fully negate** — instead they reduce incoming damage by **60%**
- The remaining 40% still passes through armor and resistance mitigation

`DamageAfterGlancingBlock = HitDamage * 0.40 * (1 - ArmorMitigation) * (1 - ResistMitigation)`

This is a **playstyle shift, not a strict upgrade**:

| Scenario | Standard Block (50% chance, 100% negate) | Glancing Blows (85% chance, 60% reduce) |
|:---------|:-----------------------------------------|:----------------------------------------|
| Burst hit that would one-shot | Risky — 50% chance to die | Safer — 85% chance to survive with 40% bleed-through |
| Sustained damage | Strong — every block is full negation | Weaker — damage bleeds through every block |
| Synergy | Standalone | Stacks with armor/resistances on bleed-through |

### Weapon Type and Block Identity

| Weapon Type | Block Style | Natural Playstyle |
|:------------|:------------|:------------------|
| Shield | Standard or Glancing Blows | Tank, high survivability |
| Two-hander | Standard only, low cap | Offensive with modest block upside |
| Dual wield | No block | Pure offense, relies on evasion/armor/resistances |

### Block Recovery

All successful blocks trigger a short recovery window (see Section 11 — Block Recovery). Debuff Resistance reduces this lockout for all weapon types equally.

### Design Philosophy

- **50% standard cap** prevents block from trivializing content on its own.
- **Glancing Blows** rewards build investment with consistency over gambling — neither mode is strictly better.
- **Two-handers can block** — no build is hard-locked out, but the ceiling enforces identity.
- Achieving near-maximum defenses across all five layers (life, block, resistances, evasion, armor) requires deep crafting investment and is intentional — a fully optimized character *should* feel powerful in normal content. The challenge ceiling scales upward through higher map tiers and uber bosses.

---

## 13. EHP Paradigm Shifts via Legendary Affixes

The default EHP model is **five-layer balanced**: life pool backed by armor,
evasion, resistances, block, and debuff resistance working in combination. No
single layer provides full protection; the formula's diminishing returns reward
spreading investment across all five.

Legendary affixes can shift a build into a fundamentally different EHP
paradigm — not nudging numbers but changing which layers feed into the formula
and how recovery works. Each paradigm uses the same underlying `R / (R + K * L)`
math; the affix changes what R means and what the cost of that redefinition is.

---

### Paradigm 1 — Balanced (default)

Five layers, each capped by its own K, all contributing. The intended baseline
for most builds. Content is balanced around a player who has invested reasonably
across all five layers.

---

### Paradigm 2 — Fortress (armor-universal coverage)

**Affix:** *"Armor applies to all damage types, including DoTs. You lose all
HP regeneration and mana regeneration."*

Armor's `R / (R + K * L)` now covers physical hits, elemental hits, bleed,
poison, and burn — all incoming damage passes through the same armor rating.
The cost: no passive recovery of any kind. Every point of damage that gets
through is permanent until actively recovered.

**K interaction:** Armor applies to DoTs at its own tuning constant rather than
the DoT resistance constant, giving legendary affixes an independent lever:

| DoT K used | Power level | Note |
|---|---|---|
| DoT resistance K (0.5) | Very strong | Armor is extra efficient vs DoTs |
| Armor K (1.0) | Strong | Same curve as physical |
| Unique affix K (1.5–2.0) | Balanced | Ceiling without touching base curves |

Recommended: unique K per legendary affix for clean tuning independence.

**What this forces:** Recovery must be active — life leech from attacks, life
on kill, recovery skills. Standing still in the fortress kills you. The
defensive paradigm dictates the offensive style: you must keep hitting to stay
alive. High-armor fortress builds are nearly immune to DoT-heavy content but
fragile against anything that cuts attack uptime (CC, knockback, silence).

---

### Paradigm 3 — Glancing Blows (evasion-universal coverage)

**Affix:** *"Evasion applies to all damage types, including DoTs. You no longer
fully evade attacks — instead every hit and every DoT tick deals 40% of its
damage. Your evasion chance cap raises to 85%."*

**Standard evasion in Eon** uses PoE's entropy sequencing — a deterministic
system that guarantees your average evasion rate over time (at 50% evasion you
WILL evade half of all attacks) but the individual hit/miss sequence still feels
like variance. Moment-to-moment mitigation is not fully predictable. DoTs bypass
evasion entirely.

**Glancing Blows removes all remaining variance.** No hit/miss. No sequence. No
gambling. Every attack glances for exactly 40% and that 40% still passes through
armor and resistances:

```
GlancingDamage = HitDamage * 0.40 * (1 - ArmorMitigation) * (1 - ResMitigation)
```

DoTs also become glancing — each tick deals 40% of its normal value, further
reduced by resistances. An evasion build's natural weakness to DoT-heavy content
is resolved without making it free.

**Expected damage comparison:**

| Mode | Chance | Damage on proc | Expected factor |
|---|---|---|---|
| Standard evasion 50% | 50% full miss | 0% | 0.50 |
| Glancing Blows 85% | 85% glancing | 40% | 0.85×0.4 + 0.15×1.0 = **0.49** |

Nearly identical average — completely different feel. Glancing Blows trades the
gamble for consistency. In long fights against fast attackers the 40% chips
relentlessly; against slow hard-hitting pinnacle bosses it is excellent.

**Symmetry with block Glancing Blows:** the same 40% / 85% cap applies to both
evasion and block Glancing Blows. Players learn the concept once and it means
the same thing across both defensive layers.

**Paradigm identity:** the Glancing Blows evasion build is the "no RNG
mitigation" evasion build. Passive regen still works. Recovery demands are
lower than Fortress. The cost is implicit — you can never fully negate anything,
and fast-hitting enemies sustain consistent chip damage that regen must outpace.

---

### Paradigm 4 — Mind over Matter (mana-as-life)

**Affix:** *"100% of all damage — including DoTs — is taken from mana before
life. Mana regeneration is doubled. Damage taken is doubled. All mitigation
(armor, resistances, evasion, block) operates at 80% efficiency."*

**The formula shift:**

Normal: `FinalDamage = Hit × (1 − Mitigation)` → hits life

MoM: `FinalDamage = Hit × (1 − Mitigation × 0.80) × 2` → hits mana

Example with 40% armor mitigation against a 500-damage hit:

| Mode | Calculation | Result |
|---|---|---|
| Normal | `500 × (1 − 0.40)` | 300 to life |
| MoM | `500 × (1 − 0.32) × 2` | 680 to mana |

A single hit costs significantly more than its life equivalent. Life becomes a
last-resort overflow buffer — it only depletes when mana is exhausted.

**Recovery model:**

Doubled mana regen is the primary sustain mechanism. Between bursts, mana
refills fast. The paradigm is designed for spike survival: a heavy hit that
would one-shot a normal build drains the mana pool instead, and regen restores
it before the next spike. Against sustained fast-hitting enemies, mana drains
faster than it regenerates — this is the paradigm's natural weakness.

**The skill-mana tension:**

Skills cost mana. Damage takes mana. In a tough fight, every cast chips the
defensive buffer. A MoM player is constantly weighing offensive output (spending
mana on skills) against defensive reserves (needing mana to absorb the next hit).
This is a richer resource management loop than managing a single HP bar.

**Natural weaknesses:**

- **DoT-heavy content:** every tick hits mana at 80% mitigation × 2. Sustained
  bleed or poison drains mana relentlessly between ticks — regen may not keep
  pace on DoT-stacked map affixes.
- **Mana drain enemies/affixes:** any mechanic that drains mana directly
  collapses the defensive buffer without dealing "damage" in the traditional
  sense. Map affixes or boss abilities that reduce mana are the paradigm's
  hard counter.
- **Low mana pool builds:** MoM scales with total mana. Intelligence-heavy
  caster builds are natural fits; strength/dexterity builds need heavy mana
  investment from gear to make the paradigm viable.

**Paradigm identity:** survive spikes through a deep mana buffer and fast regen;
die to sustained pressure or anything that bypasses the mana layer. Rewards
active resource management over passive stat stacking.

---

### Design Rule

> A legendary EHP paradigm shift must change *which layers matter* and *how
> recovery works*, not just increase the numbers. If removing the affix
> doesn't fundamentally change how the build plays, it isn't a paradigm shift
> — it's a stat boost.

> Legendary affixes have no numerical ranges. Two copies of the same legendary
> affix are identical — no "good roll" or "bad roll." Regular affixes have
> ranges; legendary affixes are flat binary trade-offs. The commitment is the
> cost: legendary affixes cannot be extracted once crafted, only replaced
> (destroying the old one). They drop at normal play pace and are not
> level-dependent — the decision to commit is the meaningful moment, not the
> acquisition.

---

*End of document.*
