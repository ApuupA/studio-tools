#!/bin/bash
# Shared parts of the sync between two Macs. Sourced after _common.sh.
#
# THE RULE: sync never deletes and never overwrites anything.
#   - a file that is replaced is MOVED to "<song>/Sync Backups/<date>/" first
#   - a song changed on both Macs comes in as a second, complete song folder
#   - files deleted on the other Mac are not deleted here
#
# How it works
#   A "unit" is one folder that travels as a whole: a song session folder
#   (02_Sessions/PT/03_Song_PT) or a project folder (00_Admin, 03_Mixes …).
#   For every unit this Mac keeps a record in <Studio>/99_SYSTEM/Sync/Units/:
#     <key>.fp     fingerprint (path, size, time of every file) at the last sync
#     <key>.state  UNIT, PROJECT, STATE, PEER, SINCE
#   STATE: lent (main gave it away) · home (main got it back) ·
#          borrowed (portable got it from main) · sent (portable sent it)
#   With that fingerprint every incoming file can be sorted out:
#     not here yet                  -> added
#     changed only on the other Mac -> old version moved to Sync Backups, new one in place
#     changed only here             -> kept, incoming ignored
#     changed on both               -> second copy, never replaced
#
# On the drive: Studio_Sync/
#   Packages/<FROM>__<project>/  info.txt, units.txt, Manifests/<key>.fp, Files/<Studio paths>
#   _Done/                       packages already brought in (kept, never deleted automatically)
#   Library/                     shared copy of 03_LIBRARY (add-only, both directions)
#   Machines/<name>.txt          plugin list of each Mac

REC_DIR="$STUDIO_ROOT/99_SYSTEM/Sync/Units"
PKG_DIR="$SYNC_DIR/Packages"
EXCLUDES="$SCRIPT_DIR/backup_excludes.txt"

# never part of a sync: caches, autosaves, our own backups
SYNC_RSYNC_EXCLUDES=(--exclude-from="$EXCLUDES" --exclude='Sync Backups/' --exclude='Session File Backups/'
                     --exclude='Auto Saves/' --exclude='*.csh' --exclude='WaveCache.wfm')

# fp <dir>: "path<TAB>size<TAB>mtime" of every file below <dir>, sorted
fp() {
    [ -d "$1" ] || return 0
    (cd "$1" && find . -type f ! -name '.DS_Store' ! -name '._*' ! -name 'WaveCache.wfm' ! -name '*.csh' \
          ! -path '*/Sync Backups/*' ! -path '*/Session File Backups/*' ! -path '*/Auto Saves/*' \
          -exec stat -f '%N%t%z%t%m' {} + 2>/dev/null) | sed 's|^\./||' | LC_ALL=C sort
}

unit_key()   { echo "$1" | sed 's|/|__|g'; }
rec_fp()     { echo "$REC_DIR/$(unit_key "$1").fp"; }
rec_state()  { echo "$REC_DIR/$(unit_key "$1").state"; }
rec_field()  { sed -n "s/^$2=//p" "$(rec_state "$1")" 2>/dev/null | head -1; }

# rec_write <unit> <project> <state> <peer> [fp-file]  – store the record of a unit
rec_write() {
    mkdir -p "$REC_DIR"
    printf 'UNIT=%s\nPROJECT=%s\nSTATE=%s\nPEER=%s\nSINCE=%s\n' "$1" "$2" "$3" "$4" "$(date '+%Y-%m-%d %H:%M')" > "$(rec_state "$1")"
    if [ -n "$5" ]; then cp "$5" "$(rec_fp "$1")"; else fp "$STUDIO_ROOT/$1" > "$(rec_fp "$1")"; fi
}

