# RHOAI on AWS — ROSA HCP Infrastructure as Code

> Terraform IaC for Red Hat OpenShift AI (RHOAI) on AWS using ROSA Hosted Control Plane (HCP).  
> Account: `406337554361` (iis-lab) · Region: `us-east-1` · Guide version: **v3**

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  AWS Account 406337554361  ·  us-east-1                 │
│                                                         │
│  VPC 10.0.0.0/16                                        │
│  ├── Public Subnets  (NAT GW, bastion)                  │
│  └── Private Subnets (ROSA nodes, Aurora, EFS)          │
│                                                         │
│  Phase 1 — Platform                                     │
│  ├── Aurora Serverless v2  (PostgreSQL 16.4 + pgvector) │
│  ├── EFS                   (RWX PVCs for notebooks)     │
│  ├── S3                    (data lake / model storage)  │
│  ├── ECR                   (container registry)         │
│  └── Lambda                (demo start/stop scheduler)  │
│                                                         │
│  Phase 2 — Cluster                                      │
│  ├── ROSA HCP cluster      (OCP 4.17.50)                │
│  ├── compute pool          (c5.2xlarge, autoscale 1-4)  │
│  ├── gpu-demo pool         (g4dn.xlarge, scale 0-1)     │
│  └── IAM / IRSA roles      (S3, Bedrock, ECR, SSM)      │
└─────────────────────────────────────────────────────────┘
```

---

## Quick Start

### First time ever (one-time setup)

```bash
# 1. Install tools
brew install terraform awscli rosa-cli watch pre-commit

# 2. Install oc CLI
rosa download oc && tar xzf openshift-client-mac.tar.gz
sudo mv oc kubectl /usr/local/bin/

# 3. Bootstrap remote state
./scripts/bootstrap-state.sh

# 4. Create account roles (ONCE per AWS account — never re-run)
rosa login
rosa create account-roles --hosted-cp --prefix rhoai-demo --yes

# 5. Create OIDC config (ONCE — reuse across all redeployments)
rosa create oidc-config --managed --yes --region us-east-1
rosa list oidc-config   # copy the ID into terraform.tfvars
```

### Every deployment

```bash
# Refresh tokens
aws-login
rosa login && export RHCS_TOKEN=$(rosa token)

# Configure
cd environments/demo
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set owner_tag, budget_alert_email, oidc_config_id

# Deploy
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Post-apply (operator roles, public ingress, admin user, pgvector)
cd ../..
./scripts/post-apply.sh
```

### Redeploy after teardown

```bash
aws-login
./scripts/redeploy.sh    # ~35 minutes end-to-end
```

---

## Project Structure

```
rhoai-iac-v2/
├── environments/
│   └── demo/
│       ├── main.tf               # Module wiring
│       ├── variables.tf          # All input variables
│       ├── outputs.tf            # Cluster URLs, IDs, ARNs
│       ├── backend.tf            # S3 remote state config
│       ├── versions.tf           # Provider version constraints
│       └── terraform.tfvars.example
├── modules/
│   ├── vpc/                      # VPC, subnets, NAT GW, route tables
│   ├── rosa-hcp/                 # ROSA HCP cluster + machine pools
│   ├── iam-irsa/                 # IAM roles for service accounts
│   ├── aurora-serverless/        # Aurora Serverless v2 + pgvector
│   ├── s3-data-lake/             # S3 bucket + lifecycle policies
│   ├── efs-storage/              # EFS + access point
│   ├── ecr-repos/                # ECR repositories
│   └── lambda-triggers/          # Demo scheduler + budget alert
└── scripts/
    ├── bootstrap-state.sh        # Create S3 + DynamoDB for TF state
    ├── post-apply.sh             # Operator roles, ingress, admin, pgvector
    ├── teardown.sh               # Complete teardown
    ├── redeploy.sh               # Full redeploy from scratch
    └── init-pgvector.sh          # Initialise Aurora schema
