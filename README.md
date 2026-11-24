# Studio Tools

A command-line workflow for a one-person recording studio on macOS: one folder structure for every
project, ready-named Pro Tools / Cubase sessions from templates, a backup at the end of every session,
safe archiving, client delivery packages – all behind one command, `studio`.

Built for engineers who record, mix and master on their own and don't want to think about files.

**What you get**

- `studio init` – the complete Studio folder structure in one step
- `studio new` / `studio add` – projects and songs with sessions already named, guided step by step
- `studio start` / `studio end` – Studio Mode (Focus, no sleep, no distractions) and a backup after every session
- `studio check` – finds wrong sample rates, short files, clipping in what clients send you
- `studio mp3` / `studio approve` / `studio deliver` – previews, final versions, client packages
- `studio archive` – verified copy to the archive drive, finals stay on the Mac
- `studio status` / `studio plugins` – overview of all projects; plugin and library inventory

All commands with options: [CHEATSHEET.md](CHEATSHEET.md)

## Quick start

Requirements: macOS with zsh (the default). Pro Tools and/or Cubase are optional – the folder structure,
backup and delivery work without them.

```bash
git clone https://github.com/ApuupA/studio-tools.git ~/studio-tools
~/studio-tools/studio init
```

`studio init` asks where your Studio folder should be (default `~/Studio`) and what your backup drive is
called. It then creates the folder structure, the two double-click files (`Start_Session.command`,
`End_Session.command`), your personal settings file and – if you say yes – the `studio` command with Tab
completion for the Terminal. It ends with a list of what is still to do. You can run it again at any time:
it never changes or deletes what is already there.

Then, in a new Terminal window:

```bash
studio new          # first project, guided
studio help         # all commands
```

Optional, but recommended:

```bash
brew install lame ffmpeg     # MP3s (macOS cannot write MP3s itself) and the peak / clipping check
```

**Your settings** live in `studio.local.conf` next to the scripts (created by `studio init`, ignored by git, so
updates with `git pull` never touch them). `studio.conf` lists everything you can set, with the defaults –
copy the lines you want to change into `studio.local.conf`.

## Folders

| Folder | What goes in |
|---|---|
| `00_INBOX` | Everything incoming (client files, downloads). Sort weekly. |
| `01_PROJECTS/<year>/` | Active projects, one folder each: `YYYY-MM_Artist_Title` |
| `02_WRITING/<NN_BAND>/` | Songwriting projects per band (`--type write`), e.g. `01_NIGHTFALL/2026-11_Nightfall_New_Album` |
| `03_LIBRARY` | Samples, IRs, presets, PT/Cubase templates, `Portfolio/` (finals of archived projects) |
| `04_ARCHIVE` | Finished projects waiting to go to the archive drive |
| `99_SYSTEM` | Logs and studio docs (plugin inventory, gear list, routing) |

### Project types

`studio new --type …` – folder numbers are the same in every type, unused ones are left out.

| Type | For | Folders | Sessions |
|---|---|---|---|
| `full` (default) | full production | 00 01 02 03_Mixes 04_Stems 05_Masters 06_Deliverables | one per song, `TRK` |
| `rec` | recording only, mix elsewhere | 00 01 02 03_Mixes (roughs) 06_Deliverables (multitracks) | one per song, `TRK` |
| `mix` | mixing received tracks | 00 01 02 03_Mixes 04_Stems 06_Deliverables 07_Received | one per song, `MIX` |
| `write` | songwriting (in `02_WRITING/<NN_BAND>/`) | 00 01 02 03_Demos 04_Ideas (memos) 05_Songs (final songs) | one per song, Cubase |
| `master` | mastering | 00 01 02 05_Masters 06_Deliverables 07_Received | **one** session `95_MASTER_Title`, songs = tracklist in the log |

`07_Received` = client files exactly as delivered – never edit there. The type is stored as `TYPE:` in
`Session_Log.txt`; `studio add` uses it automatically (old projects without it count as `full`).

### Inside a project (full production)

```
2026-10_Artist_Title/
├── 00_Admin/          Session_Log.txt, lyrics, notes, recall sheets
├── 01_Reference/      references, demos
├── 02_Sessions/
│   ├── PT/
│   │   ├── 01_Song_PT/            tracking + editing, one session per song
│   │   ├── 02_Song_PT/
│   │   └── 90_MIX_Title_PT/       big mix session (imported from 01–89)
│   └── CB/
│       ├── 01_Song_CB/
│       └── 90_MIX_Title_CB/
├── 03_Mixes/          Song_Mix_v01.wav …
├── 04_Stems/          stems, PT <-> Cubase transfers
├── 05_Masters/
└── 06_Deliverables/   final package for the client
```

