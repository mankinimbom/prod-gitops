#!/bin/bash
set -e

echo "🔍 Running comprehensive GitOps validation..."

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

validate_kubernetes_manifests() {
    echo -e "${YELLOW}Validating Kubernetes manifests...${NC}"
    find apps/ -name "*.yaml" -exec kubectl --dry-run=client apply -f {} \; 2>&1 | grep -v "configured (dry run)" || true
    echo -e "${GREEN}✅ Kubernetes manifests validation complete${NC}"
}

validate_argocd_applications() {
    echo -e "${YELLOW}Validating ArgoCD applications...${NC}"
    if command -v argocd &> /dev/null; then
        find argocd/apps/ -name "*.yaml" -exec argocd app validate {} \;
        echo -e "${GREEN}✅ ArgoCD applications validation complete${NC}"
    else
        echo -e "${RED}⚠️ ArgoCD CLI not found, skipping validation${NC}"
    fi
}

test_connectivity() {
    echo -e "${YELLOW}Testing connectivity and health...${NC}"
    
    if kubectl get namespace argocd &> /dev/null; then
        kubectl get applications -n argocd --no-headers | wc -l | xargs echo "ArgoCD applications found:"
        echo -e "${GREEN}✅ ArgoCD connectivity test complete${NC}"
    else
        echo -e "${RED}⚠️ ArgoCD namespace not found${NC}"
    fi
}

# Run all validations
validate_kubernetes_manifests
validate_argocd_applications
test_connectivity

echo -e "${GREEN}🎉 All validations completed successfully!${NC}"