# all records: prints the unit path of every record (optionally only one project / state)
rec_units() {
    local f
    for f in "$REC_DIR"/*.state; do
        [ -f "$f" ] || continue
        [ -n "$1" ] && [ "$(sed -n 's/^PROJECT=//p' "$f")" != "$1" ] && continue
        [ -n "$2" ] && [ "$(sed -n 's/^STATE=//p' "$f")" != "$2" ] && continue
        sed -n 's/^UNIT=//p' "$f"
    done
}

# changes <fp-old> <fp-new>  ->  prints "C<TAB>path" (changed) / "N<TAB>path" (new) in new vs old
# sizes must match and times may differ by up to 2 s (some drives store times coarsely)
changes() {
    # (FILENAME instead of FNR == NR: the first file may be empty – e.g. an empty folder)
    awk -F'\t' -v A="$1" 'FILENAME == A { s[$1] = $2; t[$1] = $3; next }
        { if (!($1 in s)) print "N\t" $1
          else { d = $3 - t[$1]; if (d < 0) d = -d; if ($2 != s[$1] || d > 2) print "C\t" $1 } }' "$1" "$2"
}

# classify <base-fp> <local-fp> <incoming-fp>  ->  "ACTION<TAB>path" for every incoming file
#   NEW · SAME · UPDATE (only the other Mac changed it) · KEEP (only this Mac) · BOTH (changed on both)
classify() {
    awk -F'\t' -v B="$1" -v L="$2" '
        function same(a, b,   x, y, d) { split(a, x, "\t"); split(b, y, "\t"); if (x[1] != y[1]) return 0
                                         d = x[2] - y[2]; if (d < 0) d = -d; return d <= 2 }
        FILENAME == B { b[$1] = $2 "\t" $3; next }
        FILENAME == L { l[$1] = $2 "\t" $3; next }
        { i = $2 "\t" $3
          if (!($1 in l))                      a = "NEW"
          else if (same(i, l[$1]))             a = "SAME"
          else if (($1 in b) && same(l[$1], b[$1])) a = "UPDATE"
          else if (($1 in b) && same(i, b[$1]))     a = "KEEP"
          else                                 a = "BOTH"
          print a "\t" $1 }' "$1" "$2" "$3"
}

# song units live in 02_Sessions; everything else is a project folder
is_song_unit() { case "$1" in */02_Sessions/*) return 0 ;; *) return 1 ;; esac; }

# project_units <project-path>  -> every unit of a project (relative to the Studio folder)
project_units() {
    local p="$1" rel d
    rel="${p#"$STUDIO_ROOT"/}"
    for d in "$p"/*/; do
        d="${d%/}"; [ -d "$d" ] || continue
        [ "$(basename "$d")" = "02_Sessions" ] && continue
        echo "$rel/$(basename "$d")"
    done
    for d in "$p"/02_Sessions/PT/*/ "$p"/02_Sessions/CB/*/; do
        d="${d%/}"; [ -d "$d" ] && echo "$rel/02_Sessions/$(basename "$(dirname "$d")")/$(basename "$d")"
    done
}

# packages on the drive that were made by another Mac (= waiting for this one)
packages_for_me() {
    local d
    for d in "$PKG_DIR"/*/; do
        d="${d%/}"; [ -f "$d/info.txt" ] || continue
        [ "$(sed -n 's/^FROM=//p' "$d/info.txt")" = "$MACHINE_NAME" ] && continue
        echo "$d"
    done
}
packages_from_me() {
    local d
    for d in "$PKG_DIR"/*/; do
        d="${d%/}"; [ -f "$d/info.txt" ] || continue
        [ "$(sed -n 's/^FROM=//p' "$d/info.txt")" = "$MACHINE_NAME" ] && echo "$d"
    done
}
pkg_field() { sed -n "s/^$2=//p" "$1/info.txt" | head -1; }

# short "SACRO – 03_Song, 05_Song" text for a package
pkg_summary() {
    local p="$1" songs
    songs="$(cut -f2 "$p/units.txt" | /usr/bin/grep '/02_Sessions/' | sed 's|.*/||; s/_PT$//; s/_CB$//' | sort -u | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
    echo "$(basename "$(pkg_field "$p" PROJECT)")${songs:+ – $songs}"
}