**Mix session rule:** build `90_MIX_…` with *Import Session Data* (PT) / *Import Tracks from Project* (Cubase)
and **copy the audio** ("Copy from source media"). The mix session must never only reference audio
inside the song sessions. Consolidate edited tracks before importing. Note it in `Session_Log.txt`.

### Naming

- No spaces, umlauts or special characters. Use `_` and `-` (the scripts convert ä → ae etc.).
- Dates `YYYY-MM-DD`. Never "final" – the final version is the highest number, noted in `Session_Log.txt`.
- Every project has a short **artist code** (5 letters, e.g. `NIGHT`), stored as `CODE:` in `Session_Log.txt`.

**Sessions:** `CODE_##_Song_STAGE_v##`

```
02_Sessions/PT/01_Opener_PT/
├── NIGHT_01_Opener_TRK_v01.ptx    tracking
├── NIGHT_01_Opener_TRK_v02.ptx    after a milestone (Save As)
└── NIGHT_01_Opener_EDT_v01.ptx    editing – new stage starts at v01 again
02_Sessions/PT/90_MIX_Title_PT/
└── NIGHT_90_MIX_Title_v01.ptx
02_Sessions/CB/01_Opener_CB/
└── NIGHT_01_Opener_v01.cpr
```

- Stages: `TRK` (tracking) → `EDT` (editing) → `MIX`.
- All versions of a song stay in the same folder and share its audio – new version = *Save As*.
- New version at milestones (instrument done, before editing, before experiments, each mix round),
  not on every save – autosaves cover the rest.

**Bounces:** `CODE_##_Song_Type_v##[_Variant].wav`

```
NIGHT_01_Opener_Mix_v02.wav
NIGHT_01_Opener_Mix_v02_Instr.wav     variants after the version
NIGHT_01_Opener_Mix_v02_VocUp.wav
NIGHT_01_Opener_Master_v01.wav
```

Versions are always two digits (`v01`, `v02` … – sorts correctly everywhere). Use the same number for a
mix session and its bounce (`MIX_v04.ptx` → `Mix_v04.wav`).

**Which version is the final one?** Bounce every mix round into `03_Mixes` as `…_Mix_v01`, `_v02`, `_v03` …
(masters into `05_Masters` as `…_Master_v01` …). The scripts treat the **highest version of each song** as final,
together with its variants (`_v03_Instr`). If an older version wins (the band picks v03 although v04 exists),
run `studio approve` and choose it – that is stored in `_approved.txt` in the folder.
`studio deliver`, `studio mp3` and archiving (Portfolio) all use the approved version, otherwise the highest.

### Session templates

Projects and songs are created with ready-named sessions copied from a template:

```
03_LIBRARY/Templates/ProTools/TEMPLATE_48k/TEMPLATE_48k.ptx  (+ Audio Files …)
03_LIBRARY/Templates/Cubase/TEMPLATE_48k/TEMPLATE_48k.cpr
```

Create a template once:
- **Pro Tools:** *File → Create New → Create Blank Session* (NOT a .ptxt template), name `TEMPLATE_48k`,
  WAV, 48 kHz / 24 bit, I/O as you like, location `03_LIBRARY/Templates/ProTools/`. Add click/talkback etc., save, close.
- **Cubase:** new empty project, set 48 kHz / 24 bit, project folder `03_LIBRARY/Templates/Cubase/TEMPLATE_48k`,
  save as `TEMPLATE_48k.cpr`, close.

More templates (e.g. `TEMPLATE_48k_Band`, `TEMPLATE_48k_Vocals`) work the same way – choose with `--pt` / `--cb`.
Default templates: `PT_TEMPLATE` / `CB_TEMPLATE` in `studio.local.conf`.

**Which DAW:** only the chosen DAW gets song folders and sessions. Default: Cubase for `write`,
Pro Tools for everything else. Per call: `--daw pt`, `--daw cb` or `--daw both`.
Need the other DAW later? `studio add --daw cb <project>` adds Cubase folders + sessions for all songs
(the same works with `--daw pt` on a writing project).
Folders that already contain anything are **never** touched.

## Backup concept

