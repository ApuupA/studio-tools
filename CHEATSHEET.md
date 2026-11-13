# `studio` Cheat Sheet

`PROJECT` = any part of the project name (`night`, `demo`, `mix`). Leave it out and you get a list.
**Tab** completes commands, options and project names. `studio help` shows the short list.

## Every day

| Command | What it does |
|---|---|
| `studio init [folder]` | Set up (or repair) the Studio folder: structure, double-click files, Terminal command |
| `studio start` | Studio Mode on: Focus, quits distracting apps, keeps Mac awake, checks disk/SSD/backup, opens a session |
| `studio end` | Waits for the DAW to close, asks for a session note, backs up to the SSD, Studio Mode off |
| `studio status` | Overview: free space, backup, session, all projects with type, size and last note |
| `studio backup` | Backup to the SSD now, without ending the session |

## Projects

| Command | What it does |
|---|---|
| `studio new` | **Guided:** asks type, artist, title, code, DAW, template, songs |
| `studio new "Artist" "Title" "Song 1" "Song 2"` | New full-production project directly |
| `studio add` | **Guided:** pick project, DAW, template, type the songs |
| `studio add PROJECT "Song" "Song"` | Add songs (next free numbers) |
| `studio add PROJECT` | Only fill empty song folders with template sessions |
| `studio list` | Quick project list |
| `studio open PROJECT` | Open the project folder in Finder |
| `studio cd PROJECT` | Go to the project folder in Terminal |

**Options for `new`**

| Option | Values |
|---|---|
| `--type` | `full` (default) · `rec` · `mix` · `write` · `master` |
| `--daw` | `pt` · `cb` · `both` (default: `cb` for write, `pt` otherwise) |
| `--pt NAME` / `--cb NAME` | Template from `03_LIBRARY/Templates/ProTools` / `Cubase` |
| `--code XXXXX` | Short artist code for file names (default: first 5 letters) |

`add` takes `--daw`, `--pt`, `--cb` too. `studio add --daw cb PROJECT` adds Cubase folders to all songs.

```bash
studio new --type mix "Nightfall" "Album Mix" "Song 1" "Song 2"
studio new --type master "Nightfall" "Demo" "Song 1" "Song 2"
studio new --type write "Nightfall" "New Album" "Riff 1"
```

## Mixes, masters, delivery

| Command | What it does |
|---|---|
| `studio check [PROJECT]` | Checks `07_Received`: sample rate, length, bit depth, MP3s, clipping, silence |
| `studio check /path/to/folder` | Same for any folder (e.g. in `00_INBOX`) |
| `studio mp3 [PROJECT]` | MP3s of the final mixes/masters into an `MP3` subfolder |
| `studio mp3 --all [PROJECT]` | MP3s of every version |
| `studio mp3 file.wav` | MP3 of single files, next to the file |
| `studio approve [PROJECT]` | Choose the approved version when it is **not** the newest |
| `studio deliver [PROJECT]` | Client package in `06_Deliverables`: asks what to deliver (masters, mixes, stems – any combination), adds MP3s, tracklist and zip |

`deliver`: at the question type one or more numbers (`1 2`, `1;3`, `a` = all).
Direct options: `--masters` · `--mixes` · `--stems` · `--demos` · `--songs` · `--all` · `--no-mp3` · `--no-zip`

## Finishing and maintenance

| Command | What it does |
|---|---|
| `studio archive [PROJECT]` | Copies to the archive SSD, verifies, keeps finals in `03_LIBRARY/Portfolio`, then asks to trash the local copy |
| `studio archive --no-keep [PROJECT]` | Same, without keeping finals on the Mac |
| `studio plugins` | Inventory of all plugins (versions) and sample libraries (size, location); shows changes since the last one. Run before every update |
| `studio tags` | Re-apply the coloured Finder tags to all projects |
| `studio help` | Command list |

## Naming

| What | Pattern | Example |
|---|---|---|
| Session | `CODE_##_Song_STAGE_v##` | `NIGHT_01_Opener_TRK_v01.ptx` |
| Stages | `TRK` → `EDT` → `MIX` | new version = *Save As* |
| Mix bounce | `CODE_##_Song_Mix_v##` | `NIGHT_01_Opener_Mix_v03.wav` |
| Variant | after the version | `NIGHT_01_Opener_Mix_v03_Instr.wav` |
| Master | `CODE_##_Song_Master_v##` | `NIGHT_01_Opener_Master_v01.wav` |

Final version = highest `_v##`, unless `studio approve` says otherwise.

## Project types

| Type | Folders | Sessions | Tag |
|---|---|---|---|
| `full` | 03_Mixes 04_Stems 05_Masters 06_Deliverables | one per song, `TRK` | red |
| `rec` | 03_Mixes 06_Deliverables | one per song, `TRK` | orange |
| `mix` | 03_Mixes 04_Stems 06_Deliverables 07_Received | one per song, `MIX` | blue |
| `write` | 03_Demos 04_Ideas 05_Songs (in `02_WRITING/<band>/`) | one per song, Cubase | green |
| `master` | 05_Masters 06_Deliverables 07_Received | one session for all songs | purple |

Every type also has `00_Admin`, `01_Reference`, `02_Sessions`.

## Double-click instead of typing

`Start_Session.command` = `studio start` · `End_Session.command` = `studio end`

Settings: `studio.local.conf` (yours) over `studio.conf` (defaults) · Logs: `<Studio>/99_SYSTEM/Logs/` · Details: `README.md`
