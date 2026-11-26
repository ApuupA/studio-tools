#!/bin/bash
# Carry songs and projects between your Macs on the backup drive.
#
#   studio sync              everything, in this order:
#                              1. bring in what is waiting on the drive for this Mac
#                              2. laptop: send back what you worked on
#                              3. ask if you want to take something with you
#                              4. merge the library (03_LIBRARY) and compare plugins
#   studio take [PROJECT]    only step 3: put songs on the drive
#   studio sync --send       only step 2 (used by "studio end" on the laptop)
#
# Sync NEVER deletes or overwrites anything – see _sync_lib.sh for how.

source "$(dirname "$0")/_common.sh"
source "$SCRIPT_DIR/_sync_lib.sh"

MODE="all"
case "$1" in
    --send) MODE="send"; shift ;;
    --take) MODE="take"; shift ;;
esac
TAKE_PROJECT="$1"

[ -t 0 ] || die "studio sync asks questions – run it in the Terminal."
DRIVE="$(basename "$ARCHIVE_VOLUME")"
volume_mounted "$ARCHIVE_VOLUME" || die "Backup drive '$DRIVE' is not connected."
mkdir -p "$PKG_DIR" "$SYNC_DIR/_Done" "$SYNC_DIR/Library" "$SYNC_DIR/Machines" "$REC_DIR" \
    || die "Cannot write to $SYNC_DIR"

# an open DAW could save over files that sync just brought in
if daw_running; then
    echo "Please SAVE and QUIT Pro Tools / Cubase first.  Waiting…  (Ctrl+C to cancel)"
    while daw_running; do sleep 3; done
fi

TMPW="$(mktemp -d "${TMPDIR:-/tmp}/studiosync.XXXXXX")" || die "No temp folder"
trap 'rm -rf "${TMPW:?}"' EXIT
STAMP="$(date +%Y-%m-%d_%H%M%S)"
TODAY="$(date +%Y-%m-%d)"
yes_default() { local a; read -r -p "$1 [Y/n] " a; case "$a" in n|N|no|nein) return 1 ;; *) return 0 ;; esac; }
no_default()  { local a; read -r -p "$1 [y/N] " a; case "$a" in y|Y|yes|ja|j) return 0 ;; *) return 1 ;; esac; }
# project_note <project> <text>: a line in the project's Session_Log. Our own note must not
# look like "you changed 00_Admin" at the next sync, so the record is refreshed when it was clean.
project_note() {
    local u="$1/00_Admin" f="$STUDIO_ROOT/$1/00_Admin/Session_Log.txt" was_clean=0
    [ -f "$f" ] || return 0
    [ -f "$(rec_fp "$u")" ] && [ -z "$(changes "$(rec_fp "$u")" <(fp "$STUDIO_ROOT/$u"))" ] && was_clean=1
    echo "$TODAY  $2" >> "$f"
    [ $was_clean -eq 1 ] && fp "$STUDIO_ROOT/$u" > "$(rec_fp "$u")"
    return 0
}