| What | Where | When |
|---|---|---|
| **Time Machine** – the whole Mac incl. sample libraries, plugins, settings; keeps history | a Time Machine drive | automatically, hourly |
| **End-of-session copy** – 1:1 incremental copy of the Studio folder | backup drive → `Studio_Mirror/` | `studio end` / double-click `End_Session.command` |
| **Archive** – finished projects | backup drive → `Studio_Archive/<year>/` | `studio archive` |

- The backup drive is one external SSD (default name `Studio_Backup`, set by `studio init`). It holds
  `Studio_Mirror/` and `Studio_Archive/` (folder name: `ARCHIVE_FOLDER` in the settings). Take it home
  after the session and you have an off-site copy.
- The end-of-session copy is a **mirror**: only new/changed files are copied, files deleted in Studio
  are deleted on the drive too. Going back to older versions = Time Machine.
- Safety guard: if a backup would delete more than 200 files (`MAX_DELETE_FILES`), it stops and asks first.
- **Include the backup drive in Time Machine** (Time Machine settings → Options → remove it from the exclusion
  list). Otherwise archived projects exist only once.
- The first backup copies everything, later ones only the changes. On the first double-click macOS may block
  the `.command` file: right-click → Open, and allow Terminal access to the folder and the drive.

## Commands

Everything runs through **one command, `studio`**, with Tab completion (installed by `studio init`):

```bash
studio init                                    # set up / repair the Studio folder
studio start                                   # Studio Mode on (same as Start_Session.command)
studio end                                     # note, backup, Studio Mode off (same as End_Session.command)
studio new                                     # GUIDED: asks type, artist, title, DAW, template, songs
studio add                                     # GUIDED: pick project, DAW, template, type the songs
studio status                                  # overview: all projects, sizes, last notes, backup, session
studio check                                   # check received files in 07_Received before importing
studio mp3                                     # MP3 copies of the final mixes / masters (-> MP3 subfolder)
studio approve                                 # choose the approved version if it is not the newest
studio deliver                                 # client package: masters / mixes / stems + MP3 + tracklist + zip
studio archive                                 # pick project -> archive SSD (keeps finals on the Mac)
studio plugins                                 # plugin inventory – run before every update
studio tags                                    # re-apply the coloured Finder tags
studio list                                    # quick project list
studio open demo                               # open project folder in Finder
studio cd night                                # go to the project folder in Terminal
studio backup                                  # backup to the SSD now
```

**Guided mode:** `studio new` and `studio add` without anything behind them ask step by step.
Choices are numbered (`1) Pro Tools  2) Cubase  3) both`), **Enter takes the default or skips**,
songs are typed in one line separated by `;` (`Song 1; Song 2`). `studio new` shows a summary before it
creates anything, and prints the one-line command for next time.

The direct way still works, e.g.:

```bash
studio new --type mix "Artist" "Title" "Song 1" "Song 2"
studio new --type master "Artist" "EP Title" "Song 1" "Song 2"
studio new --type write "Nightfall" "New Album" "Idea 1"
studio add night "Bonus Track" "Outro"         # project by any part of its name
studio add --daw cb night                      # add Cubase folders + sessions to all songs
studio archive --no-keep mix
```

**Tab** completes commands, options (`--type <Tab>` → full rec mix write master) and project names
from any part of the name: `studio add nig<Tab>` → `2026-10_Nightfall_First_Light`.
If a search matches several projects, you get a list to choose from.
(The scripts still work directly too, e.g. `add_songs.sh night "Song"`.)

- **Start_Session**: Focus mode on, quits distracting apps (`QUIT_APPS`), keeps the Mac awake,
  checks free space / SSD / last backup, then lets you pick a project (most recent first) and opens its newest session.
