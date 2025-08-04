#!/bin/bash

# Enhanced GitOps Repository Validation Script
echo "🔍 Enhanced GitOps Repository Validation Report"
echo "=============================================="

# Set color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Initialize error counters
ERRORS=0
WARNINGS=0

# Function to log errors
log_error() {
    echo -e "${RED}❌ ERROR:${NC} $1"
    ((ERRORS++))
}

# Function to log warnings
log_warning() {
    echo -e "${YELLOW}⚠️  WARNING:${NC} $1"
    ((WARNINGS++))
}

# Function to log success
log_success() {
    echo -e "${GREEN}✅${NC} $1"
}

# Function to log info
log_info() {
    echo -e "${BLUE}ℹ️${NC} $1"
}

# Check YAML syntax
echo -e "\n📏 Checking YAML Syntax and Structure..."
for file in $(find . -name "*.yaml" -o -name "*.yml"); do
    if ! python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
        log_error "Invalid YAML syntax in $file"
    fi
done

# Check for consistent indentation (should be 2 spaces)
echo -e "\n📐 Checking YAML Indentation..."
inconsistent_files=$(find . -name "*.yaml" -exec grep -l "^\s\{3\}\w\|^\s\{5\}\w\|^\s\{7\}\w" {} \; 2>/dev/null)
if [ -n "$inconsistent_files" ]; then
    log_warning "Files with inconsistent indentation found:"
    echo "$inconsistent_files" | while read file; do
        echo "  - $file"
    done
else
    log_success "All YAML files have consistent 2-space indentation"
fi

# Check for missing namespaces
echo -e "\n🏷️  Checking Namespace Declarations..."
missing_ns_files=""
for file in $(find apps/ secrets/ rollouts/ -name "*.yaml" 2>/dev/null); do
    if [ -f "$file" ] && ! grep -q "namespace:" "$file"; then
        missing_ns_files="$missing_ns_files $file"
    fi
done
if [ -n "$missing_ns_files" ]; then
    log_warning "Files missing namespace declarations:"
    echo "$missing_ns_files" | tr ' ' '\n' | while read file; do
        [ -n "$file" ] && echo "  - $file"
    done
else
    log_success "All resource files have namespace declarations"
fi

# Check for security contexts
echo -e "\n🔒 Checking Security Contexts..."
insecure_files=""
for file in $(find apps/ rollouts/ -name "deployment.yaml" -o -name "*rollout.yaml" 2>/dev/null); do
    if [ -f "$file" ] && ! grep -q "securityContext:" "$file"; then
        insecure_files="$insecure_files $file"
    fi
done
if [ -n "$insecure_files" ]; then
    log_warning "Files missing security contexts:"
    echo "$insecure_files" | tr ' ' '\n' | while read file; do
        [ -n "$file" ] && echo "  - $file"
    done
else
    log_success "All deployments have security contexts configured"
fi

# Check for resource requests and limits
echo -e "\n💾 Checking Resource Requests and Limits..."
missing_resources=""
for file in $(find apps/ rollouts/ -name "deployment.yaml" -o -name "*rollout.yaml" 2>/dev/null); do
    if [ -f "$file" ]; then
        if ! grep -q "resources:" "$file" || ! grep -q "requests:" "$file" || ! grep -q "limits:" "$file"; then
            missing_resources="$missing_resources $file"
        fi
    fi
done
if [ -n "$missing_resources" ]; then
    log_warning "Files missing complete resource specifications:"
    echo "$missing_resources" | tr ' ' '\n' | while read file; do
        [ -n "$file" ] && echo "  - $file"
    done
else
    log_success "All deployments have complete resource specifications"
fi

# Check for service accounts
echo -e "\n👤 Checking Service Accounts..."
missing_sa=""
for file in $(find apps/ rollouts/ -name "deployment.yaml" -o -name "*rollout.yaml" 2>/dev/null); do
    if [ -f "$file" ] && ! grep -q "serviceAccountName:" "$file"; then
        missing_sa="$missing_sa $file"
    fi
done
if [ -n "$missing_sa" ]; then
    log_warning "Files missing serviceAccountName:"
    echo "$missing_sa" | tr ' ' '\n' | while read file; do
        [ -n "$file" ] && echo "  - $file"
    done
else
    log_success "All deployments have service accounts configured"
fi

