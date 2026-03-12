# RHOAI on AWS — ROSA HCP Infrastructure as Code

> Terraform IaC for Red Hat OpenShift AI (RHOAI) on AWS using ROSA Hosted Control Plane (HCP).  
> Account: `406337554361` (iis-lab) · Region: `us-east-1` · Guide version: **v3**  
> Maintained by [IIS Tech](https://www.iistech.com/)

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
│  Platform Layer (rhoai-deploy-demo-platform-aws.sh)     │
│  ├── Aurora Serverless v2  (PostgreSQL 16.4 + pgvector) │
│  ├── EFS                   (RWX PVCs for notebooks)     │
│  ├── S3                    (data lake / model storage)  │
│  ├── ECR                   (container registry)         │
│  └── Lambda                (demo start/stop scheduler)  │
│                                                         │
│  ROSA Layer (rhoai-deploy-demo-platform-rosa.sh)        │
│  ├── ROSA HCP cluster      (OCP 4.17.50)                │
│  ├── compute pool          (c5.2xlarge, autoscale 1-4)  │
│  ├── gpu-demo pool         (g4dn.xlarge, scale 0-1)     │
│  └── IAM / IRSA roles      (S3, Bedrock, ECR, SSM)      │
└─────────────────────────────────────────────────────────┘
```

---

## Deployment Scripts

All deployment and teardown is handled by four interactive scripts in the repo root.  
Each script includes IIS Tech branding, logs all output to `logs/`, and handles
ROSA token-expiry with automatic re-authentication and retry (up to 3 attempts).

| Script | Purpose | Runtime |
|---|---|---|
| `rhoai-deploy-demo-platform-aws.sh` | Deploy AWS infra (VPC, Aurora, S3, EFS, ECR, Lambda) | ~10 min |
| `rhoai-deploy-demo-platform-rosa.sh` | Deploy ROSA cluster + IAM IRSA | ~25 min |
| `rhoai-destroy-demo-platform-rosa.sh` | Destroy ROSA cluster + roles | ~20 min |
| `rhoai-destroy-demo-platform-aws.sh` | Destroy all AWS infra | ~10 min |

> ⚠️ **Always deploy AWS before ROSA. Always destroy ROSA before AWS.**

---

## Quick Start

### Prerequisites — install once

```bash
# 1. Install tools
brew install terraform awscli rosa-cli watch pre-commit

# 2. Install oc CLI
rosa download oc && tar xzf openshift-client-mac.tar.gz
sudo mv oc kubectl /usr/local/bin/

# 3. Bootstrap remote state (run ONCE — creates S3 + DynamoDB for TF state)
./scripts/bootstrap-state.sh

# 4. Create account roles (ONCE per AWS account — never re-run)
rosa login
rosa create account-roles --hosted-cp --prefix rhoai-demo --yes

# 5. Create OIDC config (ONCE — reuse across all redeployments)
rosa create oidc-config --managed --yes --region us-east-1
rosa list oidc-config   # copy the ID into terraform.tfvars

# 6. Set environment tokens (add to ~/.zshrc for persistence)
export RHCS_TOKEN="<your-offline-token>"   # https://console.redhat.com/openshift/token
export ROSA_TOKEN="$RHCS_TOKEN"
```

### Configure terraform.tfvars

```bash
cd environments/demo
cp terraform.tfvars.example terraform.tfvars
```

Minimum required values:

```hcl
owner_tag             = "skumar@iisl.com"
budget_alert_email    = "skumar@iisl.com"
rosa_cluster_name     = "rhoai-demo"
ocp_version           = "4.17.50"          # 4.16 EOL — do not use
aurora_engine_version = "16.4"
oidc_config_id        = "2ovm1pcngkss9e6stmbirbefljiiuptk"
account_role_prefix   = "rhoai-demo"
```

---

## Deploy — Using Scripts (Recommended)

### Step 1 — Deploy AWS Platform Layer

```bash
cd ~/GitHub/rhoai-demo-iac
./rhoai-deploy-demo-platform-aws.sh
```

Installs: VPC · Aurora PostgreSQL Serverless v2 + pgvector · S3 · EFS · ECR · Lambda Scheduler · SSM · Budgets alert

**Expected output:**
```
✔  terraform apply succeeded — Apply complete! Resources: 47 added, 0 changed, 0 destroyed.
```

### Step 2 — Deploy ROSA Layer

```bash
./rhoai-deploy-demo-platform-rosa.sh
```

Installs: pgvector schema · ROSA account-roles · OIDC config · ROSA HCP cluster · worker + GPU pools · IAM IRSA roles

**Expected output:**
```
✔  terraform apply succeeded — Apply complete! Resources: 11 added, 0 changed, 0 destroyed.
✔  Cluster 'rhoai-demo' is READY 🎉
```

### Step 3 — Get cluster access

```bash
# Create cluster admin (prints one-time password — save it immediately)
rosa create admin -c rhoai-demo

# Wait 2-3 mins for OAuth to propagate, then login
oc login https://api.rhoai-demo.v7t0.p3.openshiftapps.com:443 \
  --username cluster-admin \
  --password <password-from-above>

# Verify
oc get nodes
oc get co
```

**Cluster URLs:**
```
API:     https://api.rhoai-demo.v7t0.p3.openshiftapps.com:443
Console: https://console-openshift-console.apps.rosa.rhoai-demo.v7t0.p3.openshiftapps.com
```

> If `cluster-admin` already exists: `rosa delete admin -c rhoai-demo --yes` then recreate.

---

## Deploy — Manual Terraform (Advanced)

```bash
# Refresh tokens
aws sso login --profile rhoai-demo
rosa login && export RHCS_TOKEN=$(rosa token)

# Deploy
cd environments/demo
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Post-apply (operator roles, public ingress, admin user, pgvector)
cd ../..
./scripts/post-apply.sh
```

### Redeploy after teardown

```bash
aws sso login --profile rhoai-demo
./scripts/redeploy.sh    # ~35 minutes end-to-end
```

---

## Destroy — Using Scripts (Recommended)

> ⚠️ **Always destroy ROSA before AWS** — the VPC cannot be deleted while the cluster exists.

### Step 1 — Destroy ROSA Layer

```bash
cd ~/GitHub/rhoai-demo-iac
./rhoai-destroy-demo-platform-rosa.sh
```

Destroys: IAM IRSA roles · ROSA HCP cluster + machine pools · operator IAM roles · OIDC config *(prompted)* · account roles *(prompted)*

### Step 2 — Destroy AWS Platform Layer

```bash
./rhoai-destroy-demo-platform-aws.sh
```

Destroys: Lambda · ECR · EFS · Aurora · S3 *(auto-emptied)* · IAM · VPC  
Blocks automatically if ROSA cluster still exists in the VPC.

---

## Destroy — Manual (if scripts fail)

```bash
# 1. Delete cluster
rosa delete cluster -c rhoai-demo --yes
# Wait until: rosa list clusters  returns empty

# 2. Clean ROSA roles
rosa delete operator-roles -c rhoai-demo --yes
rosa delete oidc-provider -c rhoai-demo --yes

# 3. Remove stale TF state (single-quotes required in zsh for gpu[0])
terraform state rm module.rosa.rhcs_hcp_machine_pool.workers
terraform state rm 'module.rosa.rhcs_hcp_machine_pool.gpu[0]'
terraform state rm module.rosa.rhcs_cluster_rosa_hcp.this

# 4. Refresh tokens and destroy
aws sso login --profile rhoai-demo
rosa login && export RHCS_TOKEN=$(rosa token)
terraform destroy -auto-approve

# 5. If VPC deletion fails with DependencyViolation — delete leftover SGs
aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=<VPC_ID>" \
  --query "SecurityGroups[?GroupName!='default'].[GroupId,GroupName]" --output table
aws ec2 delete-security-group --group-id <SG_ID>
terraform destroy -auto-approve   # retry
```

> ⚠️ Account roles (`rhoai-demo-HCP-ROSA-*`) and OIDC config are preserved intentionally — reuse on redeploy.

---

## RHOAI Operator Installation (Phase 3)

> ⚠️ `rosa install addon` is **not supported** on HCP clusters. Install via OperatorHub.

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

# Monitor installation (~10-15 mins)
watch -n 15 'oc get csv -n redhat-ods-operator'
```

---

## Public Ingress

ROSA HCP creates **private** ingress by default. The Terraform config already sets
`private = false` and passes all 4 subnets (public + private) to `rhcs_cluster_rosa_hcp`.
This section is for reference only if manually recreating.

```bash
# Step 1 — cluster level
rosa edit cluster -c rhoai-demo --private=false

# Step 2 — ingress level (get ID first)
rosa list ingresses -c rhoai-demo
rosa edit ingress -c rhoai-demo <INGRESS_ID> --private=false --yes

# Step 3 — verify DNS (wait 3-5 min)
dig console-openshift-console.apps.rosa.rhoai-demo.v7t0.p3.openshiftapps.com +short
# Should return public IP (not 10.x.x.x)
```

> ⚠️ `aws_subnet_ids` and `private` are **immutable** in the `rhcs` provider. If either
> needs to change the cluster must be destroyed and recreated — the deploy scripts handle this.

---

## Token Management

The `rhcs` Terraform provider uses `RHCS_TOKEN` — **separate from the `rosa` CLI session**.

```bash
# Add to ~/.zshrc for persistence
export RHCS_TOKEN="<your-offline-token>"
export ROSA_TOKEN="$RHCS_TOKEN"
```

Get your offline token: **https://console.redhat.com/openshift/token**

> ⚠️ Token expires every ~15 min during active use. Deploy scripts auto re-authenticate
> and retry up to 3 times, prompting for a fresh token and persisting it to `~/.zshrc`.

---

## Daily Operations

```bash
# Morning — scale up
rosa update machinepool -c rhoai-demo compute --min-replicas=2

# Evening — scale down (min is 1 on HCP, not 0)
rosa update machinepool -c rhoai-demo compute --min-replicas=1

# Before GPU/vLLM demo
rosa update machinepool -c rhoai-demo gpu-demo --min-replicas=1

# After GPU demo
rosa update machinepool -c rhoai-demo gpu-demo --min-replicas=0
```

### Overnight cost (workers scaled to min=1)

| Resource | Cost/hr |
|---|---|
| ROSA HCP cluster fee | $0.25 |
| 1× c5.2xlarge + ROSA fee | $0.68 |
| 2× m5.xlarge HCP infra | $0.38 |
| NAT GW + Aurora + EFS | ~$0.12 |
| **Total** | **~$1.43/hr (~$14 overnight)** |

---

## Project Structure

```
rhoai-demo-iac/
├── rhoai-deploy-demo-platform-aws.sh    # Deploy AWS infra
├── rhoai-deploy-demo-platform-rosa.sh   # Deploy ROSA cluster
├── rhoai-destroy-demo-platform-rosa.sh  # Destroy ROSA cluster
├── rhoai-destroy-demo-platform-aws.sh   # Destroy AWS infra
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
├── scripts/
│   ├── bootstrap-state.sh               # Create S3 + DynamoDB for TF state
│   ├── post-apply.sh                    # Operator roles, ingress, admin, pgvector
│   ├── teardown.sh                      # Complete teardown
│   ├── redeploy.sh                      # Full redeploy from scratch
│   └── init-pgvector.sh                 # Initialise Aurora schema
└── logs/                                # Deploy/destroy logs (gitignored)
```

---

## Known Issues (all fixed in v3)

| Error | Fix |
|---|---|
| `pip3 install` fails on Mac | `brew install pre-commit` |
| `openshift-v` prefix in version | `version = var.ocp_version` (no prefix) |
| OCP 4.16/4.15 not available | Use `4.17.50` |
| Missing `rosa_creator_arn` → 400 | Added to `properties` block |
| Cluster stuck in `waiting` | Run `rosa create operator-roles` after apply |
| `--cluster` and `--prefix` conflict | Remove `--prefix` when `--cluster` is set |
| `workers` pool name reserved | Renamed to `compute` |
| Console/API unreachable | Set `private=false` on BOTH cluster and ingress |
| Ingress ID `default` invalid | Get real ID from `rosa list ingresses` |
| DNS returns `10.x.x.x` after fix | Wait 3-5 min for NLB replacement |
| `oc` GLIBC error on AL2 bastion | Use oc `4.13.0` (not latest) |
| `rosa install addon` fails on HCP | Install RHOAI via `oc apply` Subscription |
| SSM instance profile permission denied | Use SSH key pair (IAM blocked by SSO role) |
| `zsh: no matches found: gpu[0]` | Single-quote: `'module.rosa...gpu[0]'` |
| State checksum mismatch | Use **Calculated** checksum from error, not Stored |
| VPC `DependencyViolation` on destroy | Delete leftover SGs (bastion-sg, ROSA vpce-sg) |
| `invalid_grant` mid-apply | Deploy scripts auto re-auth + retry (up to 3×) |
| `aws_subnet_ids` immutable error | Destroy + recreate cluster (rhcs provider limitation) |
| `Attribute private cannot be changed` | Destroy + recreate cluster (rhcs provider limitation) |
| `iam:ListRoleTags` 403 | SSO boundary — non-blocking, roles verified via IAM API directly |
| Duplicate variable in variables.tf | `sed -i '115,127d'` + add closing `}` |
| False success on apply with errors | Deploy scripts scan log for `│ Error:` regardless of exit code |
| `cluster-admin` already exists | `rosa delete admin -c rhoai-demo --yes` then recreate |

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

> Full provisioning guide: `rhoai-provisioning-guide-v3.docx`