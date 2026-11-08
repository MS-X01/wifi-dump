#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  wifi_dump.sh  —  Wi-Fi Password Extractor
#  Author  : Mohammad Sadra Naderi (ZVitoX)  —  github.com/MS-X01
#  Repo    : github.com/MS-X01/wifi-dump
#  Linux   : nmcli · NetworkManager · wpa_supplicant · iwd · connman
#  macOS   : Keychain
# ═══════════════════════════════════════════════════════════════

set -uo pipefail

VERSION="1.1.0"
REPO_URL="github.com/MS-X01/wifi-dump"

# ── Colors (auto-disabled for non-tty or NO_COLOR) ──────────────
USE_COLOR=true
[[ -t 1 ]] || USE_COLOR=false
[[ -n "${NO_COLOR:-}" ]] && USE_COLOR=false

apply_colors() {
    if $USE_COLOR; then
        RB='\033[1;31m'; GB='\033[1;32m'; YLW='\033[1;33m'
        CB='\033[1;36m'; CYN='\033[0;36m'; BLU='\033[0;34m'
        WHT='\033[1;37m'; DIM='\033[2m';  RST='\033[0m'
        BOLD='\033[1m';   ITALIC='\033[3m'
    else
        RB=''; GB=''; YLW=''; CB=''; CYN=''; BLU=''
        WHT=''; DIM=''; RST=''; BOLD=''; ITALIC=''
    fi
}
apply_colors

# ── Globals ────────────────────────────────────────────────────
declare -a G_SSIDS=()
declare -a G_AUTHS=()
declare -a G_PSKS=()
declare -a G_METHODS=()
declare -a G_BANDS=()
declare -a G_BSSIDS=()
declare -a G_TIMESTAMPS=()

OS=""
MODE="select"
OUTPUT_FILE=""
OUTPUT_FORMAT="table"
FILTER=""
DEBUG=false
QUIET=false

# ── Banner ─────────────────────────────────────────────────────
banner() {
    $QUIET && return
    echo -e "${CB}${BOLD}"
    echo "  ██╗    ██╗██╗███████╗██╗    ██████╗ ██╗   ██╗███╗   ███╗██████╗ "
    echo "  ██║    ██║██║██╔════╝██║    ██╔══██╗██║   ██║████╗ ████║██╔══██╗"
    echo "  ██║ █╗ ██║██║█████╗  ██║    ██║  ██║██║   ██║██╔████╔██║██████╔╝"
    echo "  ██║███╗██║██║██╔══╝  ██║    ██║  ██║██║   ██║██║╚██╔╝██║██╔═══╝ "
    echo "  ╚███╔███╔╝██║██║     ██║    ██████╔╝╚██████╔╝██║ ╚═╝ ██║██║     "
    echo "   ╚══╝╚══╝ ╚═╝╚═╝     ╚═╝    ╚═════╝  ╚═════╝ ╚═╝     ╚═╝╚═╝     "
    echo -e "${RST}"
    printf "  ${DIM}Wi-Fi Password Extractor  v%s${RST}   ${CYN}by ${BOLD}Mohammad Sadra Naderi${RST}\n" "$VERSION"
    printf "  ${DIM}%s  %s   ·   %s${RST}\n\n" "$(uname -s)" "$(uname -r)" "$REPO_URL"
}

# ── Helpers ────────────────────────────────────────────────────
die()  { echo -e "\n  ${RB}[✗]${RST}  $*\n" >&2; exit 1; }
warn() { $QUIET || echo -e "  ${YLW}[!]${RST}  $*"; }
info() { $QUIET || echo -e "  ${BLU}[i]${RST}  $*"; }
ok()   { $QUIET || echo -e "  ${GB}[✓]${RST}  $*"; }
dbg()  { $DEBUG && echo -e "  ${DIM}[DBG] $*${RST}" || true; }
sep()  { echo -e "  ${DIM}$(printf '─%.0s' {1..52})${RST}"; }

# ── OS / root ──────────────────────────────────────────────────
detect_os() {
    case "$(uname -s)" in
        Linux)  OS="linux"  ;;
        Darwin) OS="macos"  ;;
        *)      die "Unsupported OS: $(uname -s)" ;;
    esac
}

