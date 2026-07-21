# Asset License Audit

The external source pool is the full `D:\Asset Library` tree: both `Assets` and `Assets 2`.
Presence in that library means **available for inspection**, not automatically cleared for a
commercial release. Runtime files remain repo-local and must have recorded provenance.

See [`ASSET_LIBRARY_GUIDE.md`](ASSET_LIBRARY_GUIDE.md) for selection rules,
[`ASSET_MANIFEST.md`](ASSET_MANIFEST.md) for runtime authorities, and
[`ASSET_PURCHASE_BACKLOG.md`](ASSET_PURCHASE_BACKLOG.md) for known release debt.

## Audit scope and limitation

The current `npm run reboot:audit-assets` default scans only `D:\Asset Library\Assets`.
Its `.external-cache/asset-library-index.json`, `license-findings.json`, and scored candidate
output therefore omit `D:\Asset Library\Assets 2`. Treat those files as search aids, never as
proof that the whole library was reviewed or that an omitted pack is forbidden.

The release-facing import registry is `assets/licenses/asset-manifest.json`; its generated view is
`assets/licenses/THIRD_PARTY_ASSETS.md`. Some owner-confirmed/manual imports predate full registry
reconciliation, so this policy page and `CREDITS.md` remain required cross-checks.

## Known runtime/import statuses

| Source family | Status | Basis / requirement |
| --- | --- | --- |
| Ninja Adventure - Asset Pack | Commercial-safe, in use | Local CC0 record; Pixel-boy & AAA |
| Kenney packs | Commercial-safe; some in use, some registered only | CC0 license files; verify exact runtime path rather than inferring use from import status |
| CraftPix imported packs | Commercial game use; registered, not confirmed in current runtime | CraftPix Free License; no raw-pack redistribution and no AI/ML training, testing, validation, or improvement use |
| Kyrise's 16x16 RPG Icon Pack V1.3 | Commercial-safe, in use | CC BY 4.0; attribution required |
| SERENE_VILLAGE_REVAMPED | Owner-confirmed commercial, in use | Keep entitlement record; imported-sheet note under `assets/licenses/` |
| sushi_pixel_set | Commercial game use, in use | Local readme: optional credit; no redistribution/resale, NFT use, or AI training |
| Sprout Lands Basic | Owner-confirmed commercial, in use | Keep entitlement record |
| PunyMonsters | Owner-confirmed commercial, in use | Keep entitlement record |
| Helton Yan's Pixel Combat SFX | Owner-confirmed commercial, in use | Keep entitlement record |
| EPIC RPG World Pack - Ancient Ruins demo | Development use; proof still required | Owner confirmed access, but archive explicit commercial terms before release |
| Farm RPG FREE 16x16 - Tiny Asset Pack | Development-only release debt | Purchase the commercial license or replace the tracked crops; see purchase backlog |

The locally licensed Quaternius collection is CC0 and remains a candidate until imported and used.
Registered Kenney/CraftPix files likewise remain imports rather than runtime art until a real loader,
catalog, or placement references them.

32rogues and the Super Retro World dungeon/exterior packs permit commercial game use but their local
licenses prohibit NFT and AI/ML/IA-related use; Super Retro World also requires author credit, and
both restrict raw redistribution. They are **not approved for this AI-assisted project** without
written clearance that covers the actual workflow.

## Blocked and unresolved

- `fishing_free` is non-commercial and must not ship.
- Do not import 32rogues or Super Retro World into this project without the written clearance above.
- Unknown/no-local-license packs may be inspected but cannot be imported into a release without
  explicit owner confirmation or source terms saved with the project records.
- Never ship ripped or fan assets, excluded commercial IP, CC BY-NC, CC BY-ND, personal-use-only,
  or license-ambiguous content.
- Raw third-party packs are never redistributed merely because an in-game derivative is allowed.

## Required evidence for a new source

Record the pack name, author, source URL/path, license text or entitlement, commercial-use status,
attribution, redistribution limits, exact selected files/crops, runtime destination, intended use,
and reviewer/date. Update the JSON registry and regenerate `THIRD_PARTY_ASSETS.md`; add human-facing
credit when the license requires it.
