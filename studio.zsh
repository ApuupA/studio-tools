# The "studio" command with Tab completion for zsh.
# Loaded from ~/.zshrc (install_studio_command.sh adds the line).
#
#   studio <Tab>             -> start end new add archive backup status list plugins tags open cd
#   studio add nig<Tab>      -> studio add 2026-10_Nightfall_First_Light
#   studio new --type <Tab>  -> full rec mix write master
#
# Project names complete from ANY part of the name, upper/lower case doesn't matter.

STUDIO_SCRIPTS="${${(%):-%x}:A:h}"

studio() {
    if [[ "$1" == cd ]]; then
        local p
        p="$("$STUDIO_SCRIPTS/studio" _path "$2")" && cd "$p"
    else
        "$STUDIO_SCRIPTS/studio" "$@"
    fi
}

_studio_projects() {
    local -a names
    names=("${(@f)$("$STUDIO_SCRIPTS/studio" _projects)}")
    compadd -M 'm:{a-zA-Z}={A-Za-z} l:|=* r:|=*' -a names
}

_studio() {
    local -a cmds
    cmds=(
        'init:set up a Studio folder (structure, double-click files, command)'
        'start:start session (Studio Mode on)'
        'end:end session (note, backup, Studio Mode off)'
        'new:create a new project'
        'add:add songs / fill empty song folders'
        'archive:move a finished project to the archive SSD'
        'check:check received files before importing'
        'mp3:MP3 copies of the final mixes / masters'
        'approve:choose the approved version of a mix / master'
        'deliver:build the client delivery package'
        'backup:backup to the SSD now'
        'status:overview of projects, sizes, notes and backup'
        'list:list all projects'
        'plugins:plugin inventory (run before updates)'
        'tags:re-apply the coloured Finder tags'
        'open:open a project folder in Finder'
        'cd:go to a project folder'
        'help:show help'
    )
    if (( CURRENT == 2 )); then
        _describe 'studio command' cmds
        return
    fi

    local cmd="$words[2]" prev="$words[CURRENT-1]" cur="$words[CURRENT]"

    # values for options
    case "$prev" in
        --type) compadd full rec mix write master; return ;;
        --daw)  compadd pt cb both; return ;;
        --pt)   compadd -- ${(f)"$("$STUDIO_SCRIPTS/studio" _templates pt)"}; return ;;
        --cb)   compadd -- ${(f)"$("$STUDIO_SCRIPTS/studio" _templates cb)"}; return ;;
        --code) return ;;
    esac

    case "$cmd" in
        new)
            [[ "$cur" == -* ]] && compadd -- --type --code --daw --pt --cb ;;
        add|archive|open|cd|check|mp3|deliver|approve)
            if [[ "$cur" == -* ]]; then
                case "$cmd" in
                    add)     compadd -- --daw --pt --cb ;;
                    archive) compadd -- --no-keep ;;
                    mp3)     compadd -- --all ;;
                    deliver) compadd -- --masters --mixes --stems --demos --songs --all --no-mp3 --no-zip ;;
                esac
                return
            fi
            # Is the project already given? (first word that is not an option or option value)
            local i w have=0
            for (( i = 3; i < CURRENT; i++ )); do
                w="$words[i]"
                if [[ "$w" == --daw || "$w" == --pt || "$w" == --cb ]]; then (( i++ )); continue; fi
                [[ "$w" == -* ]] && continue
                have=1; break
            done
            if (( ! have )); then
                _studio_projects
                # check and mp3 also take folders / files
                [[ "$cmd" == check || "$cmd" == mp3 ]] && _files
            fi ;;
    esac
}

(( $+functions[compdef] )) || { autoload -Uz compinit && compinit }
compdef _studio studio
