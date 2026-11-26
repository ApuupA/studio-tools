#!/bin/bash
# Plugin + library inventory: writes a list of all installed plugins (with versions)
# and all sample / instrument libraries (with size and location) to
#   99_SYSTEM/Studio_Docs/Plugin_Inventory/Plugins_YYYY-MM-DD_HHMM.txt
# and shows what changed since the last inventory.
#
#   studio plugins          (or ./plugin_inventory.sh)
#
# Run it BEFORE every macOS / Pro Tools / Cubase / plugin update. If something
# breaks afterwards, the list shows exactly what was installed before.

source "$(dirname "$0")/_common.sh"

OUT_DIR="$STUDIO_ROOT/99_SYSTEM/Studio_Docs/Plugin_Inventory"
mkdir -p "$OUT_DIR"
PREV="$(find "$OUT_DIR" -name 'Plugins_*.txt' | sort | tail -1)"
OUT="$OUT_DIR/Plugins_$(date +%Y-%m-%d_%H%M%S).txt"
TMP="$(mktemp "${TMPDIR:-/tmp}/plugins.XXXXXX")"     # written here first, kept only if something changed

bundle_version() {
    local v
    v="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist" 2>/dev/null)"
    [ -n "$v" ] || v="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$1/Contents/Info.plist" 2>/dev/null)"
    echo "${v:-?}"
}

# section <FORMAT> <extension> <folder> [<folder> …]  -> lines "FORMAT  Name  version"
section() {
    local fmt="$1" ext="$2" d p
    shift 2
    for d in "$@"; do
        [ -d "$d" ] || continue
        find "$d" -name "*.$ext" -not -path "*.$ext/*" 2>/dev/null
    done | while IFS= read -r p; do
        printf '%-5s %-52s %s\n' "$fmt" "$(basename "$p" ".$ext")" "$(bundle_version "$p")"
    done | sort -f -u
}

# --- Sample / instrument libraries ----------------------------------------------
# Raw lines: vendor <TAB> name <TAB> version <TAB> size in KB <TAB> folder
MIN_KB=$(( ${LIBRARY_MIN_MB:-100} * 1024 ))

