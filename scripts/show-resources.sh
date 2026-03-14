#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# RHOAI Demo Infrastructure — Resource Inventory
# Lists all deployed AWS and ROSA resources in tabular format
# ─────────────────────────────────────────────────────────────────────────────

set -e

PROFILE="${AWS_PROFILE:-rhoai-demo}"
REGION="us-east-1"
CLUSTER_NAME="rhoai-demo"

# Colors
BOLD='\033[1m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                                    RHOAI DEMO INFRASTRUCTURE — RESOURCE INVENTORY                                                           ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null || echo "N/A")
CALLER_ARN=$(aws sts get-caller-identity --profile "$PROFILE" --query Arn --output text 2>/dev/null || echo "N/A")
CREATED_BY=$(echo "$CALLER_ARN" | awk -F'/' '{print $NF}')

# Get Terraform state path
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/../environments/demo"

# Helper function to get creation date from tags
get_creation_date() {
    local resource_id=$1
    local resource_type=$2
    
    case $resource_type in
        vpc)
            aws ec2 describe-vpcs --vpc-ids "$resource_id" --profile "$PROFILE" --query 'Vpcs[0].Tags[?Key==`CreationDate`].Value' --output text 2>/dev/null || echo "N/A"
            ;;
        subnet)
            aws ec2 describe-subnets --subnet-ids "$resource_id" --profile "$PROFILE" --query 'Subnets[0].Tags[?Key==`CreationDate`].Value' --output text 2>/dev/null || echo "N/A"
            ;;
        *)
            echo "N/A"
            ;;
    esac
}

# Print table header
printf "${BOLD}%-25s %-35s %-45s %-35s %-20s %-15s${NC}\n" "LAYER" "CATEGORY" "OBJECT_NAME" "OBJECT_ID" "CREATION_DATE" "CREATED_BY"
printf "%-25s %-35s %-45s %-35s %-20s %-15s\n" "=========================" "===================================" "=============================================" "===================================" "====================" "==============="

# ═════════════════════════════════════════════════════════════════════════════
# AWS FOUNDATION
# ═════════════════════════════════════════════════════════════════════════════
printf "${BLUE}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "AWS" "Foundation" "IIS Demo Lab" "$ACCOUNT_ID" "$(date +%Y-%m-%d)" "$CREATED_BY"

