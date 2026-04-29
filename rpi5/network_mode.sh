#!/bin/bash
# =============================================================================
# network_mode.sh — bascule WiFi entre 3 modes via NetworkManager
#
# Modes :
#   client   : connecté à un WiFi (Freebox/Simon), pas d'AP. Mode maison/dev.
#   hotspot  : Pi est AP "LidarScanner" sur 192.168.4.1/24. Mode terrain seul.
#   dual     : connecté STA + AP simultané. Mode scan (GoPro + téléphone).
#   status   : affiche l'état JSON actuel
#
# Usage : sudo network_mode.sh {client|hotspot|dual|status}
# =============================================================================

set -eo pipefail

AP_SSID="LidarScanner"
AP_PSK="lidarscan"
AP_CON="LidarScanner-AP"
AP_IFACE="wlan0"
AP_IP="192.168.4.1/24"

MODE="${1:-status}"

ensure_ap_connection() {
    # Crée la connexion AP si elle n'existe pas
    if ! nmcli -t -f NAME con show | grep -qx "$AP_CON"; then
        nmcli con add \
            type wifi ifname "$AP_IFACE" \
            con-name "$AP_CON" \
            autoconnect no \
            ssid "$AP_SSID" \
            mode ap
        nmcli con modify "$AP_CON" \
            802-11-wireless.band bg \
            802-11-wireless.channel 6 \
            ipv4.method shared \
            ipv4.addresses "$AP_IP" \
            wifi-sec.key-mgmt wpa-psk \
            wifi-sec.psk "$AP_PSK"
    fi
}

# brcmfmac (Pi 5) ne supporte pas STA+AP sur des bandes différentes.
# Si une STA est active, on aligne l'AP sur sa bande/canal pour le mode dual.
# Sinon (mode hotspot pur), on remet l'AP en 2.4 GHz canal 6.
align_ap_channel_to_sta() {
    local sta_freq sta_channel sta_band
    if command -v iw &>/dev/null; then
        sta_freq=$(iw dev "$AP_IFACE" info 2>/dev/null | awk '/channel/ {gsub(/\(/,""); print $4}' | head -1)
        sta_channel=$(iw dev "$AP_IFACE" info 2>/dev/null | awk '/channel/ {print $2}' | head -1)
    fi

    if [ -n "${sta_channel:-}" ] && [ -n "${sta_freq:-}" ]; then
        if [ "$sta_freq" -ge 5000 ]; then
            sta_band="a"
        else
            sta_band="bg"
        fi
        nmcli con modify "$AP_CON" \
            802-11-wireless.band "$sta_band" \
            802-11-wireless.channel "$sta_channel" 2>/dev/null || true
    else
        # Pas de STA active → AP en 2.4 GHz canal 6 (compatible majorité des téléphones)
        nmcli con modify "$AP_CON" \
            802-11-wireless.band bg \
            802-11-wireless.channel 6 2>/dev/null || true
    fi
}

active_sta_connection() {
    # Renvoie le nom de la connexion STA active (WiFi en mode infrastructure), s'il y en a
    nmcli -t -f NAME,TYPE,DEVICE con show --active 2>/dev/null \
        | awk -F: -v iface="$AP_IFACE" '$2=="802-11-wireless" && $3==iface && $1!="'"$AP_CON"'" {print $1; exit}'
}

mode_client() {
    ensure_ap_connection
    nmcli con down "$AP_CON" 2>/dev/null || true
    # Réactiver l'auto-connect des STA
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        nmcli con modify "$name" connection.autoconnect yes 2>/dev/null || true
    done < <(nmcli -t -f NAME,TYPE con show | awk -F: '$2=="802-11-wireless" {print $1}' | grep -vx "$AP_CON" || true)
    # Connecter au WiFi le plus prio (autoconnect-priority le plus haut)
    nmcli device wifi rescan 2>/dev/null || true
    sleep 2
    # Si rien n'est actif, tenter de remonter une connexion connue
    if [ -z "$(active_sta_connection)" ]; then
        for name in $(nmcli -t -f NAME,TYPE con show | awk -F: '$2=="802-11-wireless" {print $1}' | grep -vx "$AP_CON"); do
            nmcli con up "$name" 2>/dev/null && break || true
        done
    fi
}

