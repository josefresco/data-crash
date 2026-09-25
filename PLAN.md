# GAME DESIGN DOCUMENT: DATA CRASH (Working Title)

---

## 1. Executive Summary & Core Premise

**Data Crash** is an action-adventure hybrid combining first- or third-person open-world action (*Grand Theft Auto* style) with strategic base building and wave defense (*Tower Defense* mechanics).

Set in a near-future suburb choked by runaway artificial intelligence infrastructure, the game places players in the shoes of a local resident fighting back against predatory tech conglomerates.

### The Pitch

You wake up in your home to a deafening low-frequency drone, thick brown smog, and zero water coming from your faucets. Just outside your window looms a massive, water-guzzling corporate datacenter. Your mission: organize your neighborhood, sabotage and demolish the resource-draining "bad" datacenters, and replace them with community-owned, zero-water, solar-powered "green" datacenters—defending them against corporate mercenaries and militarized forces.

---

## 2. Core Gameplay Loop: The Eco-Reclaim Cycle

Each district or zone follows a distinct three-phase progression loop:

```
[ Phase 1: Local Activism ] ➔ [ Phase 2: Datacenter Assault ] ➔ [ Phase 3: Green Defense & Growth ]
    (Open-World Prep & Cash)        (Shooter / Demolition)              (Tower Defense / Rebuilding)

```

### Phase 1: Local Activism (Open-World / Prep)

* **Objective:** Earn funds, build community trust, gather materials, and scout corporate targets.
* **Activities:** Complete good deeds for neighbors (fixing sabotaged water mains, intercepting corporate supply trucks, taming guard dogs).
* **Environment:** Bleak, industrial, and polluted. High noise levels degrade NPC morale and limit community support.

### Phase 2: Datacenter Assault (Shooter / Infiltration)

* **Objective:** Infiltrate, disable, and demolish corporate data hubs.
* **Activities:** Breach perimeter fences, hack cooling systems, plant explosives, disable backup generators, and defeat site bosses while fighting off private security.

### Phase 3: Green Defense & Community Growth (Tower Defense)

* **Objective:** Build a clean, solar-powered datacenter and hold the zone while the ecosystem recovers.
* **Activities:**
* Lay down solar arrays, dry-cooling infrastructure, and battery storage.
* Construct neighborhood defenses (turrets, EMP traps, barricades, drone bays).
* Repel counter-attacks from corporate security and police forces trying to reclaim the site.


* **Reward:** The sky clears, grass returns, water flows back to homes, and local residents join as active defenders and vendors.

---

## 3. Worldbuilding & Visual Style

### Visual Aesthetic

* **Style:** Stylized Low-Poly / Cel-Shaded (similar to *Teardown* or *Borderlands*).
* **Rationale:**
1. **Physics & Destruction:** Simplifies dynamic destruction physics when breaching walls or collapsing server halls.
2. **Environmental Contrast:** Delivers a striking visual transition from grey, smoggy, dead neighborhoods to vibrant, green, restored districts.
3. **Readability:** Provides high visual clarity for placing traps, reading enemy sightlines, and tracking wave movements during Tower Defense phases.



### Environmental Dynamics as a HUD

* **Noise Pollution Meter:** High decibel levels reduce NPC trust and restrict stealth capabilities.
* **Local Water Table:** Restoring groundwater unlocks unique community buffs, craftable hydro-traps, and local NPC support.

---

## 4. Factions & Enemy Roster (ENEMIES.md)

### The Bosses (Executive Suite)

#### Elmo Mushbrains

* **Role:** Rogue Tech CEO & Hype-Man.
* **Encounters:** Drives an armored **Felsa Truck** around the arena trying to ram the player while broadcasting corporate monologues. Deploys "Beta Feature" shockwaves. On foot (Phase 2), he uses a flamethrower and occasionally pauses to post updates, leaving himself vulnerable.

#### Fark Suckerbush

* **Role:** Surveillance King.
* **Encounters:** Fights from inside a glass command pod. Summons holographic clones, tracks player sightlines with surveillance drones, and temporarily reverses player controls using "Algorithm Re-education."

#### Harry Perckerson

* **Role:** Venture Capital Heavyweight.
* **Encounters:** Stays behind reinforced boardroom glass, throwing "Capital Subsidies" to constantly summon waves of Private Security and FROST agents. Requires heavy explosives or environmental hazards to breach his enclosure.

#### Sham Crapman

* **Role:** Synthetic Evangelist.
* **Encounters:** Uses flying AI projection drones that project force fields around target datacenters. Fires energy blasts powered by the facility's power grid—destroying active cooling units weakens his attacks.

#### Crapya Butella

