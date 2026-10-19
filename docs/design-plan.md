# Robin Hood RPG: Design and Development Plan

Working title: **Outlaws of Sherwood**
Status: v0.2 (2026-10-19). Core decisions locked by jake: see section 12. Items still marked **[DEFAULT]** are Claude's picks within those decisions.

---

## 1. Pitch

A mobile, turn-based tactical RPG where you lead Robin Hood's band from a hidden camp in Sherwood. On a **strategic map** of Nottinghamshire you choose where to strike; the band then travels there automatically and plays out a **linear tactical mission** (a sequence of encounters along a path). Missions are procedurally generated robberies and rescues, mixed with hand-authored story missions from the legends. The Sheriff of Nottingham and Sir Guy of Gisborne act as active antagonists who set traps, capture your companions and choke off your income.

**Session length target:** 5 to 10 minutes per mission, playable one-handed in portrait. **[DEFAULT]**

**Product:** standalone native mobile app (Android and iOS), offline, sold as a **one-time purchase** with no ads or in-app purchases. **Tone:** family adventure: enemies are knocked out or flee rather than killed.

---

## 2. Core loop

```
Camp (heal, equip, recruit, upgrade)
   -> Strategic map (pick a location / mission, see risk & reward)
      -> Auto-travel (time passes, Sheriff makes moves, travel events)
         -> Tactical mission (linear chain of 3-6 nodes: fights, choices, loot)
            -> Outcome (gold, supplies, reputation, captured members?, Sheriff reacts)
               -> back to Camp
```

**Meta loop:** Grow the band, raise Sherwood's reputation with the common folk, weaken the Sheriff's hold region by region, and progress the story chapters toward a showdown in Nottingham Castle.

---

## 3. Strategic layer

### 3.1 Map
A stylized, hand-drawn map with real and legendary locations as nodes connected by roads and forest paths.

