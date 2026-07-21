# Gear and Loot Progression

## Locked rules

- `requiredLevel` is the minimum equip level, not the final power level. Once equipped at or above
  that floor, positive stats scale with player level. Rarity controls the growth rate.
- Rarity is explicit and separate from elemental or stat identity:
  `common -> uncommon -> rare -> epic -> legendary -> titan`.
- Dragon Scale is the highest normal acquisition family: it may be crafted, purchased at apex shops,
  or looted from appropriate dragons and bosses.
- Titan is above Dragon Scale and is never craftable or sold. Titan equipment may only appear at very
  low probability from world bosses, Raid bosses, or Expedition bosses.
- Content validation must reject Titan gear in recipes or shops and must require every Titan item to
  have a boss/world-boss source at one percent or lower.

## Dragon affinities

Dragon color describes build identity; it does not replace rarity.

| Color | Identity | Current use |
| --- | --- | --- |
| Green | vitality and sustain | Dragon Scale Armor; common dragon drops |
| Blue | focus and learned power | Blue Dragon Codex; Glacial Drake drops |
| Silver | defense and stability | Silver Dragon Bow; Cliff Drake drops |
| Black | precision and speed | black scale material; future precision set pieces |
| Red | direct power | Red Dragon Sabre/Maul; Inferno and Raid boss drops |
| Gold | balanced apex | rare world-boss material; apex armor tempering |

Two equipped `dragon_scale` pieces activate Dragon Scale Harmony. The weapon's color selects the
active Harmony stats, and the bonus grows at level milestones.

## Current acquisition ceiling

- Level 48 legendary Dragon Scale armor and four weapon roles are the apex normal craft tier.
- Level 48/60 Titan weapons are boss-only relics with explicit provenance.
- Legacy IDs remain stable for save compatibility even where the player-facing item name was promoted
  into Dragon or Titan identity.

## Next depth

1. Add head/hands/feet Dragon pieces so three- and four-piece bonuses can be authored and compared.
2. Give Black and Gold affinities complete weapon/set representation.
3. Add Raid/Expedition reward tables with pity counters before increasing Titan catalogue size.
4. Add affixes only after fixed rarity, scaling, set, and provenance rules are proven in normal play.