mode_hotspot() {
    ensure_ap_connection
    # Couper toutes les STA
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        nmcli con down "$name" 2>/dev/null || true
        nmcli con modify "$name" connection.autoconnect no 2>/dev/null || true
    done < <(nmcli -t -f NAME,TYPE con show | awk -F: '$2=="802-11-wireless" {print $1}' | grep -vx "$AP_CON" || true)
    sleep 1
    align_ap_channel_to_sta   # pas de STA → 2.4 GHz canal 6
    nmcli con up "$AP_CON"
}

mode_dual() {
    ensure_ap_connection
    # Garder la STA active + monter l'AP
    # Réactiver autoconnect des STA
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        nmcli con modify "$name" connection.autoconnect yes 2>/dev/null || true
    done < <(nmcli -t -f NAME,TYPE con show | awk -F: '$2=="802-11-wireless" {print $1}' | grep -vx "$AP_CON" || true)
    # Si aucune STA active, en monter une
    if [ -z "$(active_sta_connection)" ]; then
        for name in $(nmcli -t -f NAME,TYPE con show | awk -F: '$2=="802-11-wireless" {print $1}' | grep -vx "$AP_CON"); do
            nmcli con up "$name" 2>/dev/null && break || true
        done
        sleep 3   # laisser le temps à la STA de s'associer
    fi
    # Aligner l'AP sur le canal de la STA (contrainte brcmfmac)
    align_ap_channel_to_sta
    nmcli con down "$AP_CON" 2>/dev/null || true
    nmcli con up "$AP_CON"
}

status_json() {
    local sta_name sta_ssid sta_ip ap_active ap_clients current_mode
    sta_name="$(active_sta_connection)"
    if [ -n "$sta_name" ]; then
        sta_ssid="$(nmcli -t -f 802-11-wireless.ssid con show "$sta_name" 2>/dev/null | sed 's/^[^:]*://')"
        sta_ip="$(ip -4 -o addr show dev "$AP_IFACE" 2>/dev/null | awk '{print $4}' | grep -v '^192\.168\.4\.' | head -1)"
    else
        sta_ssid=""
        sta_ip=""
    fi

    if nmcli -t -f NAME con show --active 2>/dev/null | grep -qx "$AP_CON"; then
        ap_active="true"
        # Compter les clients connectés à l'AP via la table ARP/leases
        ap_clients=$(ip neigh show dev "$AP_IFACE" 2>/dev/null | grep -c "REACHABLE\|STALE" || echo 0)
    else
        ap_active="false"
        ap_clients=0
    fi

    if [ "$ap_active" = "true" ] && [ -n "$sta_name" ]; then
        current_mode="dual"
    elif [ "$ap_active" = "true" ]; then
        current_mode="hotspot"
    elif [ -n "$sta_name" ]; then
        current_mode="client"
    else
        current_mode="offline"
    fi

    cat <<EOF
{
  "mode": "$current_mode",
  "sta": {
    "connected": $([ -n "$sta_name" ] && echo true || echo false),
    "ssid": "$sta_ssid",
    "ip": "${sta_ip%%/*}"
  },
  "ap": {
    "active": $ap_active,
    "ssid": "$AP_SSID",
    "ip": "${AP_IP%%/*}",
    "clients": $ap_clients
  }
}
EOF
}

case "$MODE" in
    client)  mode_client; status_json ;;
    hotspot) mode_hotspot; status_json ;;
    dual)    mode_dual; status_json ;;
    status)  status_json ;;
    *)
        echo "Usage: $0 {client|hotspot|dual|status}" >&2
        exit 1
        ;;
esac