# ═════════════════════════════════════════════════════════════════════════════
# VPC & NETWORKING
# ═════════════════════════════════════════════════════════════════════════════
if [ -d "$TF_DIR" ]; then
    cd "$TF_DIR"
    
    # VPC
    VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "N/A")
    if [ "$VPC_ID" != "N/A" ]; then
        VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --profile "$PROFILE" --query 'Vpcs[0].CidrBlock' --output text 2>/dev/null || echo "N/A")
        printf "${BLUE}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "AWS" "VPC" "Multi-AZ VPC ($VPC_CIDR)" "$VPC_ID" "$(date +%Y-%m-%d)" "$CREATED_BY"
    fi
    
    # Public Subnets
    PUBLIC_SUBNETS=$(terraform output -json public_subnet_ids 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")
    for subnet in $PUBLIC_SUBNETS; do
        SUBNET_AZ=$(aws ec2 describe-subnets --subnet-ids "$subnet" --profile "$PROFILE" --query 'Subnets[0].AvailabilityZone' --output text 2>/dev/null || echo "N/A")
        SUBNET_CIDR=$(aws ec2 describe-subnets --subnet-ids "$subnet" --profile "$PROFILE" --query 'Subnets[0].CidrBlock' --output text 2>/dev/null || echo "N/A")
        printf "${BLUE}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "AWS" "Public Subnet" "$SUBNET_AZ ($SUBNET_CIDR)" "$subnet" "$(date +%Y-%m-%d)" "$CREATED_BY"
    done
    
    # Private Subnets
    PRIVATE_SUBNETS=$(terraform output -json private_subnet_ids 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")
    for subnet in $PRIVATE_SUBNETS; do
        SUBNET_AZ=$(aws ec2 describe-subnets --subnet-ids "$subnet" --profile "$PROFILE" --query 'Subnets[0].AvailabilityZone' --output text 2>/dev/null || echo "N/A")
        SUBNET_CIDR=$(aws ec2 describe-subnets --subnet-ids "$subnet" --profile "$PROFILE" --query 'Subnets[0].CidrBlock' --output text 2>/dev/null || echo "N/A")
        printf "${BLUE}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "AWS" "Private Subnet" "$SUBNET_AZ ($SUBNET_CIDR)" "$subnet" "$(date +%Y-%m-%d)" "$CREATED_BY"
    done
    
    # Internet Gateway
    if [ "$VPC_ID" != "N/A" ]; then
        IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --profile "$PROFILE" --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || echo "N/A")
        if [ "$IGW_ID" != "N/A" ] && [ "$IGW_ID" != "None" ]; then
            printf "${BLUE}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "AWS" "Internet Gateway" "Public subnet egress" "$IGW_ID" "$(date +%Y-%m-%d)" "$CREATED_BY"
        fi
    fi
    
    # NAT Gateway
    NAT_GW=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" --profile "$PROFILE" --query 'NatGateways[0].NatGatewayId' --output text 2>/dev/null || echo "N/A")
    if [ "$NAT_GW" != "N/A" ] && [ "$NAT_GW" != "None" ]; then
        NAT_AZ=$(aws ec2 describe-nat-gateways --nat-gateway-ids "$NAT_GW" --profile "$PROFILE" --query 'NatGateways[0].SubnetId' --output text 2>/dev/null | xargs -I {} aws ec2 describe-subnets --subnet-ids {} --profile "$PROFILE" --query 'Subnets[0].AvailabilityZone' --output text 2>/dev/null || echo "N/A")
        printf "${BLUE}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "AWS" "NAT Gateway" "Private subnet outbound ($NAT_AZ)" "$NAT_GW" "$(date +%Y-%m-%d)" "$CREATED_BY"
    fi
    
    # Route Tables
    ROUTE_TABLES=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --profile "$PROFILE" --query 'RouteTables[*].RouteTableId' --output text 2>/dev/null || echo "")
    RT_COUNT=$(echo "$ROUTE_TABLES" | wc -w | tr -d ' ')
    if [ "$RT_COUNT" -gt 0 ]; then
        printf "${BLUE}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "AWS" "Route Tables" "Public + Private routing ($RT_COUNT tables)" "$(echo $ROUTE_TABLES | cut -d' ' -f1)" "$(date +%Y-%m-%d)" "$CREATED_BY"
    fi
    
    # Security Groups
    SG_COUNT=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --profile "$PROFILE" --query 'SecurityGroups[?GroupName!=`default`]' --output json 2>/dev/null | jq '. | length' 2>/dev/null || echo "0")
    if [ "$SG_COUNT" -gt 0 ]; then
        FIRST_SG=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --profile "$PROFILE" --query 'SecurityGroups[?GroupName!=`default`] | [0].GroupId' --output text 2>/dev/null || echo "N/A")
        printf "${BLUE}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "AWS" "Security Groups" "ROSA + Aurora + EFS ($SG_COUNT groups)" "$FIRST_SG" "$(date +%Y-%m-%d)" "$CREATED_BY"
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# IAM & IDENTITY
# ═════════════════════════════════════════════════════════════════════════════
printf "${BLUE}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "AWS" "IAM Identity Center" "skumar · SystemAdministrator" "$CREATED_BY" "$(date +%Y-%m-%d)" "$CREATED_BY"

# OIDC Provider
OIDC_ID=$(cd "$TF_DIR" && terraform output -raw oidc_config_id 2>/dev/null || echo "2ovm1pcngkss9e6stmbirbefljiiuptk")
printf "${BLUE}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "AWS" "OIDC Provider" "Red Hat OCM OIDC" "$OIDC_ID" "$(date +%Y-%m-%d)" "$CREATED_BY"