# ==================================================================================
# 1. BRING IN
# ==================================================================================
bring_in() {
    local pkg="$1" from project projdir mode unit i=0 base loc inc cls n_new n_upd n_both n_keep \
          is_log line err=0 newproj=0 songs
    from="$(pkg_field "$pkg" FROM)"; project="$(pkg_field "$pkg" PROJECT)"; projdir="$STUDIO_ROOT/$project"
    [ -d "$projdir" ] || newproj=1

    echo
    echo "From $from: $(pkg_summary "$pkg")   (put on the drive $(pkg_field "$pkg" UPDATED))"
    [ $newproj -eq 1 ] && echo "  New project on this Mac: $project"

    # --- plan: what would happen to every unit ---------------------------------
    : > "$TMPW/plan"
    while IFS=$'\t' read -r mode unit <&3; do
        [ -n "$unit" ] || continue
        i=$((i + 1))
        base="$TMPW/b$i"; loc="$TMPW/l$i"; inc="$TMPW/i$i"; cls="$TMPW/c$i"
        if [ -f "$(rec_fp "$unit")" ]; then cp "$(rec_fp "$unit")" "$base"; else : > "$base"; fi
        fp "$STUDIO_ROOT/$unit" > "$loc"
        fp "$pkg/Files/$unit" > "$inc"
        classify "$base" "$loc" "$inc" > "$cls"
        n_new=$(/usr/bin/grep -c '^NEW' "$cls"); n_upd=$(/usr/bin/grep -c '^UPDATE' "$cls")
        n_both=$(/usr/bin/grep -c '^BOTH' "$cls"); n_keep=$(/usr/bin/grep -c '^KEEP' "$cls")
        # the session log is merged line by line, so it never counts as "changed on both"
        is_log=0; case "$unit" in */00_Admin) is_log=1 ;; esac
        [ $is_log -eq 1 ] && n_both=$(/usr/bin/grep -v -c $'\tSession_Log.txt$' <(/usr/bin/grep '^BOTH' "$cls"))

        how="files"
        if is_song_unit "$unit" && [ "$n_both" -gt 0 ]; then how="second"; fi
        printf '%s\t%s\t%s\n' "$i" "$how" "$unit" >> "$TMPW/plan"

        line="  $(basename "$unit"): "
        if [ "$how" = "second" ]; then
            line="$line⚠️  changed on BOTH Macs – comes in as a second song folder, yours stays as it is"
        else
            [ "$n_upd" -gt 0 ]  && line="$line$n_upd updated, "
            [ "$n_new" -gt 0 ]  && line="$line$n_new new, "
            [ "$n_both" -gt 0 ] && line="$line$n_both changed on both Macs (kept as extra copies), "
            [ "$n_keep" -gt 0 ] && line="$line$n_keep newer here (kept), "
            line="${line%, }"
            [ "${line%: }" != "$line" ] && line="${line}nothing new"
        fi
        if [ "$mode" = "delta" ] && [ ! -d "$STUDIO_ROOT/$unit" ] && is_song_unit "$unit"; then
            line="$line  (⚠️ only the changes were sent – the rest of this song is not on this Mac)"
        fi
        echo "$line"
    done 3< "$pkg/units.txt"

    yes_default "Bring it in?" || { echo "  Left on the drive."; return 0; }

    # --- apply ---------------------------------------------------------------
    local how src dst bk rel act sib tgt stem ext k
    while IFS=$'\t' read -r i how unit <&3; do
        src="$pkg/Files/$unit"; dst="$STUDIO_ROOT/$unit"; bk="$dst/Sync Backups/$STAMP"
        cls="$TMPW/c$i"

        if [ "$how" = "second" ]; then
            # complete second folder: incoming files + unchanged files cloned from this Mac
            sib="$dst ($from $TODAY)"; k=2
            while [ -e "$sib" ]; do sib="$dst ($from $TODAY $k)"; k=$((k + 1)); done
            mkdir -p "$sib"
            man="$pkg/Manifests/$(unit_key "$unit").fp"; [ -f "$man" ] || man="$TMPW/i$i"
            awk -F'\t' -v I="$TMPW/i$i" -v L="$TMPW/l$i" '
                FILENAME == I { inc[$1] = 1; next }
                FILENAME == L { s[$1] = $2; t[$1] = $3; next }
                { if ($1 in inc) print "SRC\t" $1
                  else if (($1 in s) && s[$1] == $2 && (t[$1] - $3 <= 2) && ($3 - t[$1] <= 2)) print "CLONE\t" $1
                  else print "MISSING\t" $1 }' "$TMPW/i$i" "$TMPW/l$i" "$man" > "$TMPW/s$i"
            while IFS=$'\t' read -r act rel; do
                mkdir -p "$(dirname "$sib/$rel")"
                case "$act" in
                    SRC)   cp -p "$src/$rel" "$sib/$rel" || err=$((err + 1)) ;;
                    CLONE) cp -c -p "$dst/$rel" "$sib/$rel" 2>/dev/null || cp -p "$dst/$rel" "$sib/$rel" || err=$((err + 1)) ;;
                esac
            done < "$TMPW/s$i"
            {
                echo "This is the version of $(basename "$unit") from $from, brought in $TODAY."
                echo "The song was changed on both Macs. Your version on this Mac is unchanged in:"
                echo "  $(basename "$dst")"
                echo "Open both, keep what you want. Nothing was deleted."
            } > "$sib/Sync Info.txt"
            if /usr/bin/grep -q '^MISSING' "$TMPW/s$i"; then
                cut -f2 <(/usr/bin/grep '^MISSING' "$TMPW/s$i") > "$sib/MISSING FILES.txt"
                echo "  ⚠️  $(basename "$sib"): $(/usr/bin/grep -c '^MISSING' "$TMPW/s$i") file(s) could not be put together – see MISSING FILES.txt"
            fi
            echo "  ✅ $(basename "$sib")  (second version – yours is unchanged)"
            rec_write "$unit" "$project" "$([ "$MACHINE_ROLE" = main ] && echo home || echo borrowed)" "$from"
            printf '%s\n' "$unit" >> "$TMPW/brought"
            continue
        fi

        mkdir -p "$dst"
        while IFS=$'\t' read -r act rel; do
            case "$act" in
                NEW)
                    mkdir -p "$(dirname "$dst/$rel")"
                    # safety net: never copy over something that exists (e.g. a file the fingerprint skips)
                    if [ -e "$dst/$rel" ]; then act="BOTH"; else cp -p "$src/$rel" "$dst/$rel" || err=$((err + 1)); fi ;;
            esac
            case "$act" in
                UPDATE|BOTH)
                    if [ "$rel" = "Session_Log.txt" ]; then
                        # merge: lines from the other Mac that are not here yet are added at the end
                        mkdir -p "$bk"; cp -p "$dst/$rel" "$bk/$rel"
                        awk -v A="$dst/$rel" 'FILENAME == A { seen[$0] = 1; next } !seen[$0]' "$dst/$rel" "$src/$rel" > "$TMPW/newlines" \
                            && cat "$TMPW/newlines" >> "$dst/$rel" || err=$((err + 1))
                    elif [ "$act" = "UPDATE" ]; then
                        # only the other Mac changed it: old version is moved aside, never deleted
                        mkdir -p "$(dirname "$bk/$rel")"
                        mv "$dst/$rel" "$bk/$rel" && cp -p "$src/$rel" "$dst/$rel" || err=$((err + 1))
                    else
                        # changed on both: the incoming one becomes an extra copy next to it
                        stem="${rel%.*}"; ext="${rel##*.}"; [ "$stem" = "$rel" ] && ext=""
                        tgt="$dst/$stem ($from)${ext:+.$ext}"; k=2
                        while [ -e "$tgt" ]; do tgt="$dst/$stem ($from $k)${ext:+.$ext}"; k=$((k + 1)); done
                        cp -p "$src/$rel" "$tgt" || err=$((err + 1))
                    fi ;;
            esac
        done < "$cls"
        rec_write "$unit" "$project" "$([ "$MACHINE_ROLE" = main ] && echo home || echo borrowed)" "$from"
        printf '%s\n' "$unit" >> "$TMPW/brought"
    done 3< "$TMPW/plan"

    if [ $err -gt 0 ]; then
        echo "  ❌ $err file(s) could not be copied. The package stays on the drive; nothing here was deleted."
        log "Bring-in from $from had $err errors: $(basename "$pkg")"
        return 1
    fi

    songs="$(pkg_summary "$pkg")"
    [ $newproj -eq 1 ] && set_type_tag "$projdir" "$(project_label "$projdir")"
    project_note "$project" "Brought in from $from: ${songs#* – }"
    mv "$pkg" "$SYNC_DIR/_Done/${STAMP}__$(basename "$pkg")"
    log "Brought in from $from: $songs"
    echo "  ✅ Done – it's in $(basename "$project")."
}

