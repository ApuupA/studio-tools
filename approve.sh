#!/bin/bash
# Mark which version of each mix / master is the approved (final) one.
#
#   studio approve [PROJECT]
#
# Normally the HIGHEST version is the final one and you don't need this.
# Use it when an older version won – e.g. the band chose Mix_v03 although v04 exists.
# For every song with more than one version it asks:
#
#   NIGHT_01_Opener_Mix     v01 v02 v03 v04     approved? [Enter = v04]
#
# The answer is stored in <folder>/_approved.txt and is used by
# studio deliver, studio mp3 and when archiving (Portfolio).

source "$(dirname "$0")/_common.sh"

[ -t 0 ] || die "studio approve asks questions – run it in the Terminal."
PROJECT="$(resolve_project "$1")" || exit 1
echo "Project: $(basename "$PROJECT")"
echo "Enter = keep what is shown in [brackets]. Type a number (3 or v03) to approve another version."

any=0
for folder in $BOUNCE_FOLDERS; do
    dir="$PROJECT/$folder"
    [ -d "$dir" ] || continue
    list="$(list_versions "$dir")"
    [ -n "$list" ] || continue
    apf="$dir/_approved.txt"
    new=""
    echo
    echo "$folder"
    while IFS=$'\t' read -r name versions <&3; do
        highest="${versions##* }"
        current="$(awk -F'\t' -v k="$name" '$1 == k { printf "v%02d", $2 }' "$apf" 2>/dev/null)"
        case " $versions " in *" $current "*) ;; *) current="" ;; esac
        def="${current:-$highest}"
        case "$versions" in
            *" "*) ;;                                   # several versions -> ask
            *) printf '  %-44s %s\n' "$name" "$versions (only version)"; continue ;;
        esac
        any=1
        while :; do
            read -r -p "$(printf '  %-44s %s   approved? [%s] ' "$name" "$versions" "$def")" a
            a="${a:-$def}"; a="${a#v}"; a="${a#V}"
            [[ "$a" =~ ^[0-9]+$ ]] && pick="$(printf 'v%02d' "$((10#$a))")" || pick=""
            case " $versions " in *" $pick "*) break ;; esac
            echo "      Please choose one of: $versions"
        done
        # only store it when it is not simply the highest one
        if [ "$pick" != "$highest" ]; then
            new="$new$name	$((10#${pick#v}))
"
            echo "$(date +%Y-%m-%d)  Approved: ${name}_$pick (not the newest $highest)" >> "$PROJECT/00_Admin/Session_Log.txt"
        fi
    done 3<<< "$list"
    if [ -n "$new" ]; then printf '%s' "$new" > "$apf"; else rm -f "$apf"; fi
done

echo
[ $any -eq 1 ] && echo "Saved. studio deliver / mp3 / archive now use these versions." \
               || echo "Nothing to decide – every song has only one version."