check_root() {
    [[ "$OS" == "macos" ]] && return
    [[ $EUID -eq 0 ]] || die "Needs root on Linux.\n  ${DIM}→  sudo $(basename "$0")${RST}"
}

# ── Add entry (skip dupes) ─────────────────────────────────────
add_entry() {
    local ssid="$1" auth="$2" psk="$3" method="$4" \
          band="${5:--}" bssid="${6:--}" ts="${7:--}"
    [[ -z "$ssid" ]] && return
    for s in "${G_SSIDS[@]+"${G_SSIDS[@]}"}"; do
        [[ "$s" == "$ssid" ]] && return
    done
    G_SSIDS+=("$ssid");  G_AUTHS+=("$auth");    G_PSKS+=("$psk")
    G_METHODS+=("$method"); G_BANDS+=("$band")
    G_BSSIDS+=("$bssid"); G_TIMESTAMPS+=("$ts")
}

# ── Format timestamp ───────────────────────────────────────────
fmt_ts() {
    local ts="$1"
    [[ "$ts" == "-" || -z "$ts" || "$ts" == "0" ]] && echo "-" && return
    date -d "@$ts" "+%Y-%m-%d %H:%M" 2>/dev/null \
        || date -r "$ts" "+%Y-%m-%d %H:%M" 2>/dev/null \
        || echo "-"
}

# ══════════════════════════════════════════════════════════════
#   LINUX EXTRACTORS
# ══════════════════════════════════════════════════════════════

extract_nmcli() {
    command -v nmcli &>/dev/null || return 1
    nmcli -t general status &>/dev/null || return 1

    local found=0
    while IFS=: read -r name type; do
        [[ "$type" == *"wireless"* || "$type" == *"wifi"* ]] || continue

        local psk auth band bssid ts
        psk=$(nmcli --show-secrets -t -f 802-11-wireless-security.psk \
                connection show "$name" 2>/dev/null | head -1 | cut -d: -f2-)
        auth=$(nmcli -t -f 802-11-wireless-security.key-mgmt \
                connection show "$name" 2>/dev/null | head -1 | cut -d: -f2-)
        band=$(nmcli -t -f 802-11-wireless.band \
                connection show "$name" 2>/dev/null | head -1 | cut -d: -f2-)
        bssid=$(nmcli -t -f 802-11-wireless.bssid \
                connection show "$name" 2>/dev/null | head -1 | cut -d: -f2-)
        ts=$(nmcli -t -f connection.timestamp \
                connection show "$name" 2>/dev/null | head -1 | cut -d: -f2-)

        # Normalize band
        case "$band" in
            a)  band="5 GHz"  ;;
            bg) band="2.4 GHz" ;;
            *)  band="-"      ;;
        esac

        [[ -z "$psk"   || "$psk"   == "--" ]] && psk="<none>"
        [[ -z "$auth"  || "$auth"  == "--" ]] && auth="open"
        [[ -z "$bssid" || "$bssid" == "--" ]] && bssid="-"
        [[ -z "$ts"    || "$ts"    == "--" ]] && ts="-"

        add_entry "$name" "$auth" "$psk" "nmcli" "$band" "$bssid" "$ts"
        (( found++ )) || true
    done < <(nmcli -t -f NAME,TYPE connection show 2>/dev/null)

    (( found > 0 ))
}

extract_nm_files() {
    local found=0
    local -a dirs=(
        "/etc/NetworkManager/system-connections"
        "/run/NetworkManager/system-connections"
        "/usr/lib/NetworkManager/system-connections"
    )
    for dir in "${dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r -d '' f; do
            grep -qiE "^\[wifi\]|^type=wifi|^type=802-11-wireless" "$f" 2>/dev/null || continue
            local ssid auth psk
            ssid=$(grep -iE "^ssid=" "$f" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '\r\n')
            auth=$(grep -iE "^key-mgmt=" "$f" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '\r\n')
            psk=$(grep -iE "^psk=" "$f" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '\r\n')
            [[ -z "$ssid" ]] && ssid="$(basename "$f" .nmconnection)"
            [[ -z "$auth" ]] && auth="open"
            [[ -z "$psk"  ]] && psk="<none>"
            add_entry "$ssid" "$auth" "$psk" "NM-files"
            (( found++ )) || true
        done < <(find "$dir" -maxdepth 2 -type f -print0 2>/dev/null)
    done
    (( found > 0 ))
}