```

---

## Key Configuration

`environments/demo/terraform.tfvars` — minimum required values:

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

## ROSA Deployment Sequence

Terraform alone is not sufficient for ROSA HCP. The correct sequence is:

```
1. terraform apply
        ↓
2. rosa create operator-roles --cluster rhoai-demo --hosted-cp --yes
        ↓  (cluster moves from 'waiting' → 'installing' → 'ready')
3. watch -n 30 'rosa describe cluster -c rhoai-demo | grep State'
        ↓  (~15-20 min)
4. rosa edit cluster -c rhoai-demo --private=false
   rosa edit ingress -c rhoai-demo <ID> --private=false --yes
        ↓  (3-5 min DNS propagation)
5. rosa create admin -c rhoai-demo
```

`post-apply.sh` handles all 5 steps automatically.

> ⚠️ **RHCS token expires in ~15 min.** The Terraform provider is configured with
> `wait_for_create_complete = false` so apply returns immediately. Always re-export
> the token before retrying: `rosa login && export RHCS_TOKEN=$(rosa token)`

---

## Public Ingress Fix

ROSA HCP creates **private** ingress by default. Both flags must be set:

```bash
# Step 1 — cluster level
rosa edit cluster -c rhoai-demo --private=false

# Step 2 — ingress level (get the ID first)
rosa list ingresses -c rhoai-demo
rosa edit ingress -c rhoai-demo <INGRESS_ID> --private=false --yes

# Step 3 — verify (wait 3-5 min)
dig console-openshift-console.apps.rosa.rhoai-demo.pdde.p3.openshiftapps.com +short
# Should return public IP (not 10.x.x.x)
```

---

## RHOAI Installation

`rosa install addon` is **not supported** on HCP clusters. Install via OperatorHub:

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

## Teardown

```bash
./scripts/teardown.sh
```

Manual steps if script fails:

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
aws-login && rosa login && export RHCS_TOKEN=$(rosa token)
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
| Console/API unreachable | Set `--private=false` on BOTH cluster and ingress |
| Ingress ID `default` invalid | Get real ID from `rosa list ingresses` |
| DNS returns `10.x.x.x` after fix | Wait 3-5 min for NLB replacement |
| `oc` GLIBC error on AL2 bastion | Use oc `4.13.0` (not latest) |
| `rosa install addon` fails on HCP | Install RHOAI via `oc apply` Subscription |
| SSM instance profile permission denied | Use SSH key pair (IAM blocked by SSO role) |
| `zsh: no matches found: gpu[0]` | Single-quote: `'module.rosa...gpu[0]'` |
| State checksum mismatch | Use **Calculated** checksum from error, not Stored |
| VPC `DependencyViolation` on destroy | Delete leftover SGs (bastion-sg, ROSA vpce-sg) |

---

## Deployed Resources

| Resource | Value |
|---|---|
| VPC | `vpc-0d581778f01402b9c` |
| Private Subnets | `subnet-00e247c5583990d72`, `subnet-0d57e5d3282deefeb` |
| Public Subnets | `subnet-0fd2fc4560352711a`, `subnet-01c86847fb1afd4ad` |
| S3 Bucket | `rhoai-demo-demo-406337554361` |
| Aurora | `rhoai-demo-demo-db.cluster-cidweltunfq6.us-east-1.rds.amazonaws.com` |
| EFS | `fs-02b93265abb588d1c` |
| TF State | `rhoai-demo-tfstate-406337554361` / `rhoai-demo-tflock` |
| OIDC Config | `2ovm1pcngkss9e6stmbirbefljiiuptk` |
| ROSA API | `https://api.rhoai-demo.pdde.p3.openshiftapps.com:443` |
| ROSA Console | `https://console-openshift-console.apps.rosa.rhoai-demo.pdde.p3.openshiftapps.com` |

---

## Providers

| Provider | Version |
|---|---|
| `hashicorp/aws` | `~> 5.50` |
| `terraform-redhat/rhcs` | `~> 1.7` |

> Full provisioning guide: `rhoai-provisioning-guide-v3.docx`