# ==================================================================================
# 3. TAKE (put units on the drive)
# ==================================================================================
# take_units <project> <unit>…
#   main:     songs + SYNC_CARRY_FOLDERS travel completely, other project folders travel empty
#   portable: only what changed since the last sync (everything if it never travelled)
take_units() {
    local project="$1" pkg unit src key now delta mode n=0 copied="$TMPW/copied"
    shift
    pkg="$PKG_DIR/${MACHINE_NAME}__$(basename "$project")"
    mkdir -p "$pkg/Files" "$pkg/Manifests"; touch "$pkg/units.txt"
    : > "$TMPW/took"

    for unit in "$@"; do
        src="$STUDIO_ROOT/$unit"
        [ -d "$src" ] || continue
        key="$(unit_key "$unit")"; now="$TMPW/now_$n"; n=$((n + 1))
        fp "$src" > "$now"
        : > "$copied"
        if [ "$MACHINE_ROLE" = "main" ]; then
            if is_song_unit "$unit" || case " $SYNC_CARRY_FOLDERS " in *" $(basename "$unit") "*) true ;; *) false ;; esac; then
                mode="full"
                mkdir -p "$pkg/Files/$unit"
                rsync -a "${SYNC_RSYNC_EXCLUDES[@]}" "$src/" "$pkg/Files/$unit/" >> "$LOG_FILE" 2>&1 \
                    || die "Copy to the drive failed ($unit). Nothing was changed on this Mac."
                cp "$now" "$copied"
            else
                mode="empty"; mkdir -p "$pkg/Files/$unit"
            fi
        else
            if [ -f "$(rec_fp "$unit")" ]; then mode="delta"; changes "$(rec_fp "$unit")" "$now" | cut -f2 > "$TMPW/list"
            else                                mode="full";  cut -f1 "$now" > "$TMPW/list"; fi
            while IFS= read -r rel; do
                mkdir -p "$(dirname "$pkg/Files/$unit/$rel")"
                cp -p "$src/$rel" "$pkg/Files/$unit/$rel" || die "Copy to the drive failed ($unit/$rel). Nothing was changed on this Mac."
            done < "$TMPW/list"
            awk -F'\t' -v A="$TMPW/list" 'FILENAME == A { w[$1] = 1; next } ($1 in w)' "$TMPW/list" "$now" > "$copied"
        fi
        # check: every copied file is on the drive with the same size and time
        if [ -s "$copied" ] && [ -n "$(changes <(fp "$pkg/Files/$unit") "$copied")" ]; then
            die "Check failed: the copy of $unit on the drive is not complete. Nothing was changed on this Mac."
        fi
        cp "$now" "$pkg/Manifests/$key.fp"
        awk -F'\t' -v u="$unit" '$2 != u' "$pkg/units.txt" > "$TMPW/units" && cat "$TMPW/units" > "$pkg/units.txt"
        printf '%s\t%s\n' "$mode" "$unit" >> "$pkg/units.txt"
        printf '%s\t%s\n' "$mode" "$unit" >> "$TMPW/took"
        printf '%s\n' "$unit" >> "$TMPW/took_all"
        # record: main lends it (empty folders: nothing of ours travelled), laptop sent it
        if [ "$MACHINE_ROLE" = "main" ]; then
            if [ "$mode" = "empty" ]; then : > "$TMPW/empty"; rec_write "$unit" "$project" lent "drive" "$TMPW/empty"
            else rec_write "$unit" "$project" lent "drive" "$now"; fi
        else
            rec_write "$unit" "$project" sent "drive" "$now"
        fi
    done

    printf 'FROM=%s\nROLE=%s\nPROJECT=%s\nUPDATED=%s\n' "$MACHINE_NAME" "$MACHINE_ROLE" "$project" "$(date '+%Y-%m-%d %H:%M')" > "$pkg/info.txt"
    local songs
    songs="$(cut -f2 "$TMPW/took" | /usr/bin/grep '/02_Sessions/' | sed 's|.*/||' | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
    project_note "$project" "Put on the drive by $MACHINE_NAME${songs:+: $songs}"
    log "Put on the drive: $(basename "$project")${songs:+ ($songs)}"
    echo "  ✅ On the drive: $(basename "$project")${songs:+ – $songs}"
}

