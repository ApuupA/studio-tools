#!/bin/bash
# Check received audio files BEFORE importing them into a session.
#
#   studio check [PROJECT]        checks the project's 07_Received folder
#   studio check /any/folder      checks that folder (e.g. something in 00_INBOX)
#
# Per folder (one folder = one song, usually) it reports and flags:
#   RATE    a file with a different sample rate than the others      (must be fixed)
#   LENGTH  files that are shorter/longer than the rest – not exported from the same start
#   BITS    a different bit depth than the others                     (harmless, good to know)
#   LOSSY   MP3 / AAC files where WAVs are expected
#   PEAK    files that hit 0 dBFS (possibly clipped) or are silent    (needs ffmpeg)
#   ERROR   files that cannot be read
# The report is also saved to the project's 00_Admin folder.

source "$(dirname "$0")/_common.sh"

PROJECT=""
if [ -n "$1" ] && [ -d "$1" ] && [ ! -f "${1%/}/00_Admin/Session_Log.txt" ]; then
    DIR="$(cd "$1" && pwd)"
else
    PROJECT="$(resolve_project "$1")" || exit 1
    DIR="$PROJECT/07_Received"
    [ -d "$DIR" ] || die "$(basename "$PROJECT") has no 07_Received folder – check any folder with: studio check /path/to/folder"
fi

FF="$(find_tool ffmpeg)"
TMP="$(mktemp "${TMPDIR:-/tmp}/studiocheck.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

total="$(find "$DIR" -type f \( -iname '*.wav' -o -iname '*.aif' -o -iname '*.aiff' -o -iname '*.flac' -o -iname '*.caf' \
          -o -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.ogg' \) -not -name '._*' | wc -l | tr -d ' ')"
[ "$total" -gt 0 ] || die "No audio files found in $DIR"
echo "Checking $total audio file(s) in ${DIR#"$STUDIO_ROOT"/} …" >&2

# one line per file: folder, name, channels, rate, bits, seconds, lossy(0/1), peak dB
n=0
find "$DIR" -type f \( -iname '*.wav' -o -iname '*.aif' -o -iname '*.aiff' -o -iname '*.flac' -o -iname '*.caf' \
     -o -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.ogg' \) -not -name '._*' | sort \
| while IFS= read -r f; do
    n=$((n + 1)); printf '\r  %d / %d' $n "$total" >&2
    rel="${f#"$DIR"/}"; folder="$(dirname "$rel")"; [ "$folder" = "." ] && folder="(top folder)"
    lossy=0; case "$(echo "${f##*.}" | tr '[:upper:]' '[:lower:]')" in mp3|m4a|aac|ogg) lossy=1 ;; esac
    info="$(audio_info "$f")" || info="?	?	?	0"
    peak=""
    if [ -n "$FF" ] && [ "$info" != "?	?	?	0" ]; then
        peak="$("$FF" -hide_banner -nostats -i "$f" -af volumedetect -f null - </dev/null 2>&1 \
                | sed -n 's/.*max_volume: \(.*\) dB/\1/p')"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$folder" "$(basename "$f")" "$info" "$lossy" "$peak"
  done > "$TMP"
printf '\r                    \r' >&2

REPORT="$(awk -F'\t' '
function t(s) { return sprintf("%d:%04.1f", int(s / 60), s - 60 * int(s / 60)) }
function flag(kind, msg) { issues[cur] = issues[cur] sprintf("    %-7s %s\n", kind, msg); nissue++ }
{
    f = $1; if (!(f in seen)) { seen[f] = 1; order[++nf] = f }
    i = ++cnt[f]
    name[f, i] = $2; ch[f, i] = $3; rate[f, i] = $4; bits[f, i] = $5; dur[f, i] = $6 + 0; lossy[f, i] = $7; peak[f, i] = $8
    if ($4 != "?") { rc[f, $4]++; bc[f, $5]++ }
    if ($6 + 0 > maxd[f]) maxd[f] = $6 + 0
}
END {
    for (k = 1; k <= nf; k++) {
        f = order[k]; cur = f
        # most common rate / bit depth in this folder
        mr = ""; mb = ""; best = 0; bestb = 0
        for (i = 1; i <= cnt[f]; i++) {
            if (rc[f, rate[f, i]] > best)  { best = rc[f, rate[f, i]];  mr = rate[f, i] }
            if (bc[f, bits[f, i]] > bestb) { bestb = bc[f, bits[f, i]]; mb = bits[f, i] }
        }
        mono = 0; stereo = 0; short = 0
        for (i = 1; i <= cnt[f]; i++) {
            if (ch[f, i] == 1) mono++; else if (ch[f, i] == 2) stereo++
            if (maxd[f] - dur[f, i] > 0.1) short++
        }
        for (i = 1; i <= cnt[f]; i++) {
            n = name[f, i]
            if (rate[f, i] == "?")            { flag("ERROR",  n " – cannot be read"); continue }
            if (rate[f, i] != mr)             flag("RATE",   n " is " rate[f, i] " Hz (the others: " mr " Hz)")
            if (lossy[f, i] == 1)             flag("LOSSY",  n " is a compressed file, not a WAV")
            else if (bits[f, i] != mb)        flag("BITS",   n " is " bits[f, i] " bit (the others: " mb " bit)")
            if (cnt[f] > 1 && short <= cnt[f] / 2 && maxd[f] - dur[f, i] > 0.1)
                                              flag("LENGTH", n " is " t(dur[f, i]) " (longest file: " t(maxd[f]) ")")
            if (peak[f, i] != "") {
                if (peak[f, i] + 0 >= -0.05)  flag("PEAK",   n " hits 0 dBFS – possibly clipped")
                else if (peak[f, i] + 0 <= -80) flag("PEAK", n " is silent")
            }
        }
        if (cnt[f] > 1 && short > cnt[f] / 2)
            flag("LENGTH", "the files have very different lengths – not exported from the same start point?")
        if (mr != "") { rates[mr] = 1; summary = sprintf("%s Hz / %s bit", mr, mb) } else summary = "unreadable"
        printf "%s\n    %d file(s)  ·  %s  ·  %d mono, %d stereo  ·  longest %s\n%s\n",
               f, cnt[f], summary, mono, stereo, t(maxd[f]), (issues[f] == "" ? "    ✅ ok\n" : issues[f])
    }
    nr = 0; for (r in rates) { nr++; list = list (list == "" ? "" : ", ") r " Hz" }
    if (nr > 1) { printf "NOTE: the folders use different sample rates (%s) – one session rate per song.\n\n", list }
    if (nissue == 0) print "RESULT: ✅ no problems found"
    else             print "RESULT: ⚠️  " nissue " thing(s) to look at"
}' "$TMP")"

HEADER="FILE CHECK   $(date '+%Y-%m-%d %H:%M')   ${DIR#"$STUDIO_ROOT"/}"
[ -n "$FF" ] || HEADER="$HEADER
(Peak / clipping check skipped – needs ffmpeg:  brew install ffmpeg)"

echo "$HEADER"
echo
echo "$REPORT"

if [ -n "$PROJECT" ]; then
    OUT="$PROJECT/00_Admin/Received_Check_$(date +%Y-%m-%d).txt"
    { echo "$HEADER"; echo; echo "$REPORT"; } > "$OUT"
    echo
    echo "Report saved: ${OUT#"$STUDIO_ROOT"/}"
    echo "$(date +%Y-%m-%d)  Received files checked: $(echo "$REPORT" | tail -1 | sed 's/^RESULT: //')" >> "$PROJECT/00_Admin/Session_Log.txt"
fi
