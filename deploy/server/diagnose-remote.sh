#!/usr/bin/env bash
set -euo pipefail

HOSTNAME_TO_CHECK=${1:-remote.alfaclouds.com}

echo "[diag] Kubernetes context:"
kubectl config current-context || true

echo "[diag] Ingress objects matching host ${HOSTNAME_TO_CHECK}:"
kubectl get ingress -A -o json | jq -r \
  --arg h "$HOSTNAME_TO_CHECK" \
  '.items[] | select(any(.spec.rules[]?.host; . == $h)) | "\(.metadata.namespace)/\(.metadata.name) -> class=\(.spec.ingressClassName // "") paths=" + ((.spec.rules[] | select(.host==$h) | .http.paths[] | .path) | join(","))' || true

echo "[diag] Guacamole ingress details (if present):"
kubectl -n remote-access get ingress guacamole -o yaml || true

echo "[diag] Traefik services:"
kubectl -n traefik get svc -o wide || true

echo "[diag] Pods in remote-access:"
kubectl -n remote-access get pods -o wide || true

echo "[diag] Nginx sites available with server_name ${HOSTNAME_TO_CHECK}:"
grep -R "server_name .*${HOSTNAME_TO_CHECK}" /etc/nginx 2>/dev/null || true

echo "[diag] Trying to detect Traefik upstream (LB or NodePort)..."
UPSTREAM=""
INGRESS_IP=$(kubectl -n remote-access get ingress guacamole -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
INGRESS_HOST=$(kubectl -n remote-access get ingress guacamole -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [[ -n "${INGRESS_IP}" ]]; then
  UPSTREAM="http://${INGRESS_IP}:80"
elif [[ -n "${INGRESS_HOST}" ]]; then
  UPSTREAM="http://${INGRESS_HOST}:80"
else
  # Try Traefik LB service
  TRAEFIK_LB_IP=$(kubectl -n traefik get svc -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -n "${TRAEFIK_LB_IP}" ]]; then
    UPSTREAM="http://${TRAEFIK_LB_IP}:80"
  else
    # Fallback to NodePort: find web entrypoint on any service with port 80
    NODEPORT=$(kubectl -n traefik get svc -o json | jq -r '.items[] | select(.spec.ports[]? .port==80 and .spec.type=="NodePort") | .spec.ports[] | select(.port==80) | .nodePort' | head -n1 || true)
    NODE_IP=$(kubectl get nodes -o json | jq -r '.items[0].status.addresses[] | select(.type=="InternalIP").address' || true)
    if [[ -n "${NODEPORT}" && -n "${NODE_IP}" ]]; then
      UPSTREAM="http://${NODE_IP}:${NODEPORT}"
    fi
  fi
fi
echo "[diag] Suggested upstream: ${UPSTREAM:-<not found>}"

echo "[diag] curl test to upstream (if detected):"
if [[ -n "${UPSTREAM}" ]]; then
  curl -sk --max-time 5 -I -H "Host: ${HOSTNAME_TO_CHECK}" "${UPSTREAM}/guacamole/" || true
fi

echo "[diag] Done."

