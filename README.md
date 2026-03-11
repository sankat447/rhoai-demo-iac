# RHOAI Demo IaC — AWS + ROSA Platform Terraform

> **Platform-Level Infrastructure as Code** for the Red Hat OpenShift AI (RHOAI) demo environment on AWS with ROSA Hosted Control Plane.

---

## 📐 Scope — What This Repo Covers

This repository manages the **platform layer only**:

| Layer | This Repo | Separate GitOps Repo |
|-------|-----------|---------------------|
| VPC + Networking | ✅ | |
| ROSA HCP Cluster | ✅ | |
| ROSA Machine Pools (Workers + GPU) | ✅ | |
| IAM / IRSA Roles | ✅ | |
| Aurora Serverless v2 + pgvector | ✅ | |
| S3 Data Lake Buckets | ✅ | |
| EFS Storage (Jupyter PVCs) | ✅ | |
| ECR Repositories | ✅ | |
| Lambda Schedulers + Budget Alerts | ✅ | |
| RHOAI Operator Installation | | ✅ (ArgoCD) |
| ArgoCD Bootstrap | | ✅ (ArgoCD) |
| Open WebUI, n8n, Redis, MongoDB pods | | ✅ (Helm/ArgoCD) |
| LangChain / LangServe deployments | | ✅ (Helm/ArgoCD) |
| vLLM ServingRuntime YAML | | ✅ (GitOps) |

---

## 🏗️ Architecture — Module Overview

```
modules/
├── vpc/                  ← VPC, public/private subnets, NAT Gateway, route tables
├── rosa-hcp/             ← ROSA HCP cluster, worker pool (Spot), GPU pool (starts at 0)
├── iam-irsa/             ← IAM roles federated via OIDC (S3, Bedrock, ECR, SSM)
├── aurora-serverless/    ← Aurora PostgreSQL Serverless v2 + pgvector extension
├── s3-data-lake/         ← Data lake bucket, Terraform state bucket, DynamoDB lock
├── efs-storage/          ← EFS for ReadWriteMany PVCs (Jupyter notebooks)
├── ecr-repos/            ← ECR container image repositories + lifecycle policies
└── lambda-triggers/      ← Demo scheduler (start/stop cron) + budget alerts

environments/
├── demo/                 ← FILL IN: terraform.tfvars (copy from .example)
└── prod/                 ← FILL IN: terraform.tfvars for production
```

---

## 🚀 Quick Start — First Time Setup

### Prerequisites on your MacBook

```bash
# Install required tools (one-time)
brew install tfenv awscli rosa-cli openshift-cli helm argocd
tfenv install 1.8.5 && tfenv use 1.8.5

# Verify
terraform version    # Should show 1.8.5
rosa version         # Should show 1.x.x
aws --version        # Should show 2.x.x
```

### Step 1 — Configure AWS credentials

```bash
# Option A: aws-vault (recommended — credentials in macOS Keychain)
brew install --cask aws-vault
aws-vault add rhoai-demo
# Enter your AWS Access Key ID and Secret

# Option B: AWS SSO (if your org uses SSO)
aws configure sso --profile rhoai-demo

# Verify
aws-vault exec rhoai-demo -- aws sts get-caller-identity
```

### Step 2 — Bootstrap Terraform remote state

> **One-time only.** Creates the S3 bucket and DynamoDB table for storing Terraform state.

```bash
aws-vault exec rhoai-demo -- ./scripts/bootstrap-state.sh
```

After it runs, **fill in `environments/demo/backend.tf`** with the bucket name and table name printed at the end.

### Step 3 — Configure your environment variables

```bash
cd environments/demo
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — fill in your values (see Configuration Reference below)
```

**Minimum required values to fill in:**

| Variable | Where to find it | Example |
|----------|-----------------|---------|
| `owner_tag` | Your email | `john@company.com` |
| `budget_alert_email` | Your email | `john@company.com` |
| `rosa_cluster_name` | Your choice | `rhoai-demo` |

