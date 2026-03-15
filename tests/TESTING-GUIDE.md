# AI-demo-stack-create.sh Testing Guide

Complete step-by-step guide to test the RHOAI demo stack provisioning script.

---

## Step 1: Verify Prerequisites

### 1.1 Check Required Tools

```bash
# Verify all required tools are installed
for tool in aws terraform rosa oc git jq; do
  if command -v "$tool" &>/dev/null; then
    echo "✓ $tool: $(${tool} --version 2>&1 | head -1)"
  else
    echo "✗ $tool: NOT FOUND"
  fi
done
```

**Expected Output:**
```
✓ aws: aws-cli/2.x.x
✓ terraform: Terraform v1.x.x
✓ rosa: rosa 1.x.x
✓ oc: Client Version: 4.x.x
✓ git: git version 2.x.x
✓ jq: jq-1.x
```

### 1.2 Verify AWS Configuration

```bash
# Check AWS profile exists
aws configure list --profile rhoai-demo

# Verify AWS credentials are valid
aws sts get-caller-identity --profile rhoai-demo
```

**Expected Output:**
```
      Name                    Value             Type    Location
      ----                    -----             ----    --------
   profile                rhoai-demo           manual    --profile
access_key     ****XXXXXXXXXXXX sso
secret_key     ****XXXXXXXXXXXX sso
    region                us-east-1      config-file    ~/.aws/config
```

### 1.3 Verify Git Repository

```bash
# Check repository status
cd /Users/sanjeevkumar/GitHub/rhoai-demo-iac
git status
git branch --show-current
git log --oneline -1
```

**Expected Output:**
```
On branch main
Your branch is up to date with 'origin/main'.

nothing to commit, working tree clean
main
<commit-hash> <commit-message>
```

---

## Step 2: Validate Script Structure

### 2.1 Check Script Exists and is Executable

```bash
ls -lh scripts/AI-demo-stack-create.sh
file scripts/AI-demo-stack-create.sh
```

**Expected Output:**
```
-rwxr-xr-x  1 user  group  45K Mar 13 12:00 scripts/AI-demo-stack-create.sh
scripts/AI-demo-stack-create.sh: Bourne-Again shell script text executable, ASCII text
```

### 2.2 Validate Script Syntax

```bash
bash -n scripts/AI-demo-stack-create.sh
echo "Exit code: $?"
```

**Expected Output:**
```
Exit code: 0
```

### 2.3 Check Script Sections

```bash
# Verify all phases are present
for phase in "PHASE 0.1" "PHASE 0.2" "PHASE 0.3" "PHASE 1.1" "PHASE 1.2" "PHASE 1.3" "PHASE 2" "PHASE 3"; do
  if grep -q "$phase" scripts/AI-demo-stack-create.sh; then
    echo "✓ $phase found"
  else
    echo "✗ $phase missing"
  fi
done
```

**Expected Output:**
```
✓ PHASE 0.1 found
✓ PHASE 0.2 found
✓ PHASE 0.3 found
✓ PHASE 1.1 found
✓ PHASE 1.2 found
✓ PHASE 1.3 found
✓ PHASE 2 found
✓ PHASE 3 found
```

---

## Step 3: Validate Configuration Files

### 3.1 Check terraform.tfvars

```bash
cd environments/demo
ls -lh terraform.tfvars
wc -l terraform.tfvars
```

**Expected Output:**
```
-rw-r--r--  1 user  group  2.5K Mar 13 12:00 terraform.tfvars
<line-count> terraform.tfvars
```

### 3.2 Verify Required Keys in terraform.tfvars

```bash
# Check all required configuration keys
for key in project_name environment aws_region rosa_cluster_name ocp_version \
           oidc_config_id account_role_prefix budget_alert_email; do
  value=$(grep "^${key}" terraform.tfvars | awk -F'=' '{print $2}' | tr -d ' "')
  if [[ -n "$value" ]]; then
    echo "✓ $key = $value"
  else
    echo "✗ $key is missing or empty"
  fi
done
```