# Account Roles
ACCOUNT_ROLES=$(aws iam list-roles --profile "$PROFILE" --query 'Roles[?starts_with(RoleName, `rhoai-demo-HCP-ROSA`)].RoleName' --output text 2>/dev/null || echo "")
ROLE_COUNT=$(echo "$ACCOUNT_ROLES" | wc -w | tr -d ' ')
if [ "$ROLE_COUNT" -gt 0 ]; then
    FIRST_ROLE=$(echo "$ACCOUNT_ROLES" | awk '{print $1}')
    printf "${BLUE}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "AWS" "Account Roles" "prefix: rhoai-demo ($ROLE_COUNT roles)" "$FIRST_ROLE" "$(date +%Y-%m-%d)" "$CREATED_BY"
fi

# Operator Roles
OPERATOR_ROLES=$(aws iam list-roles --profile "$PROFILE" --query 'Roles[?contains(RoleName, `rhoai-demo`) && contains(RoleName, `openshift`)].RoleName' --output text 2>/dev/null || echo "")
OP_COUNT=$(echo "$OPERATOR_ROLES" | wc -w | tr -d ' ')
if [ "$OP_COUNT" -gt 0 ]; then
    FIRST_OP=$(echo "$OPERATOR_ROLES" | awk '{print $1}')
    printf "${BLUE}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "AWS" "Operator Roles" "Cluster-specific ($OP_COUNT roles)" "$FIRST_OP" "$(date +%Y-%m-%d)" "$CREATED_BY"
fi

# IRSA Roles
IRSA_ROLES=$(aws iam list-roles --profile "$PROFILE" --query 'Roles[?contains(RoleName, `rhoai-demo-rhoai`)].RoleName' --output text 2>/dev/null || echo "")
IRSA_COUNT=$(echo "$IRSA_ROLES" | wc -w | tr -d ' ')
if [ "$IRSA_COUNT" -gt 0 ]; then
    FIRST_IRSA=$(echo "$IRSA_ROLES" | awk '{print $1}')
    printf "${BLUE}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "AWS" "IRSA Roles" "Service Account bindings ($IRSA_COUNT roles)" "$FIRST_IRSA" "$(date +%Y-%m-%d)" "$CREATED_BY"
fi

# ═════════════════════════════════════════════════════════════════════════════
# MANAGED SERVICES — STORAGE
# ═════════════════════════════════════════════════════════════════════════════

# EFS
EFS_ID=$(cd "$TF_DIR" && terraform output -raw efs_file_system_id 2>/dev/null || echo "N/A")
if [ "$EFS_ID" != "N/A" ]; then
    EFS_SIZE=$(aws efs describe-file-systems --file-system-id "$EFS_ID" --profile "$PROFILE" --query 'FileSystems[0].SizeInBytes.Value' --output text 2>/dev/null || echo "0")
    EFS_SIZE_GB=$((EFS_SIZE / 1024 / 1024 / 1024))
    printf "${BLUE}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "AWS" "EFS" "ReadWriteMany storage (${EFS_SIZE_GB}GB)" "$EFS_ID" "$(date +%Y-%m-%d)" "$CREATED_BY"
fi

# S3 Bucket
S3_BUCKET=$(cd "$TF_DIR" && terraform output -raw s3_bucket_name 2>/dev/null || echo "N/A")
if [ "$S3_BUCKET" != "N/A" ]; then
    S3_REGION=$(aws s3api get-bucket-location --bucket "$S3_BUCKET" --profile "$PROFILE" --query 'LocationConstraint' --output text 2>/dev/null || echo "us-east-1")
    [ "$S3_REGION" = "None" ] && S3_REGION="us-east-1"
    printf "${BLUE}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "AWS" "S3 Bucket" "Data lake / MLflow artifacts" "$S3_BUCKET" "$(date +%Y-%m-%d)" "$CREATED_BY"
fi

# Aurora RDS
AURORA_ENDPOINT=$(cd "$TF_DIR" && terraform output -raw aurora_endpoint 2>/dev/null || echo "N/A")
if [ "$AURORA_ENDPOINT" != "N/A" ]; then
    AURORA_CLUSTER=$(echo "$AURORA_ENDPOINT" | cut -d'.' -f1)
    AURORA_ENGINE=$(aws rds describe-db-clusters --db-cluster-identifier "$AURORA_CLUSTER" --profile "$PROFILE" --query 'DBClusters[0].EngineVersion' --output text 2>/dev/null || echo "N/A")
    printf "${BLUE}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "AWS" "Aurora Serverless v2" "PostgreSQL $AURORA_ENGINE + pgvector" "$AURORA_ENDPOINT" "$(date +%Y-%m-%d)" "$CREATED_BY"
