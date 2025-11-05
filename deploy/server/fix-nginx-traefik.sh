#!/usr/bin/env bash
set -euo pipefail

HOSTNAME=${1:-remote.alfaclouds.com}
NGINX_SITES_AVAILABLE=${NGINX_SITES_AVAILABLE:-}
NGINX_SITES_ENABLED=${NGINX_SITES_ENABLED:-}
CONF_NAME=${CONF_NAME:-${HOSTNAME}.conf}

# Detect nginx layout
if [[ -z "$NGINX_SITES_AVAILABLE" ]]; then
  if [[ -d /etc/nginx/sites-available ]]; then
    NGINX_SITES_AVAILABLE=/etc/nginx/sites-available
    NGINX_SITES_ENABLED=/etc/nginx/sites-enabled
  else
    # Fallback to conf.d only
    NGINX_SITES_AVAILABLE=/etc/nginx/conf.d
    NGINX_SITES_ENABLED=""
  fi
fi

echo "[fix] Resolving Ingress upstream for host: ${HOSTNAME}"
UPSTREAM=""
INGRESS_IP=$(kubectl -n remote-access get ingress guacamole -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
INGRESS_HOST=$(kubectl -n remote-access get ingress guacamole -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [[ -n "${INGRESS_IP}" ]]; then
  UPSTREAM="http://${INGRESS_IP}:80"
elif [[ -n "${INGRESS_HOST}" ]]; then
  UPSTREAM="http://${INGRESS_HOST}:80"
else
  # Try NGINX Ingress services first (preferred in this cluster)
  NGINX_NS=${NGINX_NS:-ingress-nginx}
  NGINX_LB_IP=$(kubectl -n "$NGINX_NS" get svc -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -n "${NGINX_LB_IP}" ]]; then
    UPSTREAM="https://${NGINX_LB_IP}:443"
  else
    NODEPORT_TLS=$(kubectl -n "$NGINX_NS" get svc -o json | jq -r '.items[] | select(.spec.type=="NodePort") | .spec.ports[] | select(.port==443) | .nodePort' | head -n1 || true)
    NODE_IP=$(kubectl get nodes -o json | jq -r '.items[0].status.addresses[] | select(.type=="InternalIP").address' || true)
    if [[ -n "${NODEPORT_TLS}" && -n "${NODE_IP}" ]]; then
      UPSTREAM="https://${NODE_IP}:${NODEPORT_TLS}"
    else
      # Fallback: Traefik (if present) HTTP 80
      TRAEFIK_LB_IP=$(kubectl -n traefik get svc -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
      if [[ -n "${TRAEFIK_LB_IP}" ]]; then
        UPSTREAM="http://${TRAEFIK_LB_IP}:80"
      else
        NODEPORT=$(kubectl -n traefik get svc -o json | jq -r '.items[] | select(.spec.ports[]? .port==80 and .spec.type=="NodePort") | .spec.ports[] | select(.port==80) | .nodePort' | head -n1 || true)
        NODE_IP=$(kubectl get nodes -o json | jq -r '.items[0].status.addresses[] | select(.type=="InternalIP").address' || true)
        if [[ -n "${NODEPORT}" && -n "${NODE_IP}" ]]; then
          UPSTREAM="http://${NODE_IP}:${NODEPORT}"
        fi
      fi
    fi
  fi
fi

if [[ -z "${UPSTREAM}" ]]; then
  echo "[fix] ERROR: Could not determine Traefik upstream. Run deploy/server/diagnose-remote.sh and ensure Traefik is reachable." >&2
  exit 1
fi
echo "[fix] Using upstream: ${UPSTREAM}"

CONF_PATH="${NGINX_SITES_AVAILABLE}/${CONF_NAME}"
BACKUP_PATH="${CONF_PATH}.bak.$(date +%Y%m%d%H%M%S)"
CERT_DIR="/etc/letsencrypt/live/${HOSTNAME}"
CERT_FULLCHAIN="${CERT_DIR}/fullchain.pem"
CERT_KEY="${CERT_DIR}/privkey.pem"

if [[ -f "${CONF_PATH}" ]]; then
  echo "[fix] Backing up existing Nginx config: ${BACKUP_PATH}"
  cp -a "${CONF_PATH}" "${BACKUP_PATH}"
fi

if [[ -f "${CERT_FULLCHAIN}" && -f "${CERT_KEY}" ]]; then
  cat >"${CONF_PATH}" <<EOF
server {
    listen 80;
    server_name ${HOSTNAME};
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${HOSTNAME};

    ssl_certificate     ${CERT_FULLCHAIN};
    ssl_certificate_key ${CERT_KEY};

    location / {
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_connect_timeout 60s;
        proxy_pass ${UPSTREAM};
    }
}
EOF
else
  echo "[fix] WARNING: TLS certs not found at ${CERT_DIR}. Creating HTTP-only proxy."
  cat >"${CONF_PATH}" <<EOF
server {
    listen 80;
    server_name ${HOSTNAME};

    location / {
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_connect_timeout 60s;
        proxy_pass ${UPSTREAM};
    }
}
EOF
fi

if [[ -n "${NGINX_SITES_ENABLED}" ]]; then
  ln -sf "${CONF_PATH}" "${NGINX_SITES_ENABLED}/${CONF_NAME}"
fi

echo "[fix] Testing Nginx configuration..."
nginx -t
echo "[fix] Reloading Nginx..."
systemctl reload nginx || service nginx reload || nginx -s reload

echo "[fix] Probing Guacamole via Nginx:"
curl -sk -I "https://${HOSTNAME}/guacamole/" || curl -sk -I "http://${HOSTNAME}/guacamole/" || true

echo "[fix] Done."