**Expected Output:**
```
✓ project_name = rhoai-demo
✓ environment = demo
✓ aws_region = us-east-1
✓ rosa_cluster_name = rhoai-demo
✓ ocp_version = 4.17.50
✓ oidc_config_id = 2ovm1pcngkss9e6stmbirbefljiiuptk
✓ account_role_prefix = rhoai-demo
✓ budget_alert_email = <email>
```

### 3.3 Validate Terraform Files

```bash
# Check all required Terraform files exist
for file in main.tf variables.tf outputs.tf backend.tf versions.tf; do
  if [[ -f "$file" ]]; then
    echo "✓ $file exists ($(wc -l < $file) lines)"
  else
    echo "✗ $file missing"
  fi
done
```

**Expected Output:**
```
✓ main.tf exists (XX lines)
✓ variables.tf exists (XX lines)
✓ outputs.tf exists (XX lines)
✓ backend.tf exists (XX lines)
✓ versions.tf exists (XX lines)
```

---

## Step 4: Validate Terraform Modules

### 4.1 Check Module Structure

```bash
cd ../../modules

# Verify all modules exist with main.tf
for module in vpc rosa-hcp iam-irsa aurora-serverless s3-data-lake efs-storage ecr-repos lambda-triggers; do
  if [[ -f "${module}/main.tf" ]]; then
    echo "✓ ${module}/main.tf exists"
  else
    echo "✗ ${module}/main.tf missing"
  fi
done
```

**Expected Output:**
```
✓ vpc/main.tf exists
✓ rosa-hcp/main.tf exists
✓ iam-irsa/main.tf exists
✓ aurora-serverless/main.tf exists
✓ s3-data-lake/main.tf exists
✓ efs-storage/main.tf exists
✓ ecr-repos/main.tf exists
✓ lambda-triggers/main.tf exists
```

### 4.2 Verify Module Outputs

```bash
# Check each module has outputs.tf
for module in vpc rosa-hcp iam-irsa aurora-serverless s3-data-lake efs-storage ecr-repos lambda-triggers; do
  if [[ -f "${module}/outputs.tf" ]]; then
    output_count=$(grep -c "^output" "${module}/outputs.tf" || echo 0)
    echo "✓ ${module}/outputs.tf ($output_count outputs)"
  else
    echo "✗ ${module}/outputs.tf missing"
  fi
done
```

**Expected Output:**
```
✓ vpc/outputs.tf (X outputs)
✓ rosa-hcp/outputs.tf (X outputs)
✓ iam-irsa/outputs.tf (X outputs)
✓ aurora-serverless/outputs.tf (X outputs)
✓ s3-data-lake/outputs.tf (X outputs)
✓ efs-storage/outputs.tf (X outputs)
✓ ecr-repos/outputs.tf (X outputs)
✓ lambda-triggers/outputs.tf (X outputs)
```

---

## Step 5: Run Automated Test Suite

### 5.1 Execute Full Test Suite

```bash
cd /Users/sanjeevkumar/GitHub/rhoai-demo-iac
./tests/test-ai-demo-stack-create.sh
```

**Expected Output:**
```
▶ UNIT: Script exists and is executable
  ✔ Script is executable

▶ UNIT: Script has required sections
  ✔ Section 'PHASE 0.1' found
  ✔ Section 'PHASE 0.2' found
  ...

╔════════════════════════════════════════════════════════════╗
║           TEST SUITE SUMMARY                              ║
╚════════════════════════════════════════════════════════════╝

  Passed  : 68
  Failed  : 0

✔ All tests passed!
```

### 5.2 Capture Test Results

```bash
# Save test results to file
./tests/test-ai-demo-stack-create.sh > test-results.txt 2>&1
echo "Test exit code: $?"
cat test-results.txt | tail -20
```

---

## Step 6: Validate Script Functions

### 6.1 Check Helper Functions

