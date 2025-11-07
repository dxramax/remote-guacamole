# Setting RDP Credentials for Auto-Login

This job configures automatic Windows login credentials for a Guacamole RDP connection.

## Usage

1. Edit `set-rdp-credentials-job.yaml` and update these environment variables:
   ```yaml
   - name: RDP_USERNAME
     value: "YourDomain\\username"  # or just "username" for local accounts
   - name: RDP_PASSWORD
     value: "YourPassword"
   - name: CONNECTION_NAME
     value: "Windows-Workstation"  # The connection name in Guacamole
   ```

2. Apply the job:
   ```bash
   kubectl apply -f deploy/k8s/set-rdp-credentials-job.yaml
   ```

3. Check the job status and logs:
   ```bash
   kubectl -n remote-access get job set-rdp-credentials
   kubectl -n remote-access logs job/set-rdp-credentials
   ```

4. Clean up the job after completion:
   ```bash
   kubectl -n remote-access delete job set-rdp-credentials
   ```

## Security Note

**IMPORTANT:** This file contains plaintext credentials. Options for better security:

1. **Use Kubernetes Secrets** (recommended):
   - Create a secret with credentials
   - Reference it in the job using `secretKeyRef`

2. **Don't commit credentials**:
   - Keep credentials in a separate file (e.g., `set-rdp-credentials-local.yaml`)
   - Add it to `.gitignore`

3. **Use Guacamole UI**:
   - Set credentials through the web interface instead
   - Navigate to: Settings → Connections → Edit connection → Parameters

## Current Configuration

- **Username:** `Atheeb\a.alakkad`
- **Connection:** Windows-Workstation
- **Applied:** 2025-11-07

After applying, users will automatically login to Windows when connecting through Guacamole.
