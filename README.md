Remote Access via Guacamole + SSH/HTTPS Tunnels

Overview
- Kubernetes manifests and scripts to expose a Windows workstation to a remote Guacamole instance without VPN.
- Browser access (Guacamole) and native RDP path via SSH reverse tunnel; HTTPS-only fallback via Chisel.

Key Paths
- K8s manifests: deploy/k8s/
- Server scripts: deploy/server/
- Windows scripts: deploy/windows/

Primary Flow (SSH reverse RDP)
1) On server (k8s): apply manifests per deploy/README.md.
2) On Windows workstation: run deploy/windows/run-ssh-reverse.ps1 (optionally -Persist) to create a reverse SSH tunnel:
   - Exposes server loopback 127.0.0.1:13389 -> workstation localhost:3389.
3) Guacamole connects to 127.0.0.1:13389 through a sidecar forward in the cluster.

HTTPS-only Fallback (Chisel)
- If outbound SSH is blocked, use deploy/windows/run-remote-access.ps1 to set up an HTTPS/WebSocket reverse tunnel to the chisel server published at /chisel.

Security Notes
- No public RDP is opened. All access rides over SSH or HTTPS.
- Change default secrets in deploy/k8s/secrets.example.yaml and deploy/k8s/chisel.yaml before production use.

Quick Start
- See deploy/README.md for step-by-step server and client instructions.

Operations Checklist
- Server (Kubernetes)
  - kubectl: apply namespace, secrets, Postgres, guacd+tunnel, guacamole, ingress per deploy/README.md
  - Root redirect (optional) for / -> /guacamole
  - Verify ingresses route via existing nginx ingressclass
- Workstation (Windows)
  - Enable RDP: deploy/windows/enable-rdp.ps1
  - Start reverse SSH tunnel (preferred): deploy/windows/run-ssh-reverse.ps1 [-Persist]
  - If SSH is blocked, start HTTPS tunnel: deploy/windows/run-remote-access.ps1 [-Persist]
  - If auth issues, temporarily relax RDP: deploy/windows/relax-rdp.ps1
  - (Optional) Create a local RDP user for testing: deploy/windows/create-local-rdp-user.ps1
- Guacamole
  - URL: https://remote.alfaclouds.com/guacamole/
  - Default admin: guacadmin / guacadmin (change on first login)
  - Connection: Windows-Workstation points to 127.0.0.1:13389 (via reverse tunnel)
- Hardening follow-up
  - Re-enable NLA on the workstation; in Guacamole, set security to nla
  - Rotate DB and SSH/chisel secrets; restrict egress via NetworkPolicy
  - Optionally store per-connection credentials in Guacamole