# Check ArgoCD Application structure
echo -e "\n🚀 Checking ArgoCD Applications..."
app_issues=""
for file in $(find argocd/apps/ -name "*.yaml" 2>/dev/null); do
    if [ -f "$file" ]; then
        if ! grep -q "syncPolicy:" "$file"; then
            app_issues="$app_issues $file(missing_syncPolicy)"
        fi
        if ! grep -q "project:" "$file"; then
            app_issues="$app_issues $file(missing_project)"
        fi
        if ! grep -q "finalizers:" "$file"; then
            app_issues="$app_issues $file(missing_finalizers)"
        fi
    fi
done
if [ -n "$app_issues" ]; then
    log_warning "ArgoCD application issues found:"
    echo "$app_issues" | tr ' ' '\n' | while read issue; do
        [ -n "$issue" ] && echo "  - $issue"
    done
else
    log_success "All ArgoCD applications properly configured"
fi

# Check for Kustomization files
echo -e "\n📦 Checking Kustomization Files..."
missing_kustomization=""
for dir in $(find apps/ -type d -name base -o -name overlays 2>/dev/null); do
    if [ -d "$dir" ] && [ ! -f "$dir/kustomization.yaml" ] && [ ! -f "$dir/kustomization.yml" ]; then
        missing_kustomization="$missing_kustomization $dir"
    fi
done
if [ -n "$missing_kustomization" ]; then
    log_warning "Directories missing kustomization files:"
    echo "$missing_kustomization" | tr ' ' '\n' | while read dir; do
        [ -n "$dir" ] && echo "  - $dir"
    done
else
    log_success "All required directories have kustomization files"
fi

# Check for health checks
echo -e "\n🏥 Checking Health Probes..."
missing_probes=""
for file in $(find apps/ rollouts/ -name "deployment.yaml" -o -name "*rollout.yaml" 2>/dev/null); do
    if [ -f "$file" ]; then
        if ! grep -q "readinessProbe:" "$file" || ! grep -q "livenessProbe:" "$file"; then
            missing_probes="$missing_probes $file"
        fi
    fi
done
if [ -n "$missing_probes" ]; then
    log_warning "Files missing health probes:"
    echo "$missing_probes" | tr ' ' '\n' | while read file; do
        [ -n "$file" ] && echo "  - $file"
    done
else
    log_success "All deployments have health probes configured"
fi

# Check for proper labels
echo -e "\n🏷️  Checking Standard Labels..."
missing_labels=""
for file in $(find apps/ -name "*.yaml" 2>/dev/null); do
    if [ -f "$file" ] && grep -q "kind: Deployment\|kind: Service\|kind: ConfigMap" "$file"; then
        if ! grep -q "app:" "$file" || ! grep -q "environment:" "$file"; then
            missing_labels="$missing_labels $file"
        fi
    fi
done
if [ -n "$missing_labels" ]; then
    log_warning "Files missing standard labels (app, environment):"
    echo "$missing_labels" | tr ' ' '\n' | while read file; do
        [ -n "$file" ] && echo "  - $file"
    done
else
    log_success "All resources have standard labels"
fi

# Summary
echo -e "\n📊 Validation Summary"
echo "===================="
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    log_success "Repository is properly configured and follows best practices!"
    echo -e "${GREEN}🎉 No issues found!${NC}"
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Found $WARNINGS warnings - consider addressing them${NC}"
else
    echo -e "${RED}❌ Found $ERRORS errors and $WARNINGS warnings - please fix before deployment${NC}"
fi

echo -e "\n📁 Repository Structure:"
if command -v tree &> /dev/null; then
    tree -I '.git|node_modules|.vscode' -L 3
else
    find . -type d -not -path '*/\.*' | head -20 | sed 's|[^/]*/|  |g'
fi

echo -e "\n📋 Configuration Files Found:"
echo "ArgoCD Applications: $(find argocd/apps/ -name "*.yaml" 2>/dev/null | wc -l)"
echo "Kustomization Files: $(find . -name "kustomization.yaml" 2>/dev/null | wc -l)"
echo "Deployment Files: $(find apps/ -name "deployment.yaml" 2>/dev/null | wc -l)"
echo "Service Files: $(find apps/ -name "service.yaml" 2>/dev/null | wc -l)"
echo "Secret Files: $(find secrets/ -name "*.yaml" 2>/dev/null | wc -l)"
echo "Rollout Files: $(find rollouts/ -name "*rollout.yaml" 2>/dev/null | wc -l)"

exit $ERRORS