| Location | Source | Role on map |
|---|---|---|
| Sherwood Forest / the Major Oak | real + legend | Home camp, safe zone |
| Nottingham (town & castle) | real | Sheriff's seat; endgame; high-risk heists |
| Great North Road | real | Ambush/robbery missions on travelers & tax wagons |
| Kirklees Priory | legend (Robin's death) | Late story chapter, "betrayal" missions |
| Fountains Abbey | legend (Friar Tuck duel) | Recruit Friar Tuck |
| St Mary's Abbey, York | legend (Gest: greedy abbot) | Rob the abbot, Sir Richard storyline |
| Barnsdale | legend (Gest setting) | Second forest base, unlockable |
| Blidworth | legend (Maid Marian's home in some tellings) | Marian storyline |
| Edwinstowe | legend (Robin & Marian's wedding) | Village hub, recruits, rumors |
| Papplewick / Robin Hood's Larder | local legend | Supply cache, hideout |
| Locksley | legend | Robin's origin, early chapter |
| Gisborne's Manor | imagined | Guy's stronghold, trap-heavy |
| Sheriff's Toll Bridge, Hanged Man's Crossing, Charcoal Burners' Clearing | imagined | Procedural mission sites |

### 3.2 Map mechanics
- **Nodes** show available missions, threat level, and reward type (gold, supplies, recruits, reputation).
- **Time** advances in days. Travel costs days; each day the Sheriff acts (see section 7).
- **Region control:** each region has a Sheriff Control value (0-100). Missions lower it; neglect lets it rise. High control means more patrols, harsher taxes on villages, and more traps.
- **Fog / Rumors:** scouting (or a scout companion like Much) reveals mission details and hidden traps before committing.
- **Auto-travel:** the player taps a destination; the band's token walks the route. Travel may trigger short events (a beggar asks for coin, a patrol spots you, a merchant offers a deal).

### 3.3 Resources
- **Gold** (stolen): recruiting, gear, bribes. "Give to the poor" spending raises Reputation.
- **Supplies** (food, arrows): consumed per day and per mission.
- **Reputation** with the common folk: unlocks recruits, rumors, safe houses, cheaper prices.
- **Infamy** with the Sheriff: rises with big hits; increases bounties, traps and Guy's attention.

---

## 4. Tactical layer (linear missions)

### 4.1 Structure
A mission is a **left-to-right path of 3-6 nodes** on a location-themed backdrop (forest road, castle courtyard, abbey cloister). Movement between nodes is automatic. Node types:
- **Combat** encounter
- **Choice** (sneak vs. fight, bribe the guard, spare the tax collector)
- **Loot** (strongbox, wagon)
- **Hazard / Trap** (snare, pit, ambush, locked gate)
- **Objective** (the wagon, the prisoner, the abbot's chest)
- Optional **branch** of one extra node (risk vs. reward), keeping the overall shape linear.

### 4.2 Turn-based combat (side-view, initiative timeline)
- Party of **up to 4** vs. 2-6 enemies, side-view lines (front row / back row), JRPG style; fits portrait mobile well.
- **Initiative timeline** shown at the top so players can plan.
- Each character has 2 AP per turn: attack, ability, item, swap rows, defend.
- **Positioning matters lightly:** front row melee, back row archers; some abilities push/pull rows.
- **Status effects:** pinned (arrow), stunned, bleeding, inspired, hidden, captured (see traps).
- **Morale:** enemies can break and flee when their leader falls; fitting for outlaws who prefer not to kill.
- **Non-lethal option:** knockouts vs. kills affect Reputation and story outcomes.
- **Win/escape:** you can always attempt a retreat; failure means a companion may be captured.

### 4.3 Enemies (typical Robin Hood foes)
| Enemy | Role |
|---|---|
| Sheriff's Men-at-Arms | Basic melee, shield wall |
| Crossbowmen | Ranged, pin targets |
| Mounted Knights | High HP, charge attack hits back row |
| Foresters / Verderers | Trackers, reveal hidden units, set snares |
| Tax Collectors & guards | Weak, flee with gold if not stopped quickly |
| Mercenaries / Bounty Hunters | Target the highest-bounty party member |
| Hounds | Fast, interrupt stealth |
| Corrupt Clergy's guards (Abbot of St Mary's) | Defensive, heal each other |
| **Sir Guy of Gisborne** (boss) | Duelist, horse-hide disguise (legend), sets traps mid-fight |
| **Sheriff of Nottingham** (boss) | Commander, buffs troops, calls reinforcements, rarely fights directly until finale |
| Others for later chapters: Prince John's agents, the Prioress of Kirklees, Red Roger | Story bosses |

---

## 5. Party and characters

Party members are recruited through their **story missions**, many based on the classic "fight then join" tales.

| Character | Recruitment story | Class / role | Signature ability |
|---|---|---|---|
| **Robin Hood** | Starting | Archer leader | *Split the Arrow*: precision shot, crit on marked targets |
| **Little John** | Quarterstaff duel on the bridge | Tank / bruiser | *Bridge Hold*: taunt and counter |
| **Will Scarlet** | Duel in the forest / rescue from hanging | Duelist DPS | *Flourish*: multi-hit, bonus vs. knights |
| **Friar Tuck** | River-crossing duel at Fountains Abbey | Healer / brawler | *Blessing* heal, *Tavern Brawl* stun |
| **Maid Marian** | Disguised duel / Blidworth story | Infiltrator / support | *Disguise*: reveal traps, start fights hidden |
| **Much the Miller's Son** | Rescue from the Sheriff's foresters | Scout / utility | *Scout Ahead*: reveal mission nodes, disarm traps |
| **Alan-a-Dale** | Rescue his bride from a forced wedding | Bard / buffer | *Ballad*: party-wide inspire |
| **Arthur a Bland** | Tanner's duel | Off-tank | *Hide Like Leather*: damage reduction |
| **David of Doncaster** | Archery contest | Second archer | *Volley*: AoE arrows |
| **Sir Richard at the Lee** | Gest: Robin lends him money | Knight ally | *Shield Charge*, unlocks safe house |
| Generic Merry Men | Recruited with Reputation | Fill-ins | Small trait pools (procedural) |

**Progression:** XP levels, a small talent tree per hero (2 branches), 3 equipment slots (weapon, armor, trinket). Bonds between companions give passive bonuses when deployed together (e.g. Robin + Marian, John + Tuck).

**Capture, never permadeath**: a downed hero who isn't recovered by mission end is *captured* and held at a location; this spawns a rescue mission with a timer. If the timer expires, the hero is moved somewhere harder (castle dungeon). No hero ever dies.

---

## 6. Missions

### 6.1 Mission types
1. **Robbery**: tax wagons, rich merchants, corrupt abbots, the Sheriff's treasury. Reward: gold.
2. **Rescue**: captured companions, villagers to be hanged, a bride forced to marry. Reward: recruits, reputation.
3. **Story missions** (hand-authored): the legends, in chapters (section 8).
4. Supporting types (later): **Escort** (smuggle grain to a starving village), **Sabotage** (burn the toll booth), **Archery Contest** (special mini-mode, the Sheriff's famous trap).

### 6.2 Procedural generation
A mission is assembled from data, not code:

```
Mission = Template(type) + Location(biome, backdrop, node slots)
        + Objective + Enemy faction & tier (from region control + infamy)
        + Modifiers (weather, night, patrol, rich target)
        + Traps (from Sheriff/Guy plan, see section 7)
        + Rewards (scaled by risk)
```

- **Templates** define node sequences with slots, e.g. Robbery = `[Approach] -> [Combat|Choice] -> [Objective: wagon] -> [Escape: Combat]`.
- **Location** picks backdrop art and allowed enemy types (no knights inside the abbey cloister, etc.).
- **Difficulty budget**: each node gets a point budget for enemies; the generator buys enemies from the faction's list.
- **Seeded RNG** so missions are reproducible (debugging, and to stop save-scumming).
- **Authored "set pieces"** can be injected into procedural missions (a famous NPC appears, a rumor pays off).

### 6.3 Mission briefing
Before launching: objective, estimated enemies, known traps (more with scouting), rewards, travel days, and which companions the target "suits".

---

## 7. The Big Bads: Sheriff and Guy

They are **AI directors** that act on the strategic map every day, and they plant what the player meets in missions.

### 7.1 Sheriff of Nottingham: the Schemer (economic & political)
- Raises taxes in regions (reduces village rewards, raises Reputation gain for helping).
- Posts **bounties** on specific heroes (attracts bounty hunters).
- Sets **bait missions**: a fake rich wagon or a public hanging that is really an ambush (the "archery contest" trap from the legend is his signature).
- Seizes caches: destroys supply stashes the player left unguarded.
- Garrisons towns to deny recruitment.

### 7.2 Sir Guy of Gisborne: the Hunter (tactical)
- Hunts the band on the map; can intercept you during travel.
- Plants **traps inside missions**: nets, pit snares, tripwire bells, locked gates, hidden crossbowmen.
- Targets a specific companion ("Guy is hunting Little John") and designs traps to capture them.
- Shows up personally as a mini-boss when infamy is high.

### 7.3 Trap system
- Traps are placed on mission nodes by the director when a mission is generated.
- Each trap has a **target** (random, a specific hero, or "whoever carries the loot"), an **effect** (capture, damage, steal loot, summon reinforcements, cut retreat) and **counters** (scouting reveals it, Much disarms, Marian's disguise bypasses, choose a different path).
- Being trapped is *recoverable*: a netted hero can be freed by spending an action before the enemy drags them off at end of next round.

### 7.4 Escalation
Director "threat level" scales with Infamy and story chapter; each Big Bad has a visible **Plot meter** on the map (when full, they launch a big scheme: a raid on camp, a fake hanging of a captured hero, a castle siege event). This gives the player readable, telegraphed pressure.

---

## 8. Story structure (one persistent campaign) **[DEFAULT: 5 chapters, rest procedural]**

1. **Outlaw** (Locksley, Sherwood): Robin is outlawed, meets Little John at the bridge, first robbery. Tutorial.
2. **The Band Gathers**: Will Scarlet, Much, Friar Tuck. Introduce Guy and traps.
3. **The Knight and the Abbot** (Gest): help Sir Richard at the Lee, rob the Abbot of St Mary's.
4. **The Golden Arrow**: the Sheriff's archery contest trap, Marian, Alan-a-Dale's wedding rescue.
5. **Nottingham**: break the Sheriff's control, duel Guy, storm the castle (and optionally King Richard's return as an epilogue).

Each chapter has 3-5 authored story missions; procedural missions fill the gaps and build resources between them. Kirklees (Robin's death) is reserved for an optional epilogue or expansion.

---

## 9. Technical plan

### 9.1 Platform and engine (decided)
- **Godot 4.x with GDScript**, chosen by Claude. It exports native Android and iOS apps, has first-class pixel-art support (nearest filtering, integer scaling), is free with no royalties, and GDScript keeps the codebase small and readable. No ads or monetization SDKs are needed, which removes Unity's main advantage.
- Android first, iOS port in Phase 6.
- **Offline single-player**, local saves; cloud save later.

### 9.2 Architecture
```
/game
  /data        # JSON/Resources: heroes, enemies, abilities, items, locations, mission templates, traps
  /core        # Pure logic, no UI: combat rules, mission generator, director AI, economy, save/load
  /scenes      # Strategic map, mission path, combat, camp, menus
  /ui          # Reusable widgets
  /tests       # Unit tests for core (GUT for Godot)
```
- Keep **game logic separate from presentation** so combat and generation are testable and tunable.
- **Deterministic, seeded RNG** throughout core logic.
- Content defined in data so new heroes, enemies, missions and traps need no code.
- A small **simulation harness** that auto-plays thousands of generated missions to balance difficulty and rewards.

### 9.3 Art and audio
- **Pixel art** (decided). Base resolution 360x640 portrait, integer-scaled; 32x32 combat sprites, 64x64 portraits, limited warm forest palette. Map drawn as a pixel parchment with illuminated-manuscript accents.
- Character art: pixel portraits + side-view combat sprites with 3-4 animations each (idle, attack, hit, down).
- Placeholder art during prototyping (free asset packs or generated placeholders), final art later.
- Audio: medieval folk score (lute, recorder, drums), simple SFX.

---

## 10. Development roadmap

| Phase | Goal | Contents | Exit criteria |
|---|---|---|---|
| **0. Pre-production** | Decide the open questions; lock scope | This doc, answers, repo setup, paper prototype of combat | Questions answered, repo created |
| **1. Combat prototype** | Is the turn-based fight fun? | 4 heroes (Robin, John, Will, Tuck), 6 enemy types, 1 boss (Guy), placeholder art | 10 fights feel distinct and fair |
| **2. Mission prototype** | Linear missions + generation | Robbery & rescue templates, 3 locations, traps v1, rewards | Generator produces 100 valid, varied missions |
| **3. Strategic layer** | The full loop | Map with ~8 nodes, auto-travel, days, resources, camp, capture & rescue | A player can play a 30-minute run |
| **4. Vertical slice ("first playable")** | One polished chapter | Chapter 1 story missions, Sheriff/Guy director v1, final art for slice, tutorial, save/load | Playtest-ready build on Android |
| **5. Content production** | Chapters 2-5 | Remaining heroes, enemies, locations, story missions, balance | Full campaign playable |
| **6. Polish & launch** | Ship | UX, performance, accessibility, store assets, iOS port, analytics | Store release |

**Proposed first playable scope (phase 4):** Chapter 1, 4 heroes, ~8 enemy types + Guy, Sherwood/Great North Road/Locksley/Nottingham outskirts, robbery and rescue procedural missions, trap v1, one Sheriff scheme (bait wagon).

---

## 11. Risks

- **Scope**: RPG + strategy + procgen is a lot. Mitigation: data-driven content, strict first-playable scope, cut supporting mission types until later.
- **Procedural sameness**: Mitigation: authored set pieces, location-specific node pools, director-driven twists.
- **Trap frustration**: losing companions can feel unfair. Mitigation: telegraph traps, always offer counters, capture instead of death, generous rescue timers.
- **Mobile UX**: small screens. Mitigation: portrait, large tap targets, combat readable at a glance, speed-up toggle.
- **Art cost**: Mitigation: limited animation, reusable backdrops, decide style early.
- **Pricing**: a one-time purchase needs strong store presentation and a free demo or launch discount; no recurring revenue.
- **IP**: Robin Hood legends are public domain; avoid elements unique to modern films/TV (e.g. specific invented characters like Azeem from *Prince of Thieves*).

---

## 12. Decisions (answered 2026-10-19)

| # | Question | Decision |
|---|---|---|
| 1 | Platform | Standalone native mobile app (Godot 4, Android first, then iOS) |
| 2 | Who codes | Claude, in GDScript |
| 3 | Art style | Pixel art |
| 4 | Monetization | One-time purchase, no ads or IAP |
| 5 | Tone | Family adventure |
| 6 | Companion loss | No permadeath; capture and rescue |
| 7 | Combat layout | Side-view party lines |
| 8 | Structure | One persistent campaign |
| 9 | Repository | New GitHub repo |

Still open: whether the Phase 4 first-playable scope is the right size (assumed yes).