# song folders of a project, grouped by song ("03_Song" -> its _PT and/or _CB folder)
song_groups() {
    local p="$1" d n
    for d in "$p"/02_Sessions/PT/*/ "$p"/02_Sessions/CB/*/; do
        d="${d%/}"; [ -d "$d" ] || continue
        n="$(basename "$d")"
        case "$n" in *_PT|*_CB) printf '%s\t%s\n' "${n%_??}" "$d" ;; *) printf '%s\t%s\n' "$n" "$d" ;; esac
    done | sort
}

take_ui() {
    local project projdir rel stems=() labels=() s daws d unit units=() kb free n c
    projdir="$(resolve_project "$1")" || return 0
    project="${projdir#"$STUDIO_ROOT"/}"
    echo
    echo "Project: $(basename "$projdir")"

    song_groups "$projdir" > "$TMPW/groups"
    while IFS= read -r s; do
        stems+=("$s")
        daws="$(awk -F'\t' -v s="$s" '$1 == s { n = $2; sub(/.*_/, "", n); printf "%s%s", (c++ ? "+" : ""), n }' "$TMPW/groups")"
        st=""
        while IFS=$'\t' read -r _ d; do
            unit="${d#"$STUDIO_ROOT"/}"
            case "$(rec_field "$unit" STATE)" in lent) st="  [already on the drive / at the laptop]" ;; esac
        done < <(awk -F'\t' -v s="$s" '$1 == s' "$TMPW/groups")
        labels+=("$s ($daws)$st")
    done < <(cut -f1 "$TMPW/groups" | uniq)

    if [ ${#stems[@]} -gt 0 ]; then
        choose_many "Which songs?" 1 "${labels[@]}"
        for c in "${CHOICES[@]}"; do
            s="${stems[$((c - 1))]}"
            while IFS=$'\t' read -r _ d; do units+=("${d#"$STUDIO_ROOT"/}"); done < <(awk -F'\t' -v s="$s" '$1 == s' "$TMPW/groups")
        done
    fi
    # the project folders (00_Admin, 01_Reference, 03_Mixes …) always come along
    while IFS= read -r unit; do is_song_unit "$unit" || units+=("$unit"); done < <(project_units "$projdir")

    # space on the drive (main copies songs completely)
    kb=0
    for unit in "${units[@]}"; do
        if is_song_unit "$unit" || case " $SYNC_CARRY_FOLDERS " in *" $(basename "$unit") "*) true ;; *) false ;; esac; then
            kb=$((kb + $(du -sk "$STUDIO_ROOT/$unit" 2>/dev/null | cut -f1)))
        fi
    done
    free=$(df -k "$ARCHIVE_VOLUME" | awk 'NR == 2 { print $4 }')
    [ "$kb" -lt "$free" ] || die "Not enough space on '$DRIVE' (needs $((kb / 1024)) MB)."
    echo
    echo "Up to $((kb / 1024)) MB go on the drive ($MACHINE_ROLE: $([ "$MACHINE_ROLE" = main ] && echo "complete songs" || echo "only what changed"))."
    yes_default "Put it on the drive?" || { echo "  Nothing taken."; return 0; }
    take_units "$project" "${units[@]}"
}