* **Role:** Cloud Infrastructure Titan.
* **Encounters:** Operates automated facility defenses (ceiling turrets, superheated steam vents, server-rack crushers). Forces players to navigate environmental hazards while managing incoming security guards.

---

### Standard Enemy Types

| Enemy Unit | Behavior & Tactical Role | Weaponry / Attack | Tactical Counter |
| --- | --- | --- | --- |
| **Private Security** | Aggressive corporate mercenaries guarding bad datacenters. | Assault rifles, stun batons, smoke grenades. | Flashbangs, standard firearms, flanking routes. |
| **Local Police** | Neutral law enforcement bound to "maintain order" at both bad and green sites. | Riot shields, tasers, tear gas, barricades. | EMP weapons, non-lethal crowd control, non-violent distractions. |
| **FROST** | Heavy armored tactical agents that abduct townspeople to lower community morale. | Capture launchers, zip-ties, heavy body armor. | Priority target—must be neutralized before kidnapping key NPCs. |
| **Dogs** | Fast pursuers that tackle and slow down the player. | Bite attacks (low damage, movement slowdown). | Throwing "Good Boy Treats" converts them permanently into friendly neighborhood guardians. |
| **Orange Hat NPCs** | Misinformed local supporters who protest green builds and block attacks on corporate sites. | Picket signs, blocking vision, forming human chains. | Megaphones, community persuasion buffs, non-lethal distraction items. |
| **Felsa Cars** | Unmanned, erratic electric vehicles roaming perimeters. | High-speed ramming attacks. | Hackable via EMP/decking tools to cause battery fires or hijack controls. |

---

## 5. Arsenal & Equipment Progression (WEAPONS.md)

### Level 1: Grassroots Sabotage (Improvised & Non-Lethal)

* **Molotov Cocktail:** Creates fire zones; burns down guard huts and clears **Orange Hat NPC** blockades.
* **Recon Drone:** Tags enemies, highlights thermal cooling vents, and lures **Local Police** toward **Private Security** zones to trigger inter-faction fights.
* **Garden Water Hose:** Short-circuits exposed electrical supply lines and low-voltage generators.
* **Rocks:** Smashes security camera lenses, breaks windows, and lures guards away from stealth paths.
* **Civilian Cars:** Rams perimeter chain-link fences and wooden gates to create assault entry points.
* **Converted Dogs:** Tamed using treats; chases away low-tier guards and acts as stealth support.

---

### Level 2: Tactical Escalation (Ranged Firearms & Heavy DIY)

* **Medium Improvised Explosive (C4/Satchel):** Planted on structural targets, cooling manifolds, and server racks to cause massive facility damage.
* **FPV Strike Drone:** Delivers flying medium-explosive payloads; directly counters roof-mounted radar and boss shield drones.
* **Pistol:** Low-noise sidearm suited for close-quarters firefights against unarmored security.
* **Shotgun:** High-spread damage; counters defensive security drones and close-range **FROST** squads.
* **Hunting Rifle:** Long-range precision rifle for taking down sniper towers, spotlight operators, and guard outposts.
* **Fire Hose:** High-volume water stream that sweeps back **FROST** squads, knocks down riot shields, and short-circuits main server racks.

---

### Level 3: All-Out Siege (Military Grade & Heavy Equipment)

* **Grenades:** Purchased at local gun shows; ideal for clearing grouped **FROST** units and breaking **Local Police** riot-shield lines.
* **Machine Guns:** Sustained high-rate suppressive fire for holding the line during Phase 3 wave defenses.
* **Rocket Launchers:** Stolen from corporate security caches; destroys armored **Felsa Trucks**, command pods, and mega-cooling towers.
* **Bulldozers & Excavators:** Provided by sympathetic construction worker NPCs; smashes main facility walls, bypasses perimeter traps, and crushes heavy defenses.

---

## 6. Community Systems & Global Mechanics

### Bribery System

Earn cash by completing neighborhood goals and spend it to influence local systems:

* **Municipal Delays:** Bribe officials to slow down corporate construction or delay police response times during an attack.
* **Supply Blockades:** Bribe freight operators to reduce enemy reinforcement spawns during boss fights.
* **Zoning Permits:** Bribe town boards to auto-grant land permits, starting Phase 3 with pre-built defensive walls.

### NPC Community Mob ("The People's Shield")

* **Distraction Operations:** High community reputation brings local townspeople out to form protest lines, drawing **Local Police** and **Orange Hat NPCs** away from facility entrances.
* **Tower Defense Repair Crew:** During Phase 3, neighbors automatically repair solar panels, restock ammo crates, and man non-lethal defense turrets alongside the player.