### Step 4 — Get Red Hat OCM Token

1. Go to [console.redhat.com/openshift/token](https://console.redhat.com/openshift/token)
2. Download the offline token JSON file
3. Export for Terraform:

```bash
export RHCS_TOKEN=$(cat ~/Downloads/rh-ocm-token.json)
# Add to ~/.zprofile for persistence
echo 'export RHCS_TOKEN=$(cat ~/rh-ocm-token.json)' >> ~/.zprofile
```

### Step 5 — Provision the full stack

```bash
# Full provision (~25-30 minutes — ROSA cluster creation is the slow step)
aws-vault exec rhoai-demo -- ./scripts/provision.sh
```

---

## 📋 Configuration Reference

All variables are defined in `environments/demo/variables.tf` with descriptions.
Set your values in `environments/demo/terraform.tfvars` (never commit this file).

### Key decisions to make in tfvars

#### Network
| Variable | Demo Default | Production |
|----------|-------------|------------|
| `availability_zones` | 2 AZs | 3 AZs |
| `vpc_cidr` | `10.0.0.0/16` | Different CIDR |

#### ROSA Cluster
| Variable | Demo Default | Notes |
|----------|-------------|-------|
| `worker_instance_type` | `c5.2xlarge` | 8 vCPU / 16GB. See sizing guide below. |
| `worker_min_replicas` | `2` | Set to `0` when stopped |
| `ocp_version` | `4.15.28` | Check: `rosa list versions --hosted-cp` |
| `create_gpu_pool` | `true` | Pool starts at 0 replicas — no cost until needed |
| `gpu_instance_type` | `g4dn.xlarge` | 16GB T4 — fits 7-8B models with quantization |

#### Worker Instance Type Sizing Guide
| Type | vCPU | RAM | Use Case | ~Spot Price |
|------|------|-----|----------|-------------|
| `c5.2xlarge` | 8 | 16GB | Demo default — general workloads | ~$0.07/hr |
| `m5.2xlarge` | 8 | 32GB | Memory-heavy workloads (more pods) | ~$0.08/hr |
| `c5.4xlarge` | 16 | 32GB | Production sizing | ~$0.14/hr |

#### Aurora Serverless v2
| Variable | Demo | Production |
|----------|------|------------|
| `aurora_min_acu` | `0.5` | `2` |
| `aurora_skip_snapshot` | `true` | **`false`** |
| `aurora_deletion_protection` | `false` | **`true`** |
| `aurora_backup_retention` | `1` | `14` |

#### Cost Control Automation
| Variable | Default | Notes |
|----------|---------|-------|
| `monthly_budget_usd` | `700` | Alert fires at 80% and 100% |
| `demo_start_cron` | `cron(0 8 ? * MON-FRI *)` | 8am UTC weekdays — adjust for your TZ |
| `demo_stop_cron` | `cron(0 20 ? * MON-FRI *)` | 8pm UTC weekdays |

> **Timezone note:** Cron times are UTC. For IST (UTC+5:30): 8am UTC = 1:30pm IST. Adjust to your timezone.

---

## 🎛️ Demo Lifecycle Commands

### Daily operations

```bash
# Morning — start demo (scale workers from 0 to 2, ~8 min)
aws-vault exec rhoai-demo -- ./scripts/start-demo.sh

# Evening — stop demo (scale workers to 0)
aws-vault exec rhoai-demo -- ./scripts/stop-demo.sh
```

### GPU demo (vLLM)

```bash
# Before GPU demo — start GPU node (~10 min to be ready)
aws-vault exec rhoai-demo -- ./scripts/gpu-on.sh

# After GPU demo — remove GPU node (saves ~$0.37/hr spot)
aws-vault exec rhoai-demo -- ./scripts/gpu-off.sh
```

### Full provision / destroy

```bash
# Provision from scratch (first time or after teardown)
aws-vault exec rhoai-demo -- ./scripts/provision.sh

# Destroy everything (multi-day break, end of sprint)
aws-vault exec rhoai-demo -- ./scripts/teardown.sh
```

### Terraform operations (manual)

```bash
cd environments/demo

# Always plan first — review before applying
aws-vault exec rhoai-demo -- terraform plan -out=tfplan

# Apply a saved plan
aws-vault exec rhoai-demo -- terraform apply tfplan

# Inspect outputs
aws-vault exec rhoai-demo -- terraform output

# Get DB password from SSM (DO NOT use terraform output for this)
aws-vault exec rhoai-demo -- \
  aws ssm get-parameter --name /rhoai-demo/aurora/master-password \
  --with-decryption --query Parameter.Value --output text
```

---

## 💰 Expected Costs

### Demo — Active (workers running, no GPU)
| Service | Cost/hr | Cost/month |
|---------|---------|------------|
| ROSA HCP fee | $0.25 | $183 |
| ROSA service fee (2×c5.2xlarge) | $0.17 | $125 |
| EC2 Spot (2×c5.2xlarge) | $0.14 | ~$102 |
| Aurora Serverless v2 (0.5 ACU) | $0.06 | ~$30 |
| VPC NAT Gateway | $0.045 | ~$33 |
| S3 + EFS + ECR | | ~$10 |
| **Total active** | **~$0.66/hr** | **~$483** |

### Demo — Stopped (workers at 0)
| Service | Cost/hr | Notes |
|---------|---------|-------|
| ROSA HCP fee | $0.25 | Control plane always running |
| Aurora Serverless v2 | ~$0.03 | Scales to minimum ACU |
| NAT Gateway | $0.045 | Still running |
| **Total stopped** | **~$0.35/hr** | **~$255/mo** |

### GPU active (add to above)
| Service | Cost/hr |
|---------|---------|
| g4dn.xlarge Spot | ~$0.37 |

> **Tip:** Use `teardown.sh` when not needed for 3+ days to drop to ~$0.

---

## 🔐 Security Practices

1. **No static credentials** — AWS Vault stores credentials in macOS Keychain. GitHub Actions uses OIDC (no static keys in CI).
2. **No secrets in Terraform** — DB password is auto-generated and stored in SSM Parameter Store. Never appears in `terraform output`.
3. **No secrets in .tfvars** — Only config values (names, sizes, regions) go in `terraform.tfvars`. Sensitive values come from SSM or environment variables.
4. **Pre-commit hooks** — `detect-aws-credentials` hook prevents accidental key commits. Run `pre-commit install` after cloning.
5. **Checkov scanning** — IaC security scanner runs on every commit and in CI.
6. **Least-privilege IAM** — IRSA roles are scoped to specific namespaces and specific S3 prefixes/Bedrock models.

---

## 📂 File Reference

```
rhoai-demo-iac/
├── README.md                            ← You are here
├── .gitignore                           ← Excludes *.tfvars, *.tfstate, .terraform/
├── .pre-commit-config.yaml              ← Auto-linting on every commit
│
├── modules/                             ← Reusable platform modules
│   ├── vpc/
│   │   ├── main.tf                      ← VPC, subnets, NAT, route tables
│   │   ├── variables.tf                 ← Module inputs
│   │   └── outputs.tf                   ← VPC ID, subnet IDs, etc.
│   ├── rosa-hcp/
│   │   ├── main.tf                      ← ROSA cluster, worker + GPU machine pools
│   │   ├── variables.tf
│   │   └── outputs.tf                   ← API URL, console URL, OIDC endpoint
│   ├── iam-irsa/
│   │   ├── main.tf                      ← 4 IRSA roles (S3, Bedrock, ECR, SSM)
│   │   ├── variables.tf
│   │   └── outputs.tf                   ← Role ARNs for service account annotation
│   ├── aurora-serverless/
│   │   ├── main.tf                      ← Aurora Serverless v2 + pgvector param group
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── init.sql                     ← Run after cluster creation to enable pgvector
│   ├── s3-data-lake/
│   │   ├── main.tf                      ← Data bucket + tfstate bucket + DynamoDB lock
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── efs-storage/
│   │   ├── main.tf                      ← EFS + mount targets + access point
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── ecr-repos/
│   │   ├── main.tf                      ← ECR repos + lifecycle policies
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── lambda-triggers/
│       ├── main.tf                      ← Scheduler Lambda + EventBridge + Budget
│       ├── variables.tf
│       └── outputs.tf
│
├── environments/
│   ├── demo/
│   │   ├── main.tf                      ← Wires all modules together
│   │   ├── variables.tf                 ← All configurable inputs
│   │   ├── outputs.tf                   ← Key outputs + next steps
│   │   ├── versions.tf                  ← Provider version constraints
│   │   ├── backend.tf                   ← ⚠️ FILL IN: S3 bucket + DynamoDB table
│   │   └── terraform.tfvars.example     ← ⚠️ COPY TO terraform.tfvars and fill in
│   └── prod/
│       ├── versions.tf
│       ├── backend.tf                   ← ⚠️ FILL IN
│       └── terraform.tfvars.example     ← ⚠️ COPY and fill in for production
│
├── scripts/
│   ├── bootstrap-state.sh               ← Run ONCE: creates S3 + DynamoDB for tfstate
│   ├── provision.sh                     ← Full stack creation (~25 min)
│   ├── teardown.sh                      ← Full stack destruction
│   ├── start-demo.sh                    ← Scale workers 0→2 (morning)
│   ├── stop-demo.sh                     ← Scale workers 2→0 (evening)
│   ├── gpu-on.sh                        ← Add GPU node for vLLM demos
│   └── gpu-off.sh                       ← Remove GPU node
│
└── .github/workflows/
    ├── tf-plan.yml                      ← PR: runs terraform plan, posts comment
    └── tf-apply.yml                     ← Main push: runs terraform apply
```

---

## 🔧 After terraform apply — Next Steps

The `terraform output next_steps` command (runs automatically at end of provision.sh) prints exactly what to do next. The summary is:

1. **Login to ROSA:** `oc login --server=$(terraform output -raw rosa_api_url) --username=cluster-admin`
2. **Install RHOAI operator:** `rosa install-addon --cluster=rhoai-demo managed-odh`
3. **Install EFS CSI driver:** `rosa install-addon --cluster=rhoai-demo aws-efs-csi-driver-operator`
4. **Init pgvector in Aurora:** `psql <aurora_endpoint> -f modules/aurora-serverless/init.sql`
5. **Bootstrap application layer** from your separate GitOps repository (ArgoCD, Helm charts)

---

## 🚢 AWS Marketplace Packaging

The CloudFormation templates for Marketplace distribution live in the `cloudformation/` directory (separate from this Terraform IaC). Key points:

- **Terraform** = your own provisioning tool (developers, CI/CD pipeline)
- **CloudFormation** = customer-facing delivery via AWS Marketplace
- Use the `cfn-lint` pre-commit hook to validate templates before submission
- Run `taskcat test run` to validate deployment across multiple AWS regions

See the companion guide in `cloudformation/README.md`.

---

## 🤝 Contributing

1. Create a branch: `git checkout -b feat/your-change`
2. Pre-commit hooks run automatically on `git commit` (terraform fmt, checkov, cfn-lint)
3. Open a PR — GitHub Actions runs `terraform plan` and posts the output as a PR comment
4. Merge to main — GitHub Actions runs `terraform apply` (with manual approval gate)

---

*Generated for RHOAI Demo Environment · AWS + ROSA Platform Architecture · 2025*
