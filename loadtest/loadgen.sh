#!/usr/bin/env bash
# Creates and deletes the load generator: a throwaway VPC, a firewall rule admitting SSH from IAP only, and one VM
# with k6. Everything it creates is named loadgen, and `down` deletes all of it, which leaves gke-vpc as the project's
# only network. The VM has no service account, because it needs no Google Cloud identity to send HTTPS requests.
#
# Usage: loadtest/loadgen.sh up | copy | ssh | pull | down
set -euo pipefail

PROJECT="${PROJECT:-example-security-lab}"
REGION="${REGION:-europe-west4}"
ZONE="${ZONE:-europe-west4-a}"
MACHINE_TYPE="${MACHINE_TYPE:-e2-standard-2}"
K6_VERSION="${K6_VERSION:-v2.2.0}"
SUBNET_RANGE="${SUBNET_RANGE:-10.99.0.0/24}"

NAME=loadgen
# The fixed range IAP TCP forwarding connects from. Nothing else can reach port 22.
IAP_RANGE=35.235.240.0/20
HERE="$(cd "$(dirname "$0")" && pwd)"

gc() { gcloud --project "$PROJECT" --quiet "$@"; }

# Runs as root on first boot. The checksum is verified before the binary is unpacked.
startup_script() {
  cat <<EOF
#!/bin/bash
set -euo pipefail
cd /tmp
base="https://github.com/grafana/k6/releases/download/${K6_VERSION}"
curl -fsSLO "\$base/k6-${K6_VERSION}-linux-amd64.tar.gz"
curl -fsSLO "\$base/k6-${K6_VERSION}-checksums.txt"
grep " k6-${K6_VERSION}-linux-amd64.tar.gz\$" "k6-${K6_VERSION}-checksums.txt" | sha256sum -c -
tar -xzf "k6-${K6_VERSION}-linux-amd64.tar.gz" --strip-components=1 -C /usr/local/bin "k6-${K6_VERSION}-linux-amd64/k6"
# An IAP tunnel can drop mid-run, and a run started inside tmux survives it.
apt-get update -qq && apt-get install -y -qq tmux
# Each VU holds its own connection, and the default of 1024 open files caps a step well before the VM's CPU does.
echo '* soft nofile 65536' > /etc/security/limits.d/k6.conf
echo '* hard nofile 65536' >> /etc/security/limits.d/k6.conf
touch /var/lib/k6-ready
EOF
}

up() {
  # IAP TCP forwarding carries the SSH session. Enabling it is idempotent and costs nothing.
  gc services enable iap.googleapis.com

  gc compute networks create "$NAME" --subnet-mode=custom
  gc compute networks subnets create "$NAME" --network="$NAME" --region="$REGION" --range="$SUBNET_RANGE"
  gc compute firewall-rules create "$NAME-allow-iap-ssh" \
    --network="$NAME" --direction=INGRESS --action=ALLOW --rules=tcp:22 --source-ranges="$IAP_RANGE"

  gc compute instances create "$NAME" \
    --zone="$ZONE" \
    --machine-type="$MACHINE_TYPE" \
    --subnet="$NAME" \
    --image-family=debian-13 \
    --image-project=debian-cloud \
    --shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring \
    --no-service-account --no-scopes \
    --metadata=enable-oslogin=TRUE \
    --metadata-from-file=startup-script=<(startup_script)

  echo "Waiting for k6 to install."
  until gc compute ssh "$NAME" --zone="$ZONE" --tunnel-through-iap --command='test -f /var/lib/k6-ready' 2>/dev/null; do
    sleep 10
  done
  gc compute ssh "$NAME" --zone="$ZONE" --tunnel-through-iap --command='k6 version && nproc && free -h'
}

copy() {
  gc compute ssh "$NAME" --zone="$ZONE" --tunnel-through-iap --command='mkdir -p ~/loadtest/results'
  gc compute scp --zone="$ZONE" --tunnel-through-iap "$HERE"/*.js "$NAME":~/loadtest/
}

ssh_vm() {
  gc compute ssh "$NAME" --zone="$ZONE" --tunnel-through-iap "$@"
}

pull() {
  mkdir -p "$HERE/results"
  gc compute scp --zone="$ZONE" --tunnel-through-iap --recurse "$NAME":~/loadtest/results/* "$HERE/results/"
}

# Deletes in dependency order and carries on past anything already gone, then lists what is left.
down() {
  gc compute instances delete "$NAME" --zone="$ZONE" || true
  gc compute firewall-rules delete "$NAME-allow-iap-ssh" || true
  gc compute networks subnets delete "$NAME" --region="$REGION" || true
  gc compute networks delete "$NAME" || true
  echo "Networks remaining:"
  gc compute networks list --format='value(name)'
}

case "${1:-}" in
  up) up ;;
  copy) copy ;;
  ssh) shift; ssh_vm "$@" ;;
  pull) pull ;;
  down) down ;;
  *) echo "Usage: $0 up | copy | ssh | pull | down" >&2; exit 2 ;;
esac
