Remote access via Apache Guacamole on Kubernetes (Traefik), with an SSH-only path to the Windows workstation. No public RDP ports are exposed.

Components
- Kubernetes namespace `remote-access`.
- Postgres for Guacamole auth (Deployment + PVC).
- Guacamole server (web) and guacd (RDP proxy) Deployments.
- Sidecar `autossh` in the guacd pod maintaining a local tunnel to `contabo_de`.
- Traefik Ingress for `remote.alfaclouds.com` (HTTP, optional TLS via cert-manager).
- Windows scripts to enable RDP and run a persistent reverse SSH tunnel to `contabo_de`.

Network flow
- Workstation → reverse SSH → `contabo_de` binds `127.0.0.1:13389` →
- guacd pod sidecar (ssh loop) → local forward `localhost:13389` → `contabo_de:127.0.0.1:13389` → workstation:3389
- Guacamole connects RDP to `localhost:13389` inside the guacd pod (no public exposure).

Prerequisites
- Traefik IngressController installed (ingressClassName: `traefik`).
- Cluster can egress TCP/22 to `contabo_de`.
- You will provide an SSH key (new or existing) authorized on `contabo_de` for a non-root user.

Windows workstation steps
1) Enable RDP and firewall (run as Administrator):
   - `powershell -ExecutionPolicy Bypass -File deploy/windows/enable-rdp.ps1`
2) Install a persistent reverse tunnel to `contabo_de` (binds only on localhost of `contabo_de`):
   - Edit parameters as needed, then run:
   - `powershell -ExecutionPolicy Bypass -File deploy/windows/install-tunnel-task.ps1 -ContaboHost <host> -ContaboUser <user> -RemotePort 13389 [-KeyPath <path-to-privkey>]`
   - This creates a scheduled task that keeps: `ssh -N -R 127.0.0.1:13389:localhost:3389 <user>@<host>` alive.

Kubernetes steps
1) Create namespace:
   - `kubectl apply -f deploy/k8s/namespace.yaml`
2) Create secrets (edit file first):
   - `deploy/k8s/secrets.example.yaml` → fill in DB creds, SSH host/user, and paste private key (id_ed25519). Then:
   - `kubectl apply -f deploy/k8s/secrets.example.yaml`
3) Storage + Postgres:
   - `kubectl apply -f deploy/k8s/postgres.yaml`
4) Initialize DB schema (runs once; safe to re-run):
   - `kubectl apply -f deploy/k8s/db-init-job.yaml`
   - Wait for job completion: `kubectl -n remote-access logs job/guac-db-init --all-containers` then `kubectl -n remote-access delete job guac-db-init`
5) Guacd + SSH tunnel sidecar:
   - `kubectl apply -f deploy/k8s/guacd-tunnel.yaml`
6) Guacamole web app:
   - `kubectl apply -f deploy/k8s/guacamole.yaml`
7) Traefik Ingress:
   - `kubectl apply -f deploy/k8s/ingress.yaml`

TLS (optional)
- If cert-manager is installed, set the annotation in `ingress.yaml`:
  `cert-manager.io/cluster-issuer: letsencrypt` and ensure the `tls` section’s secretName is acceptable.
- Otherwise, remove `tls:` from the Ingress to serve HTTP only (behind your own TLS termination if any).

Guacamole login
- Default DB-based auth with initial admin `guacadmin / guacadmin` (change on first login). After DB init, open `https://remote.alfaclouds.com/guacamole/` (or HTTP if TLS disabled), then create a connection:
  - Protocol: RDP
  - Hostname: `localhost`
  - Port: `13389`
  - Security: NLA as appropriate for your Windows version

Native RDP (optional)
- Not exposed publicly by design. If you need native RDP from a different location, create a temporary SSH local forward from any machine that can reach `contabo_de`:
  - `ssh -L 13389:127.0.0.1:13389 <user>@<contabo_host>`
  - Then RDP to `localhost:13389`.

Notes
- No public ports are opened. All traffic rides over SSH.
- If Traefik requires a different ingressClass, change `ingressClassName` in `ingress.yaml`.
- Replace image tags as needed for pinned versions.
