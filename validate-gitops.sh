#!/bin/bash

# Comprehensive GitOps Repository Validation Script
echo "🔍 GitOps Repository Validation Report"
echo "======================================"

# Check for consistent indentation (should be 2 spaces)
echo "📏 Checking YAML Indentation..."
find . -name "*.yaml" -exec grep -l "^\s\{3\}\w\|^\s\{5\}\w\|^\s\{7\}\w" {} \; > /tmp/bad_indent.txt
if [ -s /tmp/bad_indent.txt ]; then
    echo "⚠️  Files with inconsistent indentation found:"
    cat /tmp/bad_indent.txt
else
    echo "✅ All YAML files have consistent 2-space indentation"
fi

# Check for missing namespaces
echo -e "\n🏷️  Checking Namespace Declarations..."
missing_ns_files=""
for file in $(find apps/ secrets/ rollouts/ -name "*.yaml"); do
    if ! grep -q "namespace:" "$file"; then
        missing_ns_files="$missing_ns_files $file"
    fi
done
if [ -n "$missing_ns_files" ]; then
    echo "⚠️  Files missing namespace declarations:$missing_ns_files"
else
    echo "✅ All resource files have namespace declarations"
fi

# Check for security contexts
echo -e "\n🔒 Checking Security Contexts..."
insecure_files=""
for file in $(find apps/ rollouts/ -name "deployment.yaml" -o -name "*rollout.yaml"); do
    if ! grep -q "securityContext:" "$file"; then
        insecure_files="$insecure_files $file"
    fi
done
if [ -n "$insecure_files" ]; then
    echo "⚠️  Files missing security contexts:$insecure_files"
else
    echo "✅ All deployments have security contexts configured"
fi

# Check for resource requests
echo -e "\n💾 Checking Resource Requests..."
missing_resources=""
for file in $(find apps/ rollouts/ -name "deployment.yaml" -o -name "*rollout.yaml"); do
    if ! grep -q "ephemeral-storage:" "$file"; then
        missing_resources="$missing_resources $file"
    fi
done
if [ -n "$missing_resources" ]; then
    echo "⚠️  Files missing ephemeral storage requests:$missing_resources"
else
    echo "✅ All deployments have complete resource requests"
fi

# Check ArgoCD Application structure
echo -e "\n🚀 Checking ArgoCD Applications..."
app_issues=""
for file in $(find argocd/apps/ -name "*.yaml"); do
    if ! grep -q "syncPolicy:" "$file"; then
        app_issues="$app_issues $file(missing_syncPolicy)"
    fi
    if ! grep -q "project:" "$file"; then
        app_issues="$app_issues $file(missing_project)"
    fi
done
if [ -n "$app_issues" ]; then
    echo "⚠️  ArgoCD application issues: $app_issues"
else
    echo "✅ All ArgoCD applications properly configured"
fi

# Summary
echo -e "\n📊 Validation Summary"
echo "===================="
if [ -z "$missing_ns_files" ] && [ -z "$insecure_files" ] && [ -z "$missing_resources" ] && [ -z "$app_issues" ]; then
    echo "✅ Repository is properly configured and follows best practices!"
else
    echo "⚠️  Some issues found - review the details above"
fi

echo -e "\n📁 Repository Structure:"
tree -I '.git|node_modules' || find . -type d | head -20