# ==================================================================================
# 2. SEND BACK (laptop) / warnings (main)
# ==================================================================================
send_back() {
    local projects p projdir unit nc nn st sendlist=() returnlist=() keepsongs=() line any=0
    rec_units | while IFS= read -r unit; do rec_field "$unit" PROJECT; done | sort -u > "$TMPW/projects"
    while IFS= read -r p <&4; do
        projdir="$STUDIO_ROOT/$p"
        [ -d "$projdir" ] || continue
        line=""
        while IFS= read -r unit <&5; do
            /usr/bin/grep -qxF "$unit" "$TMPW/brought" 2>/dev/null && continue     # just arrived in this sync
            fp "$STUDIO_ROOT/$unit" > "$TMPW/now"
            if [ -f "$(rec_fp "$unit")" ]; then
                changes "$(rec_fp "$unit")" "$TMPW/now" > "$TMPW/ch"
                nc=$(/usr/bin/grep -c '^C' "$TMPW/ch"); nn=$(/usr/bin/grep -c '^N' "$TMPW/ch")
                st="$(rec_field "$unit" STATE)"
                if [ $((nc + nn)) -gt 0 ]; then
                    sendlist+=("$p	$unit")
                    line="$line    $(basename "$unit"): $([ $nc -gt 0 ] && echo "$nc changed")$([ $nc -gt 0 ] && [ $nn -gt 0 ] && echo ", ")$([ $nn -gt 0 ] && echo "$nn new")
"
                elif [ "$st" = "borrowed" ] && is_song_unit "$unit"; then
                    returnlist+=("$p	$unit")
                fi
            elif [ -s "$TMPW/now" ]; then
                sendlist+=("$p	$unit")
                line="$line    $(basename "$unit"): new on this Mac
"
            fi
        done 5< <(project_units "$projdir")
        if [ -n "$line" ]; then
            [ $any -eq 0 ] && { echo; echo "You worked on:"; any=1; }
            echo "  $(basename "$p")"
            printf '%s' "$line"
        fi
    done 4< "$TMPW/projects"

    if [ ${#sendlist[@]} -eq 0 ]; then
        echo; echo "Nothing changed on this Mac since the last sync."
        return 0
    fi

    local sent=0
    if yes_default "Send it to the drive?"; then
        sent=1
        while IFS= read -r p <&6; do
            units=(); while IFS= read -r u; do units+=("$u"); done < <(printf '%s\n' "${sendlist[@]}" | awk -F'\t' -v p="$p" '$1 == p { print $2 }')
            take_units "$p" "${units[@]}"
        done 6< <(printf '%s\n' "${sendlist[@]}" | cut -f1 | sort -u)
    fi
    # unchanged borrowed songs of the projects just sent: give them back as well (end of the trip)
    if [ $sent -eq 1 ] && [ ${#returnlist[@]} -gt 0 ]; then
        local keep=()
        for r in "${returnlist[@]}"; do
            printf '%s\n' "${sendlist[@]}" | cut -f1 | /usr/bin/grep -qxF "${r%%	*}" && keep+=("$r")
        done
        returnlist=("${keep[@]}")
    else
        returnlist=()
    fi
    if [ ${#returnlist[@]} -gt 0 ]; then
        echo
        echo "Also from the main Mac, unchanged:"
        printf '%s\n' "${returnlist[@]}" | cut -f2 | sed 's|.*/|    |'
        if yes_default "Give them back too? (nothing is copied – the main Mac just marks them as back)"; then
            while IFS= read -r p <&6; do
                units=(); while IFS= read -r u; do units+=("$u"); done < <(printf '%s\n' "${returnlist[@]}" | awk -F'\t' -v p="$p" '$1 == p { print $2 }')
                take_units "$p" "${units[@]}"
            done 6< <(printf '%s\n' "${returnlist[@]}" | cut -f1 | sort -u)
        fi
    fi

    # keep the songs on the laptop, or move them to the Trash (asked, never automatic)
    local sent_songs=()
    while IFS= read -r u; do [ -n "$u" ] && is_song_unit "$u" && sent_songs+=("$u"); done < <(sort -u "$TMPW/took_all" 2>/dev/null)
    if [ ${#sent_songs[@]} -gt 0 ]; then
        echo
        if no_default "Remove the songs you sent from this Mac? (they go to the Trash, not deleted)"; then
            for u in "${sent_songs[@]}"; do
                [ -d "$STUDIO_ROOT/$u" ] || continue
                mv "$STUDIO_ROOT/$u" "$HOME/.Trash/$(basename "$u") $(date +%H%M%S)" \
                    && rm -f "$(rec_fp "$u")" "$(rec_state "$u")" && echo "  🗑  $(basename "$u") → Trash"
            done
        else
            echo "  Kept on this Mac."
        fi
    fi
}

warn_lent() {
    local unit any=0
    while IFS= read -r unit; do
        [ -d "$STUDIO_ROOT/$unit" ] || continue
        is_song_unit "$unit" || continue
        if [ -n "$(changes "$(rec_fp "$unit")" <(fp "$STUDIO_ROOT/$unit"))" ]; then
            [ $any -eq 0 ] && { echo; echo "⚠️  Changed here while it is out (it will come back as a second version):"; any=1; }
            echo "    $(basename "$(rec_field "$unit" PROJECT)") – $(basename "$unit")"
        fi
    done < <(rec_units "" lent)
}

# ==================================================================================
# 4. LIBRARY + PLUGINS
# ==================================================================================
library_sync() {
    local lib="$STUDIO_ROOT/03_LIBRARY" ssd="$SYNC_DIR/Library" up down differ ex=(--exclude='Portfolio/' --exclude-from="$EXCLUDES")
    [ -d "$lib" ] || return 0
    up="$(rsync -a --ignore-existing -i "${ex[@]}" "$lib/" "$ssd/" 2>>"$LOG_FILE" | /usr/bin/grep -c '^>f')"
    down="$(rsync -a --ignore-existing -i "${ex[@]}" "$ssd/" "$lib/" 2>>"$LOG_FILE" | /usr/bin/grep -c '^>f')"
    rsync -a -n -i "${ex[@]}" "$lib/" "$ssd/" 2>/dev/null | /usr/bin/grep '^>f' | /usr/bin/grep -v '+++++++' | sed 's/^[^ ]* //' > "$TMPW/libdiff"
    differ=$(wc -l < "$TMPW/libdiff" | tr -d ' ')
    echo
    echo "Library (03_LIBRARY): $up new file(s) to the drive, $down new file(s) from the drive."
    if [ "$differ" -gt 0 ]; then
        echo "  $differ file(s) differ between this Mac and the drive – left as they are (nothing is overwritten):"
        head -5 "$TMPW/libdiff" | sed 's/^/    /'
    fi
}

plugins_compare() {
    local mine="$SYNC_DIR/Machines/$MACHINE_NAME.txt" other name missing apps
    /bin/bash "$SCRIPT_DIR/plugin_inventory.sh" --quick "$TMPW/plugins" 2>/dev/null && cp "$TMPW/plugins" "$mine"
    for other in "$SYNC_DIR/Machines"/*.txt; do
        [ -f "$other" ] && [ "$other" != "$mine" ] || continue
        name="$(basename "$other" .txt)"
        awk -v A="$mine" 'function key(l,   n, f, i, k) { n = split(l, f, / +/); k = f[1]; for (i = 2; i < n; i++) k = k " " f[i]; return k }
             FILENAME == A { if ($1 != "App:") have[key($0)] = 1; next }
             $1 != "App:" && NF > 1 && !(key($0) in have) { print "    " key($0) }' "$mine" "$other" > "$TMPW/missing"
        apps="$(diff <(/usr/bin/grep '^App:' "$mine" | sed -E 's/ +/ /g') <(/usr/bin/grep '^App:' "$other" | sed -E 's/ +/ /g') | /usr/bin/grep '^>' | sed 's/^> App: /    /')"
        echo
        if [ ! -s "$TMPW/missing" ] && [ -z "$apps" ]; then
            echo "Plugins: everything on $name is also on this Mac ✅"
        else
            [ -s "$TMPW/missing" ] && { echo "Plugins on $name that are missing here ($(wc -l < "$TMPW/missing" | tr -d ' ')):"; head -12 "$TMPW/missing"; }
            [ -n "$apps" ] && { echo "DAW versions on $name (differ from this Mac):"; echo "$apps"; }
        fi
    done
}

# ==================================================================================
# RUN
# ==================================================================================
echo "STUDIO SYNC   $MACHINE_NAME ($([ "$MACHINE_ROLE" = main ] && echo "main Mac" || echo "laptop"))   drive: $DRIVE"

case "$MODE" in
    send)
        [ "$MACHINE_ROLE" = "portable" ] && send_back
        exit 0 ;;
    take)
        take_ui "$TAKE_PROJECT"
        library_sync
        exit 0 ;;
esac

# 1. bring in
found=0
while IFS= read -r p <&3; do found=1; bring_in "$p"; done 3< <(packages_for_me)
[ $found -eq 0 ] && { echo; echo "Nothing waiting on the drive for this Mac."; }

# 2. send back (laptop) / warnings (main)
if [ "$MACHINE_ROLE" = "portable" ]; then send_back; else warn_lent; fi

# 3. take something?
echo
if no_default "Take something with you on the drive?"; then take_ui ""; fi

# 4. library + plugins
library_sync
plugins_compare

# what is still waiting for the other Mac / already delivered
waiting="$(packages_from_me)"
if [ -n "$waiting" ]; then
    echo
    echo "On the drive, waiting for the other Mac:"
    while IFS= read -r p; do echo "    $(pkg_summary "$p")"; done <<< "$waiting"
fi
done_kb="$(du -sk "$SYNC_DIR/_Done" 2>/dev/null | cut -f1)"
if [ "${done_kb:-0}" -gt 1048576 ]; then
    echo
    echo "Already delivered copies on the drive: Studio_Sync/_Done ($((done_kb / 1048576)) GB) – delete them in Finder whenever you like."
fi
echo
echo "Sync done."