fi

# ECR Repositories
ECR_REPOS=$(aws ecr describe-repositories --profile "$PROFILE" --query 'repositories[?starts_with(repositoryName, `rhoai-demo`)].repositoryName' --output text 2>/dev/null || echo "")
ECR_COUNT=$(echo "$ECR_REPOS" | wc -w | tr -d ' ')
if [ "$ECR_COUNT" -gt 0 ]; then
    FIRST_ECR=$(echo "$ECR_REPOS" | awk '{print $1}')
    printf "${BLUE}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "AWS" "ECR Repositories" "Private image hosting ($ECR_COUNT repos)" "$FIRST_ECR" "$(date +%Y-%m-%d)" "$CREATED_BY"
fi

# Lambda Functions
LAMBDA_ARN=$(cd "$TF_DIR" && terraform output -raw scheduler_lambda_arn 2>/dev/null || echo "N/A")
if [ "$LAMBDA_ARN" != "N/A" ]; then
    LAMBDA_NAME=$(echo "$LAMBDA_ARN" | awk -F':' '{print $NF}')
    printf "${BLUE}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "AWS" "Lambda Function" "Demo scheduler (start/stop)" "$LAMBDA_NAME" "$(date +%Y-%m-%d)" "$CREATED_BY"
fi

# Budget
BUDGET_NAME=$(cd "$TF_DIR" && terraform output -raw budget_name 2>/dev/null || echo "N/A")
if [ "$BUDGET_NAME" != "N/A" ]; then
    BUDGET_LIMIT=$(aws budgets describe-budget --account-id "$ACCOUNT_ID" --budget-name "$BUDGET_NAME" --query 'Budget.BudgetLimit.Amount' --output text 2>/dev/null || echo "N/A")
    printf "${BLUE}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "AWS" "Budget Alert" "Monthly limit: \$$BUDGET_LIMIT USD" "$BUDGET_NAME" "$(date +%Y-%m-%d)" "$CREATED_BY"
fi

# ═════════════════════════════════════════════════════════════════════════════
# ROSA CLUSTER
# ═════════════════════════════════════════════════════════════════════════════

# Check if rosa CLI is available
if command -v rosa &> /dev/null; then
    CLUSTER_INFO=$(rosa describe cluster -c "$CLUSTER_NAME" 2>/dev/null || echo "")
    
    if [ -n "$CLUSTER_INFO" ]; then
        CLUSTER_ID=$(echo "$CLUSTER_INFO" | grep "^ID:" | awk '{print $2}')
        CLUSTER_STATE=$(echo "$CLUSTER_INFO" | grep "^State:" | awk '{print $2}')
        OCP_VERSION=$(echo "$CLUSTER_INFO" | grep "^OpenShift Version:" | awk '{print $3}')
        API_URL=$(echo "$CLUSTER_INFO" | grep "^API URL:" | awk '{print $3}')
        CONSOLE_URL=$(echo "$CLUSTER_INFO" | grep "^Console URL:" | awk '{print $3}')
        CREATED_DATE=$(echo "$CLUSTER_INFO" | grep "^Created:" | awk '{print $2, $3, $4, $5, $6}')
        
        printf "${GREEN}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "ROSA" "HCP Cluster" "$CLUSTER_NAME (OCP $OCP_VERSION)" "$CLUSTER_ID" "$CREATED_DATE" "$CREATED_BY"
        printf "${GREEN}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "ROSA" "Cluster State" "$CLUSTER_STATE" "-" "-" "-"
        
        if [ -n "$API_URL" ] && [ "$API_URL" != "" ]; then
            printf "${GREEN}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "ROSA" "API Server" "Kubernetes API endpoint" "$API_URL" "-" "-"
        fi
        
        if [ -n "$CONSOLE_URL" ] && [ "$CONSOLE_URL" != "" ]; then
            printf "${GREEN}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "ROSA" "Console URL" "OpenShift Web Console" "$CONSOLE_URL" "-" "-"
        fi
        
        # Machine Pools
        MACHINE_POOLS=$(rosa list machinepools -c "$CLUSTER_NAME" 2>/dev/null | tail -n +2 || echo "")
        if [ -n "$MACHINE_POOLS" ]; then
            echo "$MACHINE_POOLS" | while IFS= read -r line; do
                POOL_NAME=$(echo "$line" | awk '{print $1}')
                POOL_TYPE=$(echo "$line" | awk '{print $3}')
                POOL_REPLICAS=$(echo "$line" | awk '{print $5}')
                printf "${GREEN}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "ROSA" "Machine Pool" "$POOL_NAME ($POOL_TYPE, $POOL_REPLICAS nodes)" "-" "-" "-"
            done
        fi
        
        # Ingress
        INGRESS_DOMAIN=$(echo "$CLUSTER_INFO" | grep "^DNS:" | awk '{print $2}')
        if [ -n "$INGRESS_DOMAIN" ]; then
            printf "${GREEN}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "ROSA" "Ingress Controller" "*.apps.rosa.$INGRESS_DOMAIN" "-" "-" "-"
        fi
    else
        printf "${YELLOW}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "ROSA" "Cluster" "No cluster found (destroyed or not deployed)" "-" "-" "-"
        printf "${YELLOW}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "ROSA" "Status" "Run ./scripts/deploy.sh to create cluster" "-" "-" "-"
    fi
