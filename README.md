# CorpseCamp

A WoW Forever addon that plays a loud alert the moment the enemy player you're camping resurrects.

You kill someone and CorpseCamp starts watching for them. When they come back, either rezzed in place or after running back as a ghost, you hear the raid warning three times, `Name RESURRECTED!` shows across your screen, and the game icon flashes in your taskbar. Sound plays on the Master channel, so it reaches you even with game sound muted or the client in the background.

## Install

1. Download `CorpseCamp-<version>.zip` from [Releases](https://github.com/drptbl/corpsecamp/releases).
2. Extract it into `World of Warcraft/_forever_/Interface/AddOns/`.
3. Restart the game client. A `/reload` doesn't pick up a new addon.
4. Type `/ccamp setup` once, out of combat. This turns on enemy nameplates, always shows them, and raises the nameplate range to 41 if it's lower.

## Usage

Kill an enemy player while they're your target. CorpseCamp prints `camping Name-Realm`, and a status line with a timer appears at the top of the screen. Stay within about 40 yards of the corpse.

The skull on your minimap:

| Action | Result |
| --- | --- |
| Left-click | open the panel |
| Right-click | camp your current target |
| Drag | move it around the minimap |

The icon is grey while you're not camping anyone, and turns red when they resurrect.

The panel shows who you're camping, their state and a running timer. Its buttons do the same as the commands below. Type a name into the box and press Enter to camp someone you can't target. Drag the panel to move it. Esc closes it.

| Command | What it does |
| --- | --- |
| `/ccamp` | camp your target. If they're still alive, the alert arms once they die |
| `/ccamp Name` | camp a player by name |
| `/ccamp stop` | stop camping |
| `/ccamp status` | print who you're camping and for how long |
| `/ccamp test` | play the alert once |
| `/ccamp setup` | set up nameplates (out of combat only) |
| `/ccamp ui` | open the panel |

You can bind a key to target the camped player under Key Bindings => AddOns => CorpseCamp. It runs `/targetexact Name`. Addons aren't allowed to change your target, so you press the key yourself.

## How it works

WoW Forever doesn't let addons read the combat log, so CorpseCamp can't see the kill or the resurrection directly. Instead it checks your target, focus, mouseover and every visible nameplate, five times a second and on every nameplate event.

Enemies can't see a ghost. So if the player you're camping shows up alive after being seen dead, they've resurrected. The alert fires once per death and re-arms when they're seen dead again.

The Forever client hides some unit values from addons. Every read is guarded, so a hidden value never breaks the scan.

## Limits

- Detection range is nameplate range, about 40 yards. Beyond that, nothing an addon can see changes when they rez.
- A spirit healer rez at the graveyard can't be detected. The "ghost or out of view" timer just keeps counting.
- An enemy hunter's Feign Death may look like a death. If so, them standing up sets off the alert.
- This version hasn't been verified in the live client yet. If something doesn't work, open an [issue](https://github.com/drptbl/corpsecamp/issues) and attach a CampProbe log.

## CampProbe

CampProbe is an optional diagnostic addon. It logs what the client lets an addon see about enemy players, both in and out of combat. It's only useful when CorpseCamp misbehaves.

1. Install `CampProbe-<version>.zip` the same way, then get one kill and stay near the corpse while they run back.
2. Use `/probe` to dump your target and `/probe plates` to dump the visible player nameplates.
3. Attach `WTF/Account/<ACCOUNT>/SavedVariables/CampProbe.lua` to the issue.

## Development

You need `luajit` (`brew install luajit`).

| Command | What it does |
| --- | --- |
| `make addon-link` | symlink `CorpseCamp/` into the Forever AddOns folder, so a `/reload` loads your edits |
| `make probe-link` | the same for `CampProbe/` |
| `make test` | run the state machine tests and the addon against a stubbed WoW API |
| `make dist` | build the release zips into `dist/` |

`make addon-link WOW_ADDONS=<dir>` points the link at another AddOns folder.

## License

[MIT](LICENSE)
