# Test Suite for AI-demo-stack-create.sh

Comprehensive test suite validating the RHOAI demo stack provisioning script without requiring actual AWS/ROSA deployment.

## Running Tests

```bash
./tests/test-ai-demo-stack-create.sh
```

## Test Categories

### Unit Tests (20 tests)
- Script structure and executability
- Required sections (PHASE 0.1 through PHASE 3)
- Helper functions (log, log_ok, log_fail, log_warn, section, abort, confirm)
- Tool availability checks
- Token handling (persist_and_export_token, RHCS_TOKEN)
- Error handling and retry logic
- Terraform phases (init, plan, apply)
- Cluster readiness polling
- Output extraction

### Integration Tests (16 tests)
- terraform.tfvars validation (8 required keys)
- Terraform configuration files (main.tf, variables.tf, outputs.tf, backend.tf, versions.tf)
- Terraform modules (vpc, rosa-hcp, iam-irsa, aurora-serverless, s3-data-lake, efs-storage, ecr-repos, lambda-triggers)
- Script syntax validation
- Log directory setup
- Environment directory structure

### Mock Tests (4 tests)
- Tool availability (aws, terraform, rosa, oc, git, jq)
- AWS profile configuration
- Git repository validation
- Current branch detection

## Test Results

All 68 tests should pass:
- **Passed**: 68
- **Failed**: 0

## What Gets Tested

✓ Script structure and phases  
✓ Helper function definitions  
✓ Authentication handling (AWS SSO, ROSA/OCM, RHCS token)  
✓ Token expiry detection and retry logic  
✓ Terraform workflow (init → plan → apply)  
✓ Cluster readiness polling  
✓ Resource output extraction  
✓ Configuration validation  
✓ Module structure  
✓ Environment setup  

## What's NOT Tested

✗ Actual AWS resource creation (non-destructive)  
✗ Actual ROSA cluster provisioning  
✗ Real authentication flows  
✗ Terraform apply execution  
✗ Network connectivity  

## Prerequisites

For full test coverage, ensure:
- `aws`, `terraform`, `rosa`, `oc`, `git`, `jq` are installed
- AWS profile `rhoai-demo` is configured in `~/.aws/config`
- Repository is a valid git repo

## Exit Codes

- `0` — All tests passed
- `1` — One or more tests failed

## Adding New Tests

Edit `tests/test-ai-demo-stack-create.sh` and add test cases using:

```bash
test_start "TEST CATEGORY: Description"
if [[ condition ]]; then
  test_pass "What passed"
else
  test_fail "What failed"
fi
```

Or for skipped tests:
```bash
test_skip "Reason for skipping"
```