extract_wpa() {
    local -a confs=()
    while IFS= read -r -d '' f; do confs+=("$f"); done \
        < <(find /etc/wpa_supplicant /run/wpa_supplicant -name "*.conf" -print0 2>/dev/null)
    (( ${#confs[@]} > 0 )) || return 1

    local found=0
    for c in "${confs[@]}"; do
        local in_block=0 ssid="" psk="" key_mgmt=""
        while IFS= read -r line; do
            line="${line#"${line%%[![:space:]]*}"}"
            case "$line" in
                "network={"*) in_block=1; ssid=""; psk=""; key_mgmt="" ;;
                "}"*)
                    if (( in_block )) && [[ -n "$ssid" ]]; then
                        add_entry "$ssid" "${key_mgmt:-WPA-PSK}" "${psk:-<none>}" "wpa_supplicant"
                        (( found++ )) || true
                    fi; in_block=0 ;;
                ssid=*)    (( in_block )) && ssid="${line#ssid=}"    && ssid="${ssid//\"/}" ;;
                psk=*)     (( in_block )) && psk="${line#psk=}"      && psk="${psk//\"/}"  ;;
                key_mgmt=*)(( in_block )) && key_mgmt="${line#key_mgmt=}" ;;
            esac
        done < "$c"
    done
    (( found > 0 ))
}

extract_iwd() {
    local dir="/var/lib/iwd"; [[ -d "$dir" ]] || return 1
    local found=0
    while IFS= read -r -d '' f; do
        local ssid pass auth
        ssid="$(basename "$f")"; ssid="${ssid%.psk}"; ssid="${ssid%.8021x}"; ssid="${ssid%.open}"
        pass=$(grep -i "^Passphrase=" "$f" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '\r\n')
        [[ -z "$pass" ]] && auth="open" || auth="WPA-PSK"
        add_entry "$ssid" "$auth" "${pass:-<none>}" "iwd"
        (( found++ )) || true
    done < <(find "$dir" -maxdepth 2 \( -name "*.psk" -o -name "*.8021x" -o -name "*.open" \) -print0 2>/dev/null)
    (( found > 0 ))
}

extract_connman() {
    local dir="/var/lib/connman"; [[ -d "$dir" ]] || return 1
    local found=0
    while IFS= read -r sf; do
        local ssid psk auth
        ssid=$(grep -i "^Name=" "$sf" 2>/dev/null | head -1 | cut -d'=' -f2-)
        psk=$(grep -i "^Passphrase=" "$sf" 2>/dev/null | head -1 | cut -d'=' -f2-)
        auth=$(grep -i "^Security=" "$sf" 2>/dev/null | head -1 | cut -d'=' -f2-)
        [[ -z "$ssid" ]] && continue
        add_entry "$ssid" "${auth:-unknown}" "${psk:-<none>}" "connman"
        (( found++ )) || true
    done < <(find "$dir" -name "settings" 2>/dev/null)
    (( found > 0 ))
}

# ── macOS ──────────────────────────────────────────────────────
extract_macos() {
    command -v networksetup &>/dev/null || die "'networksetup' not found."
    local iface
    iface=$(networksetup -listallhardwareports 2>/dev/null \
        | awk '/Wi-Fi|AirPort/{f=1} f && /Device:/{print $2; exit}')
    [[ -z "$iface" ]] && iface="en0"
    info "Interface: ${BOLD}$iface${RST}"

    local found=0
    while IFS= read -r ssid; do
        ssid="${ssid#"${ssid%%[![:space:]]*}"}"
        [[ -z "$ssid" || "$ssid" == "Preferred networks on"* ]] && continue
        local psk
        psk=$(security find-generic-password -D "AirPort network password" -a "$ssid" -w 2>/dev/null \
              || security find-generic-password -D "802.1X Password" -a "$ssid" -w 2>/dev/null \
              || echo "<none>")
        add_entry "$ssid" "WPA/WPA2" "$psk" "Keychain"
        (( found++ )) || true
    done < <(networksetup -listpreferredwirelessnetworks "$iface" 2>/dev/null | tail -n +2)
    (( found > 0 ))
}