- **End_Session**: waits until Pro Tools / Cubase are closed, asks "What did you do today?" (goes into the
  project's `Session_Log.txt` with the session time), backs up to the SSD, Focus off, Mac may sleep again.
- **Archive**: copies, verifies every file by checksum, **keeps the finals on the Mac** in
  `03_LIBRARY/Portfolio/<project>/` (newest version per song from `03_Mixes`, `03_Demos`, `05_Masters`, `05_Songs`, incl. variants
  like `_Instr` – see `ARCHIVE_KEEP_*` in `studio.conf`), then asks before moving the local copy to the Trash
  (and removes its now redundant copy from `Studio_Mirror`).
- **Finder tags**: every project folder gets a coloured tag for its type – Full production red, Recording orange,
  Mixing blue, Mastering purple, Songwriting green. Set automatically by `studio new`; `studio tags` re-applies
  them to all projects (your own tags on a folder are kept).
- **Check** (`studio check [project | folder]`): reads every audio file and flags a different sample rate, files
  that are shorter than the rest (not exported from the same start), different bit depth, MP3s among WAVs, files that
  hit 0 dBFS or are silent, and unreadable files. Report is saved to `00_Admin/Received_Check_<date>.txt`.
- **MP3** (`studio mp3`): 320 kbit/s copies of the final versions into an `MP3` subfolder, tagged with artist, album,
  title and track number. `--all` = every version; `studio mp3 file.wav` = single files.
  Needs `ffmpeg` or `lame` (`brew install lame`) – macOS itself cannot write MP3s. Same for the peak check: `ffmpeg`.
- **Deliver** (`studio deliver`): asks what to deliver – **masters, mixes, stems in any combination** (type one or
  more numbers: `1 2`, `1;3`, `a` = all). Shows the final files, then builds
  `06_Deliverables/<date>_<CODE>_<Title>_<Masters_Mixes_Stems>/` with `WAV/` + `MP3/` per part, the stems with their
  song folders (WAV only), a `Tracklist.txt` and a zip.
  Direct: `--masters` `--mixes` `--stems` `--all`, plus `--no-mp3` `--no-zip`. Stem versions are compared per song folder.
- **Plugin + library inventory** (`studio plugins`): lists every AAX / VST3 / VST / AU plugin with its version, the
  macOS, Pro Tools and Cubase versions, and all **sample / instrument libraries** with vendor, size and location
  (Native Instruments from its registrations incl. version; Toontrack, Steinberg, IK Multimedia, Spectrasonics, XLN,
  Arturia, `/Users/Shared`; folders of 100 MB and more). Libraries elsewhere, e.g. on another drive: add the folder
  to `LIBRARY_FOLDERS` in `studio.local.conf`. Saved to `99_SYSTEM/Studio_Docs/Plugin_Inventory/`, with a list of what
  changed since the last one. Run it **before** every macOS, DAW or plugin update.
- **Where libraries belong:** installed instrument libraries (EZdrummer, Superior, Kontakt …) stay **outside** the
  Studio folder – their own apps manage them, they can be downloaded again, and Time Machine covers them.
  `03_LIBRARY` is for what is yours and cannot be re-downloaded: own samples, IRs, NAM models, user presets, templates.
- Settings: `studio.local.conf` (yours) over `studio.conf` (defaults) · logs: `<Studio>/99_SYSTEM/Logs/`

## One-time setup after `studio init`

`studio init` shows which of these are still open (⬜) and which are done (✅).

1. **Session templates** – save one empty session per DAW into `03_LIBRARY/Templates/` (see *Session templates* above).
   Without a template, song folders are created empty.
2. **Backup drive** – name it as you told `studio init` (default `Studio_Backup`) and include it in Time Machine.
3. **Focus mode for `studio start` / `studio end`** – macOS only lets scripts change Focus through a Shortcut:
   Shortcuts app → new shortcut → action **"Set Focus"** → choose your focus → **On**. Name it exactly
   `Studio Focus On`. Make a second one with **Off** named `Studio Focus Off`.
   (German macOS: Kurzbefehle → "Fokus festlegen" → Ein / Aus. Other names: `FOCUS_*` in the settings.)
4. **Audio tools** – `brew install lame ffmpeg`.
5. **First inventory** – `studio plugins`, and again before every macOS, DAW or plugin update.

Moved the Studio folder or the tools folder? Run `studio init` again – it repairs the double-click files and
the Terminal command.

## Layout

The tools can live anywhere (`~/studio-tools`), with the Studio folder set in `studio.local.conf`. They can also
live *inside* the Studio folder at `<Studio>/99_SYSTEM/Scripts` – then the Studio folder is found automatically
and can be moved as a whole.

Git only ever sees the tools folder. Projects, audio, sessions, logs and inventories are in the Studio folder
and are never part of the repository.

## Licence and disclaimer

MIT – see [LICENSE](LICENSE). Use it, change it, share it.

These scripts copy, move and (after asking) delete files. They are built carefully – every archive copy is
verified by checksum, nothing is deleted without a question – but they come without any warranty. Try them on
a test folder first, and keep an independent backup such as Time Machine.
