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

