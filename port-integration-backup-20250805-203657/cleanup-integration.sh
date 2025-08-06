#!/bin/bash

# Port.io Integration Cleanup Script
# Removes redundant files while keeping essential components

set -e

echo "🧹 Cleaning up Port.io Integration directory..."
echo "=============================================="

# Check if we're in the right directory
if [ ! -f "port-blueprints-actions.yaml" ]; then
    echo "❌ Error: Not in port-integration directory"
    echo "Please run this script from: prod-gitops/port-integration/"
    exit 1
fi

# Backup before cleanup
echo "📋 Creating backup..."
mkdir -p ../port-integration-backup-$(date +%Y%m%d-%H%M%S)
cp -r . ../port-integration-backup-$(date +%Y%m%d-%H%M%S)/

echo "🗑️  Removing redundant files..."

# Remove redundant documentation
if [ -f "AUTOPILOT-COMPLETE.md" ]; then
    rm AUTOPILOT-COMPLETE.md
    echo "   ✅ Removed AUTOPILOT-COMPLETE.md"
fi

if [ -f "INTEGRATION_COMPLETE.md" ]; then
    rm INTEGRATION_COMPLETE.md
    echo "   ✅ Removed INTEGRATION_COMPLETE.md"
fi

if [ -f "STATUS.md" ]; then
    rm STATUS.md
    echo "   ✅ Removed STATUS.md"
fi

if [ -f "use-case-example.md" ]; then
    rm use-case-example.md
    echo "   ✅ Removed use-case-example.md"
fi

# Remove duplicate/old files
if [ -f "argocd-integration-fixed.yaml" ]; then
    rm argocd-integration-fixed.yaml
    echo "   ✅ Removed argocd-integration-fixed.yaml (duplicate)"
fi

if [ -f "deploy-integration.sh" ]; then
    rm deploy-integration.sh
    echo "   ✅ Removed deploy-integration.sh (replaced by enhanced version)"
fi

if [ -f "setup-port-helm-charts.sh" ]; then
    rm setup-port-helm-charts.sh
    echo "   ✅ Removed setup-port-helm-charts.sh (replaced by enhanced version)"
fi

# Remove Autopilot files (optional - keep if you want to use Autopilot later)
read -p "🤔 Do you want to remove ArgoCD Autopilot files? (y/N): " remove_autopilot
if [[ $remove_autopilot =~ ^[Yy]$ ]]; then
    if [ -f "argocd-autopilot.md" ]; then
        rm argocd-autopilot.md
        echo "   ✅ Removed argocd-autopilot.md"
    fi
    
    if [ -f "setup-autopilot.sh" ]; then
        rm setup-autopilot.sh
        echo "   ✅ Removed setup-autopilot.sh"
    fi
else
    echo "   ⏭️  Keeping Autopilot files for future use"
fi

echo ""
echo "📊 Remaining Essential Files:"
echo "============================="

# List essential files
echo "✅ Core Integration:"
[ -f "port-blueprints-actions.yaml" ] && echo "   📄 port-blueprints-actions.yaml"
[ -f "port-gitops-controller.yaml" ] && echo "   📄 port-gitops-controller.yaml"
[ -f "argocd-integration.yaml" ] && echo "   📄 argocd-integration.yaml"
[ -d "controller" ] && echo "   📂 controller/"

echo ""
echo "✅ Deployment & Configuration:"
[ -f "deploy-port-helm-enhanced.sh" ] && echo "   📄 deploy-port-helm-enhanced.sh"
[ -f "values-k8s-exporter.yaml" ] && echo "   📄 values-k8s-exporter.yaml"
[ -f "values-argocd-ocean.yaml" ] && echo "   📄 values-argocd-ocean.yaml"

echo ""
echo "✅ Documentation:"
[ -f "README.md" ] && echo "   📄 README.md"
[ -f "HELM-SETUP-GUIDE.md" ] && echo "   📄 HELM-SETUP-GUIDE.md"
[ -f "rbac-security.md" ] && echo "   📄 rbac-security.md"
[ -f "CLEANUP-GUIDE.md" ] && echo "   📄 CLEANUP-GUIDE.md"

echo ""
echo "✅ Optional (if kept):"
[ -f "argocd-autopilot.md" ] && echo "   📄 argocd-autopilot.md"
[ -f "setup-autopilot.sh" ] && echo "   📄 setup-autopilot.sh"

echo ""
echo "🎉 Cleanup Complete!"
echo "=================="
echo ""
echo "📁 Your streamlined port-integration directory now contains:"
echo "   • $(find . -maxdepth 1 -type f | wc -l) files (down from 20+)"
echo "   • All essential components preserved"
echo "   • Backup created in ../port-integration-backup-*"
echo ""
echo "🚀 Ready to deploy with:"
echo "   ./deploy-port-helm-enhanced.sh"
echo ""
echo "💡 Your GitHub Actions workflows are correctly placed in:"
echo "   • backend/.github/workflows/"
echo "   • frontend/.github/workflows/"