# lib_root <vendor> <folder>: every subfolder of <folder> is one library
lib_root() {
    local vendor="$1" root="$2" d
    [ -d "$root" ] || return
    for d in "$root"/*/; do
        [ -d "$d" ] || continue
        d="${d%/}"
        printf '%s\t%s\t-\t%s\t%s\n' "$vendor" "$(basename "$d")" "$(du -sk "$d" 2>/dev/null | cut -f1)" "$d"
    done
}

# Native Instruments registers every library with its real location and version
lib_native_instruments() {
    local p dir ver vol rest
    for p in /Library/Preferences/com.native-instruments.*.plist; do
        [ -f "$p" ] || continue
        dir="$(/usr/libexec/PlistBuddy -c 'Print :ContentDir' "$p" 2>/dev/null)" || continue
        ver="$(/usr/libexec/PlistBuddy -c 'Print :ContentVersion' "$p" 2>/dev/null)"
        # "Macintosh HD:Users:Shared:Name:"  ->  /Users/Shared/Name   (other drives: /Volumes/<name>/…)
        vol="${dir%%:*}"; rest="${dir#*:}"; rest="/$(echo "${rest%:}" | tr ':' '/')"
        [ -d "/Volumes/$vol$rest" ] && [ "$(cd "/Volumes/$vol" 2>/dev/null && pwd -P)" != "/" ] && rest="/Volumes/$vol$rest"
        [ -d "$rest" ] || continue
        printf 'Native Instruments\t%s\t%s\t%s\t%s\n' "$(basename "$p" .plist | sed 's/^com\.native-instruments\.//')" \
            "${ver:--}" "$(du -sk "$rest" 2>/dev/null | cut -f1)" "$rest"
    done
}

libraries() {
    local d extra
    lib_native_instruments
    for d in "/Library/Application Support/Toontrack"/*/ "$HOME/Library/Application Support/Toontrack"/*/; do
        [ -d "$d" ] && lib_root "Toontrack" "${d%/}"
    done
    lib_root "Toontrack"      "/Library/Application Support/EZDrummer"
    lib_root "Toontrack"      "/Library/Application Support/Superior Drummer"
    lib_root "Steinberg"      "/Library/Application Support/Steinberg/Content"
    lib_root "Steinberg"      "$HOME/Library/Application Support/Steinberg/Content"
    lib_root "IK Multimedia"  "$HOME/Documents/IK Multimedia"
    lib_root "Spectrasonics"  "/Library/Application Support/Spectrasonics"
    lib_root "Spectrasonics"  "$HOME/Library/Application Support/Spectrasonics"
    lib_root "XLN Audio"      "/Library/Application Support/XLN Audio"
    lib_root "XLN Audio"      "/Users/Shared/XLN Audio"
    lib_root "Arturia"        "/Library/Arturia"
    lib_root "UJAM"           "/Library/Application Support/UJAM"
    lib_root "Shared folder"  "/Users/Shared"
    IFS='|' read -r -a extra <<< "$LIBRARY_FOLDERS"
    for d in "${extra[@]}"; do [ -n "$d" ] && lib_root "Own folder" "${d%/}"; done
}

# big enough, each folder only once (first mention wins), sorted, nicely formatted
library_section() {
    libraries | awk -F'\t' -v min="$MIN_KB" '$4 + 0 >= min && !seen[$5]++' | sort -f -t"$(printf '\t')" -k1,1 -k2,2 \
    | awk -F'\t' '{ printf "LIB   %-19s %-34s %-9s %7.1f GB   %s\n", $1, $2, $3, $4 / 1048576, $5; total += $4 }
                  END { if (NR) printf "\nLibraries: %d folder(s), %.1f GB in total\n", NR, total / 1048576 }'
}

# Quick list for "studio sync" (apps + plugins only, no libraries, nothing saved here):
#   plugin_inventory.sh --quick <file>
plugins_only() {
    for app in /Applications/Pro\ Tools*.app /Applications/Cubase*.app /Applications/Nuendo*.app /Applications/WaveLab*.app; do
        [ -d "$app" ] && printf 'App:      %-28s %s\n' "$(basename "$app" .app)" "$(bundle_version "$app")"
    done
    section AAX  aaxplugin "/Library/Application Support/Avid/Audio/Plug-Ins"
    section VST3 vst3      "/Library/Audio/Plug-Ins/VST3"       "$HOME/Library/Audio/Plug-Ins/VST3"
    section VST  vst       "/Library/Audio/Plug-Ins/VST"        "$HOME/Library/Audio/Plug-Ins/VST"
    section AU   component "/Library/Audio/Plug-Ins/Components" "$HOME/Library/Audio/Plug-Ins/Components"
}
if [ "$1" = "--quick" ]; then
    rm -f "$TMP"
    plugins_only > "${2:?--quick needs a file}"
    exit 0
fi

echo "Collecting plugins…"
{
    echo "PLUGIN INVENTORY   $(date '+%Y-%m-%d %H:%M')"
    echo "Mac:      $(sysctl -n hw.model 2>/dev/null)  ·  macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
    for app in /Applications/Pro\ Tools*.app /Applications/Cubase*.app /Applications/Nuendo*.app /Applications/WaveLab*.app; do
        [ -d "$app" ] && printf 'App:      %-28s %s\n' "$(basename "$app" .app)" "$(bundle_version "$app")"
    done
    echo
    echo "# FORMAT NAME                                                VERSION"
    section AAX  aaxplugin "/Library/Application Support/Avid/Audio/Plug-Ins"
    section VST3 vst3      "/Library/Audio/Plug-Ins/VST3"       "$HOME/Library/Audio/Plug-Ins/VST3"
    section VST  vst       "/Library/Audio/Plug-Ins/VST"        "$HOME/Library/Audio/Plug-Ins/VST"
    section AU   component "/Library/Audio/Plug-Ins/Components" "$HOME/Library/Audio/Plug-Ins/Components"
    echo
    echo "# LIBRARIES (folders of ${LIBRARY_MIN_MB:-100} MB and more)"
    echo "#     VENDOR              NAME                               VERSION      SIZE   LOCATION"
    echo "Measuring libraries (this can take a moment)…" >&2
    library_section
} > "$TMP"

count() { grep -c "^$1 " "$TMP"; }
echo
echo "Found:  AAX $(count AAX)  ·  VST3 $(count VST3)  ·  VST $(count VST)  ·  AU $(count AU)"
grep '^Libraries:' "$TMP" | sed 's/^/        /'


# --- What changed since the last inventory? -------------------------------------
if [ -n "$PREV" ]; then
    echo
    echo "Changes since $(basename "$PREV" .txt | sed 's/Plugins_//'):"
    comparable() { grep -E '^(AAX|VST3|VST|AU|LIB|App:|Mac:)' "$1" | sed -E '/^LIB/ s/ +[0-9]+\.[0-9] GB +/  |  /'; }
    changes="$(diff <(comparable "$PREV") <(comparable "$TMP") \
               | grep '^[<>]' | sed 's/^</  before:  /; s/^>/  now:     /')"
    if [ -z "$changes" ]; then
        echo "  none – the last inventory is still correct, no new file needed."
        rm -f "$TMP"
        exit 0
    fi
    echo "$changes"
fi

mv "$TMP" "$OUT"
echo
echo "Saved: ${OUT#"$STUDIO_ROOT"/}"
log "Plugin inventory written"