else
    printf "${YELLOW}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "ROSA" "CLI" "rosa CLI not installed" "-" "-" "-"
fi

# ═════════════════════════════════════════════════════════════════════════════
# OPENSHIFT PLATFORM LAYER
# ═════════════════════════════════════════════════════════════════════════════

# Check if oc CLI is available and cluster is accessible
if command -v oc &> /dev/null; then
    # Test cluster connectivity
    oc whoami &> /dev/null
    OC_CONNECTED=$?
    
    if [ $OC_CONNECTED -eq 0 ]; then
        printf "${GREEN}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "OCP" "Platform Layer" "Cluster-scoped platform objects" "-" "-" "-"
        
        # Storage Classes
        STORAGE_CLASSES=$(oc get storageclass -o json 2>/dev/null | jq -r '.items[] | select(.metadata.name | test("efs|gp3|gp2")) | "\(.metadata.name)|\(.provisioner)|\(.metadata.annotations."storageclass.kubernetes.io/is-default-class" // "false")"' 2>/dev/null || echo "")
        
        if [ -n "$STORAGE_CLASSES" ]; then
            echo "$STORAGE_CLASSES" | while IFS='|' read -r sc_name provisioner is_default; do
                SC_TYPE=""
                SC_DESC=""
                
                case $sc_name in
                    *efs*)
                        SC_TYPE="EFS CSI Driver"
                        SC_DESC="ReadWriteMany · multi-pod shared"
                        ;;
                    *gp3*)
                        SC_TYPE="EBS CSI Driver"
                        SC_DESC="ReadWriteOnce · per-pod"
                        [ "$is_default" = "true" ] && SC_DESC="$SC_DESC (default)"
                        ;;
                    *gp2*)
                        SC_TYPE="EBS CSI Driver (legacy)"
                        SC_DESC="ReadWriteOnce · per-pod"
                        [ "$is_default" = "true" ] && SC_DESC="$SC_DESC (default)"
                        ;;
                    *)
                        SC_TYPE="$provisioner"
                        SC_DESC="Custom storage class"
                        ;;
                esac
                
                printf "${GREEN}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "OCP" "StorageClass" "$sc_name · $SC_TYPE" "$SC_DESC" "-" "-"
            done
        fi
        
        # Security Context Constraints (SCCs)
        SCCS=$(oc get scc -o json 2>/dev/null | jq -r '.items[] | select(.metadata.name | test("restricted-v2|anyuid|privileged|hostnetwork")) | "\(.metadata.name)|\(.priority // "null")|\(.allowPrivilegedContainer // false)"' 2>/dev/null || echo "")
        
        if [ -n "$SCCS" ]; then
            echo "$SCCS" | while IFS='|' read -r scc_name priority privileged; do
                SCC_DESC=""
                
                case $scc_name in
                    restricted-v2)
                        SCC_DESC="Default · blocks runAsUser/fsGroup/root"
                        ;;
                    anyuid)
                        SCC_DESC="Allows any UID · no root privilege"
                        ;;
                    privileged)
                        SCC_DESC="Full host access · cluster-admin only"
                        ;;
                    hostnetwork)
                        SCC_DESC="Host network access · monitoring/ingress"
                        ;;
                    *)
                        SCC_DESC="Priority: $priority"
                        ;;
                esac
                
                printf "${GREEN}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "OCP" "SCC" "$scc_name" "$SCC_DESC" "-" "-"
            done
        fi
        
        # Cluster Operators (key platform components)
        KEY_OPERATORS="authentication console ingress image-registry storage monitoring dns network"
        for op in $KEY_OPERATORS; do
            OP_STATUS=$(oc get clusteroperator "$op" -o json 2>/dev/null | jq -r '.status.conditions[] | select(.type=="Available") | .status' 2>/dev/null || echo "Unknown")
            OP_VERSION=$(oc get clusteroperator "$op" -o json 2>/dev/null | jq -r '.status.versions[]? | select(.name=="operator") | .version' 2>/dev/null || echo "N/A")
            
            if [ "$OP_STATUS" = "True" ]; then
                OP_DESC="Available"
                case $op in
                    authentication)
                        OP_DESC="OAuth · RBAC · cluster-admin"
                        ;;
                    console)
                        OP_DESC="Web UI · developer/admin perspectives"
                        ;;
                    ingress)
                        OP_DESC="Router · *.apps domain · NLB"
                        ;;
                    image-registry)
                        OP_DESC="Internal registry · S3-backed"
                        ;;
                    storage)
                        OP_DESC="CSI drivers · EBS + EFS provisioners"
                        ;;
                    monitoring)
                        OP_DESC="Prometheus · Grafana · Alertmanager"
                        ;;
                    dns)
                        OP_DESC="CoreDNS · cluster.local resolution"
                        ;;
                    network)
                        OP_DESC="OVN-Kubernetes · pod networking"
                        ;;
                esac
                printf "${GREEN}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "OCP" "ClusterOperator" "$op" "$OP_DESC" "-" "-"
            fi
        done
        
        # Namespaces (key platform namespaces only)
        KEY_NAMESPACES="openshift-authentication openshift-console openshift-ingress openshift-image-registry openshift-monitoring openshift-storage"
        for ns in $KEY_NAMESPACES; do
            NS_EXISTS=$(oc get namespace "$ns" -o name 2>/dev/null || echo "")
            if [ -n "$NS_EXISTS" ]; then
                NS_CREATED=$(oc get namespace "$ns" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null | cut -d'T' -f1 || echo "N/A")
                NS_DESC=""
                case $ns in
                    openshift-authentication)
                        NS_DESC="OAuth server · identity providers"
                        ;;
                    openshift-console)
                        NS_DESC="Web console pods"
                        ;;
                    openshift-ingress)
                        NS_DESC="Router pods · ingress controllers"
                        ;;
                    openshift-image-registry)
                        NS_DESC="Internal registry pods"
                        ;;
                    openshift-monitoring)
                        NS_DESC="Prometheus · Grafana · Alertmanager"
                        ;;
                    openshift-storage)
                        NS_DESC="CSI driver pods · storage operators"
                        ;;
                esac
                printf "${GREEN}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "OCP" "Namespace" "$ns" "$NS_DESC" "$NS_CREATED" "-"
            fi
        done
        
    else
        printf "${YELLOW}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "OCP" "Platform" "Not logged in to cluster" "-" "-" "-"
        printf "${YELLOW}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "OCP" "Hint" "Run: oc login <API-URL>" "-" "-" "-"
    fi
else
    printf "${YELLOW}%-25s${NC} %-35s %-45s %-35s %-20s %-15s\n" "OCP" "CLI" "oc CLI not installed" "-" "-" "-"
fi

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Resource inventory complete${NC}"
echo ""
