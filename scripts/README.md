# Scripts Reference

Operational scripts for the RHOAI Demo IaC on AWS (ROSA HCP).  
All scripts are run from the **repo root**, log to `logs/`, and handle AWS SSO + Red Hat SSO automatically.

---

## Prerequisites — install once

```bash
brew install awscli terraform rosa-cli openshift-cli jq watch

# Bootstrap Terraform remote state (once per AWS account)
./scripts/bootstrap-state.sh

# Create ROSA account roles (once per AWS account — never re-run)
rosa login
rosa create account-roles --hosted-cp --prefix rhoai-demo --yes

# Create OIDC config (once — reuse across all redeployments)
rosa create oidc-config --managed --yes --region us-east-1
rosa list oidc-config   # copy the ID into environments/demo/terraform.tfvars
```

> Red Hat offline token login is **deprecated**. All scripts use `rosa login` (Red Hat SSO browser flow).  
> The `RHCS_TOKEN` env var is only needed by the Terraform `rhcs` provider — scripts obtain it automatically via `rosa token` after SSO login.

---

## Lifecycle Scripts

### AI-demo-stack-create.sh — Full stack deployment (~30-35 min)

Deploys everything: VPC · Aurora · S3 · EFS · ECR · Lambda · ROSA HCP cluster · IAM IRSA roles.

```bash
./scripts/AI-demo-stack-create.sh
```

What it does:
- Checks all required tools (`aws`, `terraform`, `rosa`, `oc`, `git`, `jq`)
- AWS SSO authentication (checks session, triggers `aws sso login` only if expired)
- Red Hat SSO login via `rosa login` (browser-based — no token copy/paste)
- Automatically exports `RHCS_TOKEN` from active rosa session for the Terraform `rhcs` provider
- Validates `terraform.tfvars` key-by-key
- `terraform init` → `plan` → `apply` with separate timestamped logs per phase
- Token-expiry retry loop (up to 3 attempts) — re-authenticates via SSO and retries apply
- False-success guard — scans apply log for `│ Error:` even when exit code is 0
- Polls cluster state every 60s until `ready` (max 35 min)
- Prints resource URLs and next steps on completion

---

### AI-demo-stack-destroy.sh — Full stack destruction (~20-25 min)

Destroys everything in the correct order. Requires typing `destroy-demo` to confirm.

```bash
./scripts/AI-demo-stack-destroy.sh
```

Destroys: IAM IRSA roles · ROSA cluster + machine pools · operator roles · Lambda · ECR · EFS · Aurora · S3 (auto-emptied) · VPC  
Prompts whether to also delete OIDC config and account roles (recommended: keep for redeployment).

---

## Daily Operations

### stop-demo.sh — Scale down overnight (~2-3 min)

Scales workers to 0 to save costs. Data (Aurora, EFS, S3) is preserved.

```bash
./scripts/stop-demo.sh
```

Cost while stopped: ~$0.73/hr (~$17.50/day)

### start-demo.sh — Scale up in the morning (~5-8 min)

Re-enables autoscaling and scales compute pool back to min=2.

```bash
./scripts/start-demo.sh
```

### gpu-on.sh / gpu-off.sh — GPU pool for vLLM demos

```bash
./scripts/gpu-on.sh    # scale gpu-demo pool to 1 (g4dn.xlarge)
./scripts/gpu-off.sh   # scale gpu-demo pool to 0
```

---

## Utility Scripts

### show-resources.sh — Resource inventory

Displays all deployed AWS and OpenShift resources in a colour-coded table.

```bash
./scripts/show-resources.sh
```

### bootstrap-state.sh — Terraform remote state (run once)

Creates the S3 bucket and DynamoDB table used for Terraform state locking.

```bash
./scripts/bootstrap-state.sh
```

### import-all-resources.sh — Import existing resources into state

Use when resources exist in AWS but are missing from Terraform state (e.g. after a partial apply).

```bash
./scripts/import-all-resources.sh
```

### redeploy.sh — Full teardown + provision in one command

```bash
./scripts/redeploy.sh   # ~55 minutes end-to-end
```

### init-pgvector.sh — Initialise Aurora pgvector schema

Run once after Aurora is provisioned. Requires network access to Aurora (run from within VPC or via bastion).

```bash
./scripts/init-pgvector.sh
```

---

## Authentication Reference

| Auth | Method | Notes |
|---|---|---|
| AWS | `aws sso login --profile rhoai-demo` | Scripts check session first, only re-login if expired |
| Red Hat / OCM | `rosa login` (browser SSO) | Offline token login is deprecated by Red Hat |
| Terraform `rhcs` provider | `RHCS_TOKEN=$(rosa token)` | Scripts export this automatically after SSO login |

---

## Cost Summary

| State | Cost/hr | Cost/day |
|---|---|---|
| Running (2 workers) | ~$2.00 | ~$48 |
| Stopped (0 workers) | ~$0.73 | ~$17.50 |
| Destroyed | $0.00 | $0.00 |

---

## Logs

All scripts write timestamped logs to `logs/` (gitignored).

```bash
ls -ltr logs/          # list recent runs
tail -f logs/provision_*.log   # follow active run
```