# ── Debug scan ─────────────────────────────────────────────────
debug_scan() {
    echo -e "  ${CB}${BOLD}[ DEBUG SCAN ]${RST}\n"
    echo -e "  ${YLW}nmcli${RST}"
    if command -v nmcli &>/dev/null; then
        echo -e "    ${GB}installed${RST}"
        nmcli -t -f NAME,TYPE connection show 2>/dev/null | sed 's/^/    /' | head -20
    else
        echo -e "    ${RB}not found${RST}"
    fi

    echo -e "\n  ${YLW}NetworkManager dirs${RST}"
    for d in /etc/NetworkManager/system-connections \
              /run/NetworkManager/system-connections \
              /usr/lib/NetworkManager/system-connections; do
        if [[ -d "$d" ]]; then
            echo -e "    ${GB}$d${RST}"
            find "$d" -maxdepth 2 -type f 2>/dev/null | sed 's/^/      /'
        else
            echo -e "    ${DIM}$d  (not found)${RST}"
        fi
    done

    echo -e "\n  ${YLW}wpa_supplicant${RST}"
    find /etc/wpa_supplicant /run/wpa_supplicant -name "*.conf" 2>/dev/null \
        | sed 's/^/    /' || echo -e "    ${DIM}none${RST}"

    echo -e "\n  ${YLW}iwd${RST}"
    [[ -d /var/lib/iwd ]] \
        && find /var/lib/iwd -maxdepth 2 -type f 2>/dev/null | sed 's/^/    /' \
        || echo -e "    ${DIM}not found${RST}"
    echo ""; exit 0
}

