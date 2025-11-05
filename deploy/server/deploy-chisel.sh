#!/usr/bin/env bash
set -euo pipefail

NS=remote-access
BASE_DIR=$(cd "$(dirname "$0")/.." && pwd)

echo "[chisel] Ensuring namespace ${NS} exists"
kubectl get ns ${NS} >/dev/null 2>&1 || kubectl create ns ${NS}

# Optionally refresh auth from env
if [[ -n "${CHISEL_USER:-}" && -n "${CHISEL_PASS:-}" ]]; then
  echo "[chisel] Updating chisel auth secret from env"
  kubectl -n ${NS} delete secret chisel-auth >/dev/null 2>&1 || true
  kubectl -n ${NS} create secret generic chisel-auth \
    --from-literal=username="${CHISEL_USER}" \
    --from-literal=password="${CHISEL_PASS}"
fi

echo "[chisel] Applying k8s manifests"
kubectl apply -f "${BASE_DIR}/k8s/chisel.yaml"

echo "[chisel] Waiting for chisel-server rollout"
kubectl -n ${NS} rollout status deploy/chisel-server --timeout=120s

echo "[chisel] Verifying services and ingress"
kubectl -n ${NS} get svc chisel-server chisel-rdp
kubectl -n ${NS} get ingress chisel-server -o wide

echo "[chisel] Optionally re-bootstrap Guacamole connection to use chisel-rdp"
kubectl apply -f "${BASE_DIR}/k8s/bootstrap-connection-job.yaml"
sleep 3 || true
kubectl -n ${NS} logs job/guac-bootstrap-connection --tail=100 --all-containers || true

echo "[chisel] Done. Client command (Windows PowerShell):"
cat <<'CMD'
$dir = 'C:\ProgramData\chisel'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
Invoke-WebRequest -UseBasicParsing -Uri https://github.com/jpillora/chisel/releases/download/v1.9.1/chisel_1.9.1_windows_amd64.gz -OutFile $dir\chisel.gz
certutil -f -decode $dir\chisel.gz $dir\chisel.exe | Out-Null
& "$dir\chisel.exe" client --keepalive 30s --auth guac:change_me_chisel wss://remote.alfaclouds.com/chisel R:13389:127.0.0.1:3389
CMD

