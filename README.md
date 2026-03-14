# RHOAI on AWS — ROSA HCP Infrastructure as Code

> Terraform IaC for Red Hat OpenShift AI (RHOAI) on AWS using ROSA Hosted Control Plane (HCP).  
> Account: `406337554361` (iis-lab) · Region: `us-east-1`  
> Maintained by [IIS Tech](https://www.iistech.com/)

---

## Purpose

This repo provisions and manages a complete RHOAI demo environment on AWS:

- **AWS Platform Layer** — VPC, Aurora PostgreSQL Serverless v2 + pgvector, S3, EFS, ECR, Lambda cost scheduler, SSM, Budgets alert
- **ROSA Layer** — ROSA HCP cluster (OCP 4.17), compute + GPU machine pools, IAM IRSA roles for S3 / Bedrock / Aurora / ECR access
- **Operational scripts** — provision, teardown, daily stop/start, GPU on/off, resource inventory

Everything is driven by a single master script: `./scripts/AI-demo-stack-create.sh`

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  AWS Account 406337554361  ·  us-east-1                 │
│                                                         │
│  VPC 10.0.0.0/16                                        │
│  ├── Public Subnets  (NAT GW, NLB ingress)              │
│  └── Private Subnets (ROSA nodes, Aurora, EFS)          │
│                                                         │
│  AWS Platform Layer                                     │
│  ├── Aurora Serverless v2  (PostgreSQL 16.4 + pgvector) │
│  ├── EFS                   (RWX PVCs for notebooks)     │
│  ├── S3                    (data lake / model storage)  │
│  ├── ECR                   (container registry)         │
│  └── Lambda                (demo start/stop scheduler)  │
│                                                         │
│  ROSA Layer                                             │
│  ├── ROSA HCP cluster      (OCP 4.17.50)                │
│  ├── compute pool          (c5.2xlarge, autoscale 1-4)  │
│  ├── gpu-demo pool         (g4dn.xlarge, scale 0-1)     │
│  └── IAM / IRSA roles      (S3, Bedrock, ECR, SSM)      │
└─────────────────────────────────────────────────────────┘
```

---

## Quick Start

### 1. Prerequisites — install once

```bash
brew install awscli terraform rosa-cli openshift-cli jq watch

# Bootstrap Terraform remote state (once per AWS account)
./scripts/bootstrap-state.sh

# Create ROSA account roles (once per AWS account)
rosa login
rosa create account-roles --hosted-cp --prefix rhoai-demo --yes

# Create OIDC config (once — reuse across all redeployments)
rosa create oidc-config --managed --yes --region us-east-1
rosa list oidc-config   # copy the ID into environments/demo/terraform.tfvars
```

### 2. Configure terraform.tfvars

```bash
cd environments/demo
cp terraform.tfvars.example terraform.tfvars
```

Minimum required values:

```hcl
owner_tag             = "skumar@iistech.com"
budget_alert_email    = "skumar@iistech.com"
rosa_cluster_name     = "rhoai-demo"
ocp_version           = "4.17.50"
aurora_engine_version = "16.4"
oidc_config_id        = "2ovm1pcngkss9e6stmbirbefljiiuptk"
account_role_prefix   = "rhoai-demo"
```

### 3. Deploy

```bash
cd ~/GitHub/rhoai-demo-iac
./scripts/AI-demo-stack-create.sh
```

The script handles everything interactively:
- AWS SSO authentication
- Red Hat SSO login (browser-based — offline token login is deprecated)
- `terraform init` → `plan` → `apply`
- Token-expiry retry (up to 3 attempts, re-authenticates via SSO)
- Cluster readiness polling
- Post-deploy resource summary

### 4. Get cluster access

```bash
# Create cluster admin (prints one-time password — save it)
rosa create admin -c rhoai-demo

# Wait 2-3 min for OAuth to propagate, then login
oc login https://api.rhoai-demo.v7t0.p3.openshiftapps.com:443 \
  --username cluster-admin --password <password-from-above>

oc get nodes
oc get co
```

---

## Authentication

| Auth | Method |
|---|---|
| AWS | `aws sso login --profile rhoai-demo` |
| Red Hat / OCM | `rosa login` — browser-based Red Hat SSO |
| Terraform `rhcs` provider | `RHCS_TOKEN=$(rosa token)` — scripts export this automatically |

> Offline token login (`rosa login --token=...`) is **deprecated** by Red Hat.  
> Scripts use `rosa login` (SSO) and obtain `RHCS_TOKEN` automatically via `rosa token` for the Terraform provider.

---

## Scripts

See [`scripts/README.md`](scripts/README.md) for full reference. Summary:

| Script | Purpose | Duration |
|---|---|---|
| `scripts/AI-demo-stack-create.sh` | Deploy full stack (AWS + ROSA + IAM) | ~30-35 min |
| `scripts/AI-demo-stack-destroy.sh` | Destroy full stack | ~20-25 min |
| `scripts/stop-demo.sh` | Scale workers to 0 overnight | ~2-3 min |
| `scripts/start-demo.sh` | Scale workers back up | ~5-8 min |
| `scripts/gpu-on.sh` | Scale GPU pool to 1 for vLLM demos | ~1 min |
| `scripts/gpu-off.sh` | Scale GPU pool to 0 | ~1 min |
| `scripts/show-resources.sh` | Resource inventory (AWS + OCP) | instant |
| `scripts/bootstrap-state.sh` | Create S3 + DynamoDB for TF state | ~1 min |
| `scripts/redeploy.sh` | Full teardown + provision | ~55 min |

---

## Daily Operations

```bash
# Evening — scale down
./scripts/stop-demo.sh        # ~$0.73/hr overnight

# Morning — scale up
./scripts/start-demo.sh       # ~$2/hr running

# Before GPU / vLLM demo
./scripts/gpu-on.sh

# After GPU demo
./scripts/gpu-off.sh
```

---

## Cost

| State | Cost/hr | Cost/day |
|---|---|---|
| Running (2 workers) | ~$2.00 | ~$48 |
| Stopped (0 workers) | ~$0.73 | ~$17.50 |
| Destroyed | $0.00 | $0.00 |

Overnight saving with `stop-demo.sh`: ~$30/day.

---

## Teardown

```bash
./scripts/AI-demo-stack-destroy.sh
# Type: destroy-demo
```

Destroys: ROSA cluster · IAM roles · Lambda · ECR · EFS · Aurora · S3 · VPC  
Prompts whether to also delete OIDC config and account roles (keep them — they're reusable).

---

## RHOAI Operator Installation

> `rosa install addon` is not supported on HCP clusters. Install via OperatorHub.

```bash
oc new-project redhat-ods-operator

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec:
  channel: stable
  installPlanApproval: Automatic
  name: rhods-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

watch -n 15 'oc get csv -n redhat-ods-operator'
```

---

## Project Structure

```
rhoai-demo-iac/
├── scripts/
│   ├── README.md                        # Scripts reference (this file's companion)
│   ├── AI-demo-stack-create.sh              # Master deployment script ← start here
│   ├── AI-demo-stack-destroy.sh             # Full stack destruction
│   ├── stop-demo.sh                     # Scale down overnight
│   ├── start-demo.sh                    # Scale up in morning
│   ├── gpu-on.sh / gpu-off.sh           # GPU pool management
│   ├── show-resources.sh                # Resource inventory
│   ├── bootstrap-state.sh               # TF remote state setup (once)
│   ├── redeploy.sh                      # Teardown + provision
│   └── init-pgvector.sh                 # Aurora pgvector schema init
├── environments/
│   └── demo/
│       ├── main.tf                      # Module wiring
│       ├── variables.tf                 # All input variables
│       ├── outputs.tf                   # Cluster URLs, IDs, ARNs
│       ├── backend.tf                   # S3 remote state config
│       ├── versions.tf                  # Provider version constraints
│       └── terraform.tfvars.example
├── modules/
│   ├── vpc/                             # VPC, subnets, NAT GW, route tables
│   ├── rosa-hcp/                        # ROSA HCP cluster + machine pools
│   ├── iam-irsa/                        # IAM roles for service accounts
│   ├── aurora-serverless/               # Aurora Serverless v2 + pgvector
│   ├── s3-data-lake/                    # S3 bucket + lifecycle policies
│   ├── efs-storage/                     # EFS + access point
│   ├── ecr-repos/                       # ECR repositories
│   └── lambda-triggers/                 # Demo scheduler + budget alert
└── logs/                                # Deploy/destroy logs (gitignored)
```

---

## Deployed Resources

| Resource | Value |
|---|---|
| VPC | `vpc-062ba0ee77948a2e9` |
| Private Subnets | `subnet-0e9770b6c7980a80b`, `subnet-033cae2d4a276cbf0` |
| Public Subnets | `subnet-0d42f49bc74431ea4`, `subnet-0ba5477fa5ad2ea4d` |
| S3 Bucket | `rhoai-demo-demo-406337554361` |
| Aurora | `rhoai-demo-demo-db.cluster-cidweltunfq6.us-east-1.rds.amazonaws.com` |
| EFS | `fs-0b2595228ea531516` |
| Lambda Scheduler | `rhoai-demo-demo-demo-scheduler` |
| TF State | `rhoai-demo-tfstate-406337554361` / `rhoai-demo-tflock` |
| OIDC Config | `2ovm1pcngkss9e6stmbirbefljiiuptk` |
| ROSA API | `https://api.rhoai-demo.v7t0.p3.openshiftapps.com:443` |
| ROSA Console | `https://console-openshift-console.apps.rosa.rhoai-demo.v7t0.p3.openshiftapps.com` |

---

## Providers

| Provider | Version |
|---|---|
| `hashicorp/aws` | `~> 5.50` |
| `terraform-redhat/rhcs` | `~> 1.7` |

---

## Known Issues & Fixes

| Error | Fix |
|---|---|
| `openshift-v` prefix in version | `version = var.ocp_version` (no prefix) |
| OCP 4.16/4.15 not available | Use `4.17.50` |
| Cluster stuck in `waiting` | Run `rosa create operator-roles` after apply |
| Console/API unreachable | Set `private=false` on BOTH cluster and ingress |
| DNS returns `10.x.x.x` after fix | Wait 3-5 min for NLB replacement |
| `rosa install addon` fails on HCP | Install RHOAI via `oc apply` Subscription |
| `zsh: no matches found: gpu[0]` | Single-quote: `'module.rosa...gpu[0]'` |
| State checksum mismatch | Use **Calculated** checksum from error, not Stored |
| VPC `DependencyViolation` on destroy | Delete leftover SGs (bastion-sg, ROSA vpce-sg) |
| `invalid_grant` mid-apply | `AI-demo-stack-create.sh` auto re-authenticates via SSO + retries (up to 3×) |
| `aws_subnet_ids` immutable error | Destroy + recreate cluster (rhcs provider limitation) |
| `Attribute private cannot be changed` | Destroy + recreate cluster (rhcs provider limitation) |
| `iam:ListRoleTags` 403 | SSO boundary — non-blocking |
| False success on apply with errors | `AI-demo-stack-create.sh` scans log for `│ Error:` regardless of exit code |
| `cluster-admin` already exists | `rosa delete admin -c rhoai-demo --yes` then recreate |
| Offline token login deprecated | Use `rosa login` (SSO) — scripts handle this automatically |
