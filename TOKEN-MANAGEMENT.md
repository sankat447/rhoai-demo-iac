# Token Management Quick Reference

## Token Expiry Symptoms

```
aws: [ERROR]: Error when retrieving token from sso: Token has expired and refresh failed
rosa: E: Failed to create OCM connection: access and refresh tokens are unavailable or expired
```

## Quick Recovery

### Option 1: Complete Credential Reset (Recommended for Expired Tokens)

```bash
./scripts/reset-credentials.sh
```

This script:
- Clears all cached AWS SSO credentials
- Clears all cached ROSA/OCM credentials
- Performs fresh AWS SSO login
- Performs fresh ROSA/OCM login
- Exports RHCS_TOKEN for Terraform
- Persists tokens to shell rc file

### Option 2: Automated Recovery (for Recently Expired Tokens)

```bash
./scripts/reauth.sh
```

This script:
- Refreshes AWS SSO
- Refreshes ROSA/OCM
- Exports RHCS_TOKEN
- Persists tokens

### Option 3: Manual Recovery

#### Step 1: Refresh AWS SSO

```bash
aws sso login --profile rhoai-demo
```

Verify:
```bash
aws sts get-caller-identity --profile rhoai-demo
```

#### Step 2: Refresh ROSA/OCM

```bash
rosa login
```

Verify:
```bash
rosa whoami
```

#### Step 3: Export RHCS_TOKEN

```bash
export RHCS_TOKEN=$(rosa token)
export ROSA_TOKEN=$RHCS_TOKEN
```

#### Step 4: Persist Tokens (Optional)

For zsh:
```bash
cat >> ~/.zshrc << 'EOF'
export RHCS_TOKEN=$(rosa token)
export ROSA_TOKEN=$RHCS_TOKEN
EOF
```

For bash:
```bash
cat >> ~/.bash_profile << 'EOF'
export RHCS_TOKEN=$(rosa token)
export ROSA_TOKEN=$RHCS_TOKEN
EOF
```

## Token Lifetimes

| Token | Lifetime | Refresh |
|-------|----------|---------|
| AWS SSO | 12 hours | `aws sso login --profile rhoai-demo` |
| ROSA/OCM | 24 hours | `rosa login` |
| RHCS_TOKEN | 24 hours | `rosa token` |

## Verify Tokens

```bash
# AWS SSO
aws sts get-caller-identity --profile rhoai-demo

# ROSA/OCM
rosa whoami

# RHCS_TOKEN
echo $RHCS_TOKEN | head -c 20
```

## Common Issues

### Issue: "Token has expired"

**Solution:**
```bash
./scripts/reauth.sh
```

### Issue: "Not able to get authentication token"

**Solution:**
```bash
rosa login
rosa token
export RHCS_TOKEN=$(rosa token)
```

### Issue: "invalid_grant" during terraform apply

**Solution:**
The script auto-detects this and retries with re-authentication. If manual retry needed:

```bash
./scripts/reauth.sh
cd environments/demo
terraform apply tfplan
```

## Before Running Deployment

Always verify both tokens are valid:

```bash
# Check AWS
aws sts get-caller-identity --profile rhoai-demo

# Check ROSA
rosa whoami

# Check RHCS_TOKEN
echo "RHCS_TOKEN set: $([ -n "$RHCS_TOKEN" ] && echo 'YES' || echo 'NO')"
```

## Troubleshooting

### AWS SSO not working

```bash
# Clear AWS cache
rm -rf ~/.aws/sso/cache/*

# Re-login
aws sso login --profile rhoai-demo
```

### ROSA not working

```bash
# Clear ROSA cache
rm -rf ~/.config/rosa/

# Re-login
rosa login
```

### Terraform still failing after token refresh

```bash
# Force new token
unset RHCS_TOKEN
export RHCS_TOKEN=$(rosa token)

# Retry apply
cd environments/demo
terraform apply tfplan
```

## Token Persistence

Tokens are automatically persisted to:
- **zsh**: `~/.zshrc`
- **bash**: `~/.bash_profile`
- **sh**: `~/.profile`

To verify:
```bash
grep RHCS_TOKEN ~/.zshrc  # or ~/.bash_profile
```

## Next Steps

After token refresh:

```bash
# Option 1: Bootstrap Terraform state
./scripts/bootstrap-state.sh

# Option 2: Deploy full stack
./scripts/AI-demo-stack-create.sh

# Option 3: Just verify tokens
./scripts/reauth.sh
```

---

**Note:** The `AI-demo-stack-create.sh` script includes automatic token expiry detection and retry logic. If tokens expire during deployment, the script will automatically re-authenticate and retry (up to 3 attempts).
