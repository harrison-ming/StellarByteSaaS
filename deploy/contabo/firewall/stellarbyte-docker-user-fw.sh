#!/usr/bin/env bash
# Spec 5.1 / 5.4: containers on the StellarByte network (172.30.0.0/24) must never
# talk SMTP port 25 to the outside; mail goes through Stalwart submission (587).
# Idempotent. Installed as /usr/local/sbin/stellarbyte-docker-user-fw.sh and run by
# stellarbyte-docker-user-fw.service after every docker.service (re)start, because
# this host has no netfilter-persistent and Docker recreates DOCKER-USER empty on boot.
#   stellarbyte-docker-user-fw.sh apply|remove|check
set -euo pipefail
SUBNET="${STELLARBYTE_SUBNET:-172.30.0.0/24}"
RULE=(-s "$SUBNET" -p tcp --dport 25 -m comment --comment stellarbyte-no-smtp25 -j DROP)

ensure_chain() {
  # Docker normally creates DOCKER-USER; create it if we race ahead of it.
  iptables -nL DOCKER-USER >/dev/null 2>&1 || iptables -N DOCKER-USER
}

case "${1:-apply}" in
  apply)
    ensure_chain
    iptables -C DOCKER-USER "${RULE[@]}" 2>/dev/null || iptables -I DOCKER-USER 1 "${RULE[@]}"
    iptables -C DOCKER-USER "${RULE[@]}"
    echo "DOCKER-USER: drop tcp/25 from $SUBNET present"
    ;;
  remove)
    while iptables -C DOCKER-USER "${RULE[@]}" 2>/dev/null; do iptables -D DOCKER-USER "${RULE[@]}"; done
    echo "DOCKER-USER: rule removed"
    ;;
  check)
    iptables -C DOCKER-USER "${RULE[@]}" && echo "present"
    ;;
  *) echo "usage: $0 apply|remove|check" >&2; exit 2 ;;
esac