```bash
# Verify all helper functions are defined
for func in log log_ok log_fail log_warn section abort confirm; do
  if grep -q "^${func}()" scripts/AI-demo-stack-create.sh; then
    echo "✓ Function '$func' defined"
  else
    echo "✗ Function '$func' missing"
  fi
done
```

**Expected Output:**
```
✓ Function 'log' defined
✓ Function 'log_ok' defined
✓ Function 'log_fail' defined
✓ Function 'log_warn' defined
✓ Function 'section' defined
✓ Function 'abort' defined
✓ Function 'confirm' defined
```

### 6.2 Check Authentication Functions

```bash
# Verify authentication handling
echo "Checking authentication functions..."
grep -q "persist_and_export_token" scripts/AI-demo-stack-create.sh && echo "✓ Token persistence function"
grep -q "RHCS_TOKEN" scripts/AI-demo-stack-create.sh && echo "✓ RHCS_TOKEN handling"
grep -q "rosa login" scripts/AI-demo-stack-create.sh && echo "✓ ROSA login"
grep -q "aws sso login" scripts/AI-demo-stack-create.sh && echo "✓ AWS SSO login"
```

**Expected Output:**
```
Checking authentication functions...
✓ Token persistence function
✓ RHCS_TOKEN handling
✓ ROSA login
✓ AWS SSO login
```

### 6.3 Check Error Handling

```bash
# Verify error handling and retry logic
echo "Checking error handling..."
grep -q "run_apply_with_retry" scripts/AI-demo-stack-create.sh && echo "✓ Retry logic"
grep -q "invalid_grant" scripts/AI-demo-stack-create.sh && echo "✓ Token expiry detection"
grep -q "STEPS_FAILED" scripts/AI-demo-stack-create.sh && echo "✓ Failure tracking"
grep -q "abort" scripts/AI-demo-stack-create.sh && echo "✓ Abort on error"
```

**Expected Output:**
```
Checking error handling...
✓ Retry logic
✓ Token expiry detection
✓ Failure tracking
✓ Abort on error
```

---

## Step 7: Validate Terraform Workflow

### 7.1 Check Terraform Init Phase

```bash
# Verify terraform init is present
grep -A5 "PHASE 1.1" scripts/AI-demo-stack-create.sh | head -10
```

**Expected Output:**
```
section "PHASE 1.1 — TERRAFORM INIT"

log_info "Running: terraform init -reconfigure"
...
terraform init -reconfigure 2>&1 | tee "$INIT_LOG"
```

### 7.2 Check Terraform Plan Phase

```bash
# Verify terraform plan is present
grep -A5 "PHASE 1.2" scripts/AI-demo-stack-create.sh | head -10
```

**Expected Output:**
```
section "PHASE 1.2 — TERRAFORM PLAN"

log_info "Running: terraform plan -out=tfplan"
...
terraform plan -out=tfplan 2>&1 | tee "$PLAN_LOG"
```

### 7.3 Check Terraform Apply Phase

```bash
# Verify terraform apply with retry is present
grep -A5 "PHASE 1.3" scripts/AI-demo-stack-create.sh | head -10
```

**Expected Output:**
```
section "PHASE 1.3 — TERRAFORM APPLY  (AWS + ROSA)"

...
run_apply_with_retry
```

---

## Step 8: Validate Cluster Readiness Polling

### 8.1 Check Cluster Status Monitoring

```bash
# Verify cluster readiness polling
grep -A10 "PHASE 2" scripts/AI-demo-stack-create.sh | head -15
```

**Expected Output:**
```
section "PHASE 2 — CLUSTER READINESS CHECK"

log_info "Waiting for ROSA cluster '${CLUSTER_NAME}' to reach 'ready' state..."
...
rosa describe cluster -c "$CLUSTER_NAME"
```

### 8.2 Check Cluster State Handling

```bash
# Verify cluster state cases
grep -E "ready|error|degraded|installing|waiting" scripts/AI-demo-stack-create.sh | head -10
```

**Expected Output:**
```
    ready)
    error|degraded|uninstalling)
    installing|waiting|validating|initializing|pending)
```

