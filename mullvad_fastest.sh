#!/usr/bin/env bash


die() {
  echo -e "[⚠️ ] Error: $1" >&2
  exit 1
}

PROGRAM="${0##*/}"
ARGS=( "$@" )
SELF="${BASH_SOURCE[0]}"
[[ $SELF == */* ]] || SELF="./$SELF"
SELF="$(cd "${SELF%/*}" && pwd -P)/${SELF##*/}"
#[[ $UID == 0 ]] || exec sudo -p "[?] $PROGRAM must be run as root. Please enter the password for %u to continue: " -- "$BASH" -- "$SELF" "${ARGS[@]}"
WG_CONFIGS="/etc/wireguard"
[[ ${BASH_VERSINFO[0]} -ge 4 ]] || die "bash ${BASH_VERSINFO[0]} detected, when ${RED}bash 4+${NC} required"

# color ref: https://gist.github.com/vratiu/9780109
UCyan="\033[4;36m" # Underlined Cyan
RED='\033[1;31m'   # Red color
GREEN='\033[0;32m' # Green color"
NC='\033[0m'       # No Color



# check deps
type curl &>/dev/null || die "Please install ${RED}curl${NC} and then try again."
type boringtun &>/dev/null || die "${RED}boringtun${NC} not installed."
type wg &>/dev/null || die "${RED}Wireguard${NC} not installed."
type wg-quick &>/dev/null || die "${RED}wg-quick${NC} not installed. Install before proceeding."
type fping &>/dev/null || die "${RED}fping${NC} missing - exiting."

set -e

echo "[❇️ ] Contacting Mullvad Wireguard API for server locations."
declare -A SERVER_ENDPOINTS
declare -A SERVER_PUBLIC_KEYS
declare -A SERVER_LOCATIONS
declare -A SERVER_IP
declare -a SERVER_CODES

RESPONSE="$(curl -LsS https://api.mullvad.net/public/relays/wireguard/v1/)" || die "${RED}Unable to connect to Mullvad API.${NC}"
FIELDS="$(jq -r 'foreach .countries[] as $country (.; .; foreach $country.cities[] as $city (.; .; foreach $city.relays[] as $relay (.; .; $country.name, $city.name, $relay.hostname, $relay.public_key, $relay.ipv4_addr_in)))' <<<"$RESPONSE")" || die "${RED}Unable to parse response.${NC}"
while read -r COUNTRY && read -r CITY && read -r HOSTNAME && read -r PUBKEY && read -r IPADDR; do
  CODE="${HOSTNAME%-wireguard}"
  SERVER_CODES+=( "$CODE" )
  SERVER_LOCATIONS["$CODE"]="$COUNTRY,$CITY"
  SERVER_PUBLIC_KEYS["$CODE"]="$PUBKEY"
  SERVER_IP["$CODE"]="$IPADDR"
  SERVER_ENDPOINTS["$CODE"]="$IPADDR:51820"
done <<<"$FIELDS"

shopt -s nocasematch
for CODE in "${SERVER_CODES[@]}"; do
  echo ${SERVER_LOCATIONS["$CODE"]},$CODE,${SERVER_IP["$CODE"]} >> mullvad_host.list
done
shopt -u nocasematch

echo "[❇️ ] Finding lowest latency endpoint."
# fping outputs to stderr. fuck.
# fping sucks -- adding ||true because if dead hosts appear (as "-"), fping exits uncleanly
fping -C 1 -q `cat mullvad_host.list | awk -F, '{print $NF}' | xargs` 2>> host_latency.list || true


# sort latency list
# find fastest wg SERVER_ENDPOINTS
QUICKEST_ENDPOINT=$(sort -n -k3 host_latency.list | grep -v "-" | head -1 | awk '{print $1}')
QUICKEST_LATENCY=$(sort -n -k3 host_latency.list | grep -v "-" | head -1 | awk '{print $3}')

echo "[❇️ ] Found $QUICKEST_ENDPOINT @ $QUICKEST_LATENCY ms."

echo "[❇️ ] Gathering WireGuard detauls for this endpoint."
# Quickest details
QUICKEST_ENDPOINT_VERBOSE=$(grep $QUICKEST_ENDPOINT mullvad_host.list)
Q_CODE=$(echo $QUICKEST_ENDPOINT_VERBOSE | awk -F, '{print $3}')
Q_CITY=$(echo $QUICKEST_ENDPOINT_VERBOSE | awk -F, '{print $2}')
Q_COUNTRY=$(echo $QUICKEST_ENDPOINT_VERBOSE | awk -F, '{print $1}')

# Print it
echo
echo -e "${UCyan}Quickest Wireguard Endpoint${NC}"
echo -e "Country: ${GREEN}$Q_COUNTRY${NC}"
echo -e "City: ${GREEN}$Q_CITY${NC}"
echo -e "Wireguard Code: ${GREEN}$Q_CODE${NC}"
echo -e "Latency: ${GREEN}$QUICKEST_LATENCY ms ${NC}"
echo
echo -e "${UCyan}Alternatively, next best endpoints:${NC}"

for nextbest in {2..5};
 do
  #echo $nextbest
  RAW="$(sort -n -k3 host_latency.list | head -$nextbest | tail -1)"
  TTL="$(sort -n -k3 host_latency.list | head -$nextbest | tail -1 | awk '{print $3}')"
  IPV4="$(sort -n -k3 host_latency.list | head -$nextbest | tail -1 | awk '{print $1}')"
  EP="$(grep $IPV4 mullvad_host.list | awk -F, '{print $3}')"
  #echo "$EP ($IPV4 @ $TTL ms)"
  echo "$EP ($TTL ms)"
done

#connect
echo
echo -e "${UCyan}Connect now with:${NC} (for boringtun)"
echo "WG_QUICK_USERSPACE_IMPLEMENTATION=boringtun wg-quick up $WG_CONFIGS/mv-$Q_CODE.conf"
echo
echo -e "${UCyan}Or connect with:${NC} (for wireguard-go)"
echo "wg-quick up $WG_CONFIGS/mv-$Q_CODE.conf"

# clean  up
rm mullvad_host.list host_latency.list

echo -e "\nAfter connecting, run ${GREEN}./am-i-mullvad.sh${NC}"


#evil ping - all hosts at once
#for i in {1..254} ;do (ping 10.1.1.$i -c 1 -w 5  >/dev/null && echo "10.1.1.$i" &) ;done

## might be an option: fping -C 3 -q < ./iplist

# inpiration
# https://securityespresso.org/tutorials/2019/03/22/vpn-server-using-wireguard-on-ubuntu/

## what I used on o2 in italy
#WG_QUICK_USERSPACE_IMPLEMENTATION=boringtun wg-quick up ./mullvad-it1.conf
#WG_QUICK_USERSPACE_IMPLEMENTATION=boringtun wg-quick down ./mullvad-it1.conf

## TODO
# auto connect? figure out config file sorting out bullshit
#

# INSPIRATION
# https://github.com/phvr/mullvad-wg/blob/master/mullvad
# https://github.com/burghardt/easy-wg-quick