# ══════════════════════════════════════════════════════════════
#   COLLECT — compact scan table
# ══════════════════════════════════════════════════════════════
collect_all() {
    if [[ "$OS" == "macos" ]]; then
        extract_macos || die "macOS Keychain extraction failed."
    else
        # Run all methods, track counts per method
        declare -A METHOD_COUNTS=(
            [nmcli]=0 [nm-files]=0 [wpa]=0 [iwd]=0 [connman]=0
        )

        local before

        before=${#G_SSIDS[@]}
        extract_nmcli      2>/dev/null && true
        METHOD_COUNTS[nmcli]=$(( ${#G_SSIDS[@]} - before ))

        before=${#G_SSIDS[@]}
        extract_nm_files   2>/dev/null && true
        METHOD_COUNTS[nm-files]=$(( ${#G_SSIDS[@]} - before ))

        before=${#G_SSIDS[@]}
        extract_wpa        2>/dev/null && true
        METHOD_COUNTS[wpa]=$(( ${#G_SSIDS[@]} - before ))

        before=${#G_SSIDS[@]}
        extract_iwd        2>/dev/null && true
        METHOD_COUNTS[iwd]=$(( ${#G_SSIDS[@]} - before ))

        before=${#G_SSIDS[@]}
        extract_connman    2>/dev/null && true
        METHOD_COUNTS[connman]=$(( ${#G_SSIDS[@]} - before ))

        # Print compact scan summary
        if ! $QUIET; then
            echo -e "  ${BOLD}Scan results:${RST}\n"
            local methods=("nmcli" "nm-files" "wpa" "iwd" "connman")
            local labels=("nmcli" "NetworkManager files" "wpa_supplicant" "iwd" "connman")
            for idx in "${!methods[@]}"; do
                local m="${methods[$idx]}" label="${labels[$idx]}"
                local n="${METHOD_COUNTS[$m]}"
                if (( n > 0 )); then
                    printf "  ${DIM}  %-22s${RST}  ${GB}%-3s  ✓${RST}\n" "$label" "$n profiles"
                else
                    printf "  ${DIM}  %-22s  —${RST}\n" "$label"
                fi
            done
            echo ""
        fi
    fi

    if (( ${#G_SSIDS[@]} == 0 )); then
        warn "Nothing found. Run ${BOLD}--debug${RST} to diagnose:\n  ${DIM}sudo $(basename "$0") --debug${RST}"
        exit 1
    fi

    ok "${BOLD}${#G_SSIDS[@]}${RST} unique profile(s) found\n"
}

# ══════════════════════════════════════════════════════════════
#   DISPLAY
# ══════════════════════════════════════════════════════════════
# ── Filter ─────────────────────────────────────────────────────
apply_filter() {
    local pattern="$1"
    [[ -z "$pattern" ]] && return
    local lc_pattern; lc_pattern="${pattern,,}"
    local -a ns=() na=() np=() nm=() nb=() nbs=() nt=()
    for i in "${!G_SSIDS[@]}"; do
        local lc_ssid="${G_SSIDS[$i],,}"
        [[ "$lc_ssid" == *"$lc_pattern"* ]] || continue
        ns+=("${G_SSIDS[$i]}"); na+=("${G_AUTHS[$i]}"); np+=("${G_PSKS[$i]}")
        nm+=("${G_METHODS[$i]}"); nb+=("${G_BANDS[$i]}")
        nbs+=("${G_BSSIDS[$i]}"); nt+=("${G_TIMESTAMPS[$i]}")
    done
    G_SSIDS=("${ns[@]+"${ns[@]}"}");     G_AUTHS=("${na[@]+"${na[@]}"}")
    G_PSKS=("${np[@]+"${np[@]}"}");      G_METHODS=("${nm[@]+"${nm[@]}"}")
    G_BANDS=("${nb[@]+"${nb[@]}"}");     G_BSSIDS=("${nbs[@]+"${nbs[@]}"}")
    G_TIMESTAMPS=("${nt[@]+"${nt[@]}"}")
}

render_entry() {
    local i="$1" show_idx="${2:-true}"
    local ssid="${G_SSIDS[$i]}"   auth="${G_AUTHS[$i]}"
    local psk="${G_PSKS[$i]}"     method="${G_METHODS[$i]}"
    local band="${G_BANDS[$i]}"   bssid="${G_BSSIDS[$i]}"
    local ts="${G_TIMESTAMPS[$i]}"

    local psk_render
    if [[ "$psk" == "<none>" ]]; then
        psk_render="${DIM}<none>${RST}"
    else
        psk_render="${RB}${BOLD}${psk}${RST}"
    fi

    local ts_fmt; ts_fmt="$(fmt_ts "$ts")"

    sep
    $show_idx && echo -e "  ${CB}${BOLD}#$((i+1))${RST}"
    printf "  ${WHT}%-12s${RST}  ${GB}%s${RST}\n"          "SSID"       "$ssid"
    printf "  ${WHT}%-12s${RST}  ${YLW}%s${RST}\n"         "Auth"       "$auth"
    printf "  ${WHT}%-12s${RST}  %b\n"                     "Password"   "$psk_render"
    [[ "$band"  != "-" && -n "$band"  ]] && \
    printf "  ${WHT}%-12s${RST}  ${DIM}%s${RST}\n"         "Band"       "$band"
    [[ "$bssid" != "-" && -n "$bssid" ]] && \
    printf "  ${WHT}%-12s${RST}  ${DIM}%s${RST}\n"         "BSSID"      "$bssid"
    [[ "$ts_fmt" != "-" ]] && \
    printf "  ${WHT}%-12s${RST}  ${DIM}%s${RST}\n"         "Last used"  "$ts_fmt"
    printf "  ${WHT}%-12s${RST}  ${DIM}%s${RST}\n"         "Source"     "$method"
}

dump_all() {
    echo -e "  ${CB}${BOLD}All Wi-Fi Profiles  [${#G_SSIDS[@]}]${RST}"
    for i in "${!G_SSIDS[@]}"; do render_entry "$i"; done
    sep; echo ""
}

interactive_select() {
    echo -e "  ${CB}${BOLD}Saved Wi-Fi Networks${RST}\n"
    for i in "${!G_SSIDS[@]}"; do
        local extra="${DIM}${G_AUTHS[$i]}"
        [[ "${G_BANDS[$i]}" != "-" && -n "${G_BANDS[$i]}" ]] && extra+="  ${G_BANDS[$i]}"
        extra+="${RST}"
        printf "  ${CB}[%2d ]${RST}  ${GB}%-34s${RST}  %b\n" "$((i+1))" "${G_SSIDS[$i]}" "$extra"
    done

    local max="${#G_SSIDS[@]}"
    echo ""
    while true; do
        printf "  ${BOLD}Select [1-${max}] or q to quit: ${RST}"
        read -r choice
        [[ "$choice" =~ ^[qQ]$ ]] && echo "" && exit 0
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= max )); then
            echo ""; render_entry "$(( choice-1 ))" false; sep; echo ""; break
        fi
        warn "Enter a number between 1 and ${max}."
    done
}

# ── Export ─────────────────────────────────────────────────────
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
    printf '%s' "$s"
}

export_table() {
    {
        printf "# Wi-Fi Dump — %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
        printf "# Author  : Mohammad Sadra Naderi (ZVitoX) — %s\n" "$REPO_URL"
        printf "# System  : %s %s\n" "$(uname -s)" "$(uname -r)"
        printf "# ─────────────────────────────────────────────────────────\n"
        printf "%-34s %-12s %-28s %-10s %-20s %s\n" \
            "SSID" "AUTH" "PASSWORD" "BAND" "LAST USED" "SOURCE"
        printf "%-34s %-12s %-28s %-10s %-20s %s\n" \
            "----" "----" "--------" "----" "---------" "------"
        for i in "${!G_SSIDS[@]}"; do
            printf "%-34s %-12s %-28s %-10s %-20s %s\n" \
                "${G_SSIDS[$i]}" "${G_AUTHS[$i]}" "${G_PSKS[$i]}" \
                "${G_BANDS[$i]}" "$(fmt_ts "${G_TIMESTAMPS[$i]}")" "${G_METHODS[$i]}"
        done
    } > "$OUTPUT_FILE"
}

export_json() {
    {
        printf '{\n  "generated": "%s",\n  "system": "%s %s",\n  "count": %d,\n  "networks": [\n' \
            "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$(uname -s)" "$(uname -r)" "${#G_SSIDS[@]}"
        local last=$(( ${#G_SSIDS[@]} - 1 ))
        for i in "${!G_SSIDS[@]}"; do
            printf '    {\n'
            printf '      "ssid": "%s",\n'       "$(json_escape "${G_SSIDS[$i]}")"
            printf '      "auth": "%s",\n'       "$(json_escape "${G_AUTHS[$i]}")"
            printf '      "password": "%s",\n'   "$(json_escape "${G_PSKS[$i]}")"
            printf '      "band": "%s",\n'       "$(json_escape "${G_BANDS[$i]}")"
            printf '      "bssid": "%s",\n'      "$(json_escape "${G_BSSIDS[$i]}")"
            printf '      "last_used": "%s",\n'  "$(json_escape "$(fmt_ts "${G_TIMESTAMPS[$i]}")")"
            printf '      "source": "%s"\n'      "$(json_escape "${G_METHODS[$i]}")"
            if (( i == last )); then printf '    }\n'; else printf '    },\n'; fi
        done
        printf '  ]\n}\n'
    } > "$OUTPUT_FILE"
}

csv_escape() {
    local s="$1"
    if [[ "$s" == *'"'* || "$s" == *,* || "$s" == *$'\n'* ]]; then
        s="${s//\"/\"\"}"
        printf '"%s"' "$s"
    else
        printf '%s' "$s"
    fi
}

export_csv() {
    {
        printf 'ssid,auth,password,band,bssid,last_used,source\n'
        for i in "${!G_SSIDS[@]}"; do
            printf '%s,%s,%s,%s,%s,%s,%s\n' \
                "$(csv_escape "${G_SSIDS[$i]}")" "$(csv_escape "${G_AUTHS[$i]}")" \
                "$(csv_escape "${G_PSKS[$i]}")"  "$(csv_escape "${G_BANDS[$i]}")" \
                "$(csv_escape "${G_BSSIDS[$i]}")" "$(csv_escape "$(fmt_ts "${G_TIMESTAMPS[$i]}")")" \
                "$(csv_escape "${G_METHODS[$i]}")"
        done
    } > "$OUTPUT_FILE"
}

export_file() {
    case "$OUTPUT_FORMAT" in
        json) export_json  ;;
        csv)  export_csv   ;;
        *)    export_table ;;
    esac
    # exported file contains plaintext credentials — never leave it world/group-readable
    chmod 600 "$OUTPUT_FILE" 2>/dev/null
    ok "Exported → ${BOLD}$OUTPUT_FILE${RST}  ${DIM}($OUTPUT_FORMAT, chmod 600)${RST}"
}

# ── Usage ──────────────────────────────────────────────────────
usage() {
    cat <<EOF

${BOLD}wifi_dump.sh${RST} — Wi-Fi Password Extractor  ${DIM}v${VERSION}${RST}

${BOLD}Usage:${RST}
  [sudo] $(basename "$0") [OPTIONS]

${BOLD}Modes${RST}
  ${CB}-a, --all${RST}               Dump every saved profile at once
  ${CB}-s, --select${RST}            Interactive selector ${DIM}(default)${RST}

${BOLD}Output${RST}
  ${CB}-o, --output FILE${RST}            Save results to FILE
  ${CB}-f, --format {table,json,csv}${RST}  Format for --output ${DIM}(default: table)${RST}
  ${CB}-g, --filter PATTERN${RST}         Only networks whose SSID contains PATTERN ${DIM}(case-insensitive)${RST}

${BOLD}Other${RST}
  ${CB}    --debug${RST}             Run a diagnostic scan (which sources exist, raw paths)
  ${CB}    --no-color${RST}          Disable ANSI colors ${DIM}(auto-off for non-tty / NO_COLOR)${RST}
  ${CB}-q, --quiet${RST}             Suppress info/banner output
  ${CB}-v, --version${RST}           Print version and exit
  ${CB}-h, --help${RST}              This help

${BOLD}Examples${RST}
  ${DIM}sudo $(basename "$0")${RST}                         interactive picker
  ${DIM}sudo $(basename "$0") -a${RST}                       dump everything to the terminal
  ${DIM}sudo $(basename "$0") -a -o wifi.txt${RST}           dump + save as a text table
  ${DIM}sudo $(basename "$0") -a -o wifi.json -f json${RST}  dump + save as JSON
  ${DIM}sudo $(basename "$0") -a -o wifi.csv -f csv${RST}    dump + save as CSV
  ${DIM}sudo $(basename "$0") -a -g home${RST}               only SSIDs containing "home"

${BOLD}Exit status${RST}
  0  success
  1  error (not root, unsupported OS, nothing found, bad argument)

$REPO_URL
EOF
}

# ── Main ───────────────────────────────────────────────────────
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--all)      MODE="all"     ;;
            -s|--select)   MODE="select"  ;;
            -o|--output)   shift; OUTPUT_FILE="${1:-}" ;;
            -f|--format)   shift; OUTPUT_FORMAT="${1:-table}" ;;
            -g|--filter)   shift; FILTER="${1:-}" ;;
            --debug)       DEBUG=true     ;;
            --no-color)    USE_COLOR=false; apply_colors ;;
            -q|--quiet)    QUIET=true     ;;
            -v|--version)  echo "wifi_dump.sh v$VERSION"; exit 0 ;;
            -h|--help)     usage; exit 0  ;;
            *) die "Unknown option: $1\n  Run '$(basename "$0") --help'" ;;
        esac
        shift
    done

    case "$OUTPUT_FORMAT" in
        table|json|csv) ;;
        *) die "Unknown format: $OUTPUT_FORMAT  (expected 'table', 'json' or 'csv')" ;;
    esac

    banner
    detect_os
    check_root
    $DEBUG && debug_scan
    collect_all
    apply_filter "$FILTER"
    if [[ -n "$FILTER" && "${#G_SSIDS[@]}" -eq 0 ]]; then
        die "No saved network matches the filter: '$FILTER'"
    fi

    case "$MODE" in
        all)    dump_all ;;
        select) interactive_select ;;
    esac

    [[ -n "$OUTPUT_FILE" ]] && export_file
}

main "$@"