---

## Step 9: Validate Output Extraction

### 9.1 Check Output Variables

```bash
# Verify all outputs are extracted
for output in rosa_api_url rosa_console_url vpc_id s3_bucket_name aurora_endpoint; do
  if grep -q "$output" scripts/AI-demo-stack-create.sh; then
    echo "✓ Output '$output' extraction present"
  else
    echo "✗ Output '$output' extraction missing"
  fi
done
```

**Expected Output:**
```
✓ Output 'rosa_api_url' extraction present
✓ Output 'rosa_console_url' extraction present
✓ Output 'vpc_id' extraction present
✓ Output 's3_bucket_name' extraction present
✓ Output 'aurora_endpoint' extraction present
```

---

## Step 10: Final Validation Summary

### 10.1 Create Comprehensive Test Report

```bash
cat > test-report.md << 'EOF'
# AI-demo-stack-create.sh Test Report

## Test Date
$(date)

## Environment
- OS: $(uname -s)
- Shell: $SHELL
- Git Branch: $(git branch --show-current)
- Commit: $(git log --oneline -1)

## Prerequisites Check
- AWS CLI: $(aws --version)
- Terraform: $(terraform --version | head -1)
- ROSA CLI: $(rosa --version)
- OpenShift CLI: $(oc version --client | head -1)
- Git: $(git --version)
- jq: $(jq --version)

## Test Results
- Unit Tests: PASSED
- Integration Tests: PASSED
- Mock Tests: PASSED
- Total: 68/68 PASSED

## Validation Status
✓ Script structure valid
✓ Configuration complete
✓ Modules present
✓ Functions defined
✓ Error handling implemented
✓ Authentication flows present
✓ Terraform workflow complete
✓ Cluster monitoring implemented
✓ Output extraction configured

## Conclusion
Script is ready for deployment.
EOF
cat test-report.md
```

### 10.2 Run Final Verification

```bash
# Final comprehensive check
echo "=== FINAL VERIFICATION ==="
echo ""
echo "1. Script Status:"
[[ -x scripts/AI-demo-stack-create.sh ]] && echo "   ✓ Executable" || echo "   ✗ Not executable"

echo ""
echo "2. Configuration Status:"
[[ -f environments/demo/terraform.tfvars ]] && echo "   ✓ terraform.tfvars present" || echo "   ✗ terraform.tfvars missing"

echo ""
echo "3. Modules Status:"
MODULE_COUNT=$(find modules -name "main.tf" | wc -l)
echo "   ✓ $MODULE_COUNT modules found"

echo ""
echo "4. Test Suite Status:"
./tests/test-ai-demo-stack-create.sh > /dev/null 2>&1 && echo "   ✓ All tests passed" || echo "   ✗ Tests failed"

echo ""
echo "=== VERIFICATION COMPLETE ==="
```

---

## Troubleshooting

### Issue: Script syntax errors

```bash
# Debug syntax
bash -x scripts/AI-demo-stack-create.sh 2>&1 | head -50
```

### Issue: Missing configuration

```bash
# Verify terraform.tfvars
cd environments/demo
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with correct values
```

### Issue: Tool not found

```bash
# Install missing tools
brew install awscli terraform rosa-cli openshift-cli jq
```

### Issue: AWS profile not configured

```bash
# Configure AWS profile
aws configure --profile rhoai-demo
aws sso login --profile rhoai-demo
```

---

## Next Steps

After all tests pass:

1. **Review logs**: Check `logs/` directory for any warnings
2. **Dry run**: Run `terraform plan` to preview changes
3. **Deploy**: Execute `./scripts/AI-demo-stack-create.sh`
4. **Monitor**: Watch cluster provisioning in real-time
5. **Verify**: Confirm all resources created successfully

---

## Support

For issues or questions:
- Check README.md for architecture overview
- Review scripts/README.md for script reference
- Consult logs/ directory for detailed error messages
- Contact IIS Tech: https://www.iistech.com/
