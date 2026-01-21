#!/usr/bin/env bash
set -euo pipefail

NS=remote-access
POSTGRES_USER=${POSTGRES_USER:-guac}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-change_me}
POSTGRES_DB=${POSTGRES_DB:-guacamole}
SSH_HOST=${SSH_HOST:-}
SSH_USER=${SSH_USER:-}
SSH_KEY_PATH=${SSH_KEY_PATH:-}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found" >&2; exit 1
fi

echo "[deploy] Creating namespace ${NS} (if not exists)"
kubectl get ns ${NS} >/dev/null 2>&1 || kubectl create ns ${NS}

echo "[deploy] Creating DB secret guac-db-secrets"
kubectl -n ${NS} delete secret guac-db-secrets >/dev/null 2>&1 || true
kubectl -n ${NS} create secret generic guac-db-secrets \
  --from-literal=POSTGRES_USER="${POSTGRES_USER}" \
  --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  --from-literal=POSTGRES_DB="${POSTGRES_DB}"

if [[ -z "${SSH_HOST}" || -z "${SSH_USER}" || -z "${SSH_KEY_PATH}" ]]; then
  echo "[deploy] INFO: Skipping contabo-ssh secret (set SSH_HOST, SSH_USER, SSH_KEY_PATH env vars to create it)"
else
  echo "[deploy] Creating SSH secret contabo-ssh"
  kubectl -n ${NS} delete secret contabo-ssh >/dev/null 2>&1 || true
  kubectl -n ${NS} create secret generic contabo-ssh \
    --from-literal=ssh_host="${SSH_HOST}" \
    --from-literal=ssh_user="${SSH_USER}" \
    --from-file=id_ed25519="${SSH_KEY_PATH}"
fi

BASE_DIR=$(cd "$(dirname "$0")/.." && pwd)

echo "[deploy] Applying Postgres"
kubectl apply -f "${BASE_DIR}/k8s/postgres.yaml"

echo "[deploy] Initializing DB schema job"
kubectl apply -f "${BASE_DIR}/k8s/db-init-job.yaml"
echo "[deploy] Waiting a bit for init job logs..."
sleep 5 || true
kubectl -n ${NS} logs job/guac-db-init --all-containers --tail=100 || true
echo "[deploy] Cleaning init job (safe to ignore if not finished)"
kubectl -n ${NS} delete job guac-db-init || true

echo "[deploy] Applying guacd + tunnel"
kubectl apply -f "${BASE_DIR}/k8s/guacd-tunnel.yaml"

echo "[deploy] Applying guacamole web"
kubectl apply -f "${BASE_DIR}/k8s/guacamole.yaml"

echo "[deploy] Applying ingress (guacamole path /guacamole)"
kubectl apply -f "${BASE_DIR}/k8s/ingress.yaml"

echo "[deploy] Applying root redirect ingress/middleware"
kubectl apply -f "${BASE_DIR}/k8s/redirect-root.yaml"

echo "[deploy] Done. Verify pods and ingress:"
kubectl -n ${NS} get pods,svc,ingress

