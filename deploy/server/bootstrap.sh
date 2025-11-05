#!/usr/bin/env bash
set -euo pipefail

NS=remote-access

echo "[remote] Ensuring namespace: ${NS}"
kubectl get ns "${NS}" >/dev/null 2>&1 || kubectl create ns "${NS}"

echo "[remote] Creating/ensuring DB secret (idempotent)"
if ! kubectl -n ${NS} get secret guac-db-secrets >/dev/null 2>&1; then
  kubectl -n ${NS} create secret generic guac-db-secrets \
    --from-literal=POSTGRES_USER=guac \
    --from-literal=POSTGRES_PASSWORD=change_me \
    --from-literal=POSTGRES_DB=guacamole
else
  echo "[remote] DB secret exists; keeping existing values"
fi

echo "[remote] Ensuring SSH secret for sidecar (contabo-ssh)"
if ! kubectl -n ${NS} get secret contabo-ssh >/dev/null 2>&1; then
  USER_NAME=${SSH_USER:-$(id -un)}
  HOST_IP=${SSH_HOST:-$(hostname -I | awk '{print $1}')}
  KEY_DIR="$HOME/.ssh/k8s-guacd"
  KEY_PATH="$KEY_DIR/id_ed25519"
  mkdir -p "$KEY_DIR"
  if [ ! -f "$KEY_PATH" ]; then
    ssh-keygen -t ed25519 -f "$KEY_PATH" -N '' -C "guacd-sidecar" >/dev/null
  fi
  mkdir -p "$HOME/.ssh"
  touch "$HOME/.ssh/authorized_keys"
  if ! grep -q "$(cat "$KEY_PATH.pub" | cut -d' ' -f2)" "$HOME/.ssh/authorized_keys"; then
    cat "$KEY_PATH.pub" >> "$HOME/.ssh/authorized_keys"
  fi
  chmod 700 "$HOME/.ssh"; chmod 600 "$HOME/.ssh/authorized_keys"
  kubectl -n ${NS} create secret generic contabo-ssh \
    --from-literal=ssh_host="$HOST_IP" \
    --from-literal=ssh_user="$USER_NAME" \
    --from-file=id_ed25519="$KEY_PATH"
else
  echo "[remote] contabo-ssh secret exists; keeping existing key"
fi

BASE_DIR=$(cd "$(dirname "$0")/.." && pwd)

echo "[remote] Applying Postgres"
kubectl apply -f "${BASE_DIR}/k8s/postgres.yaml"

echo "[remote] Initializing DB schema (safe to re-run)"
kubectl apply -f "${BASE_DIR}/k8s/db-init-job.yaml" || true
sleep 3 || true
kubectl -n ${NS} delete job guac-db-init --ignore-not-found

echo "[remote] Applying guacd + SSH tunnel sidecar"
kubectl apply -f "${BASE_DIR}/k8s/guacd-tunnel.yaml"

echo "[remote] Applying Guacamole web"
kubectl apply -f "${BASE_DIR}/k8s/guacamole.yaml"

echo "[remote] Applying Ingress for /guacamole"
kubectl apply -f "${BASE_DIR}/k8s/ingress.yaml"

echo "[remote] Seeding/ensuring default connection 'Windows-Workstation'"
kubectl apply -f "${BASE_DIR}/k8s/bootstrap-connection-job.yaml" || true
sleep 3 || true
kubectl -n ${NS} delete job guac-bootstrap-connection --ignore-not-found

echo "[remote] Status:"
kubectl -n ${NS} get pods,svc,ingress
echo "[remote] Done."

