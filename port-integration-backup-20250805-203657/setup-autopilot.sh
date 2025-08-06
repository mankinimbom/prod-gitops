#!/bin/bash

# ArgoCD Autopilot Bootstrap Script
# This script sets up ArgoCD Autopilot for automated GitOps repository management

set -e

echo "🚀 Setting up ArgoCD Autopilot for Port.io Integration"

# Configuration
GIT_ORG="your-org"
GIT_REPO_NAME="gitops-bootstrap"
GIT_REPO_URL="https://github.com/${GIT_ORG}/${GIT_REPO_NAME}"
ARGOCD_SERVER="argo.annkinimbom.com"

# Check prerequisites
check_prerequisites() {
    echo "📋 Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        echo "❌ kubectl is required but not installed"
        exit 1
    fi
    
    if ! command -v git &> /dev/null; then
        echo "❌ git is required but not installed"
        exit 1
    fi
    
    if [ -z "$GIT_TOKEN" ]; then
        echo "❌ GIT_TOKEN environment variable is required"
        echo "   Export your GitHub Personal Access Token:"
        echo "   export GIT_TOKEN='your-github-token'"
        exit 1
    fi
    
    echo "✅ Prerequisites check passed"
}

# Install ArgoCD Autopilot
install_autopilot() {
    echo "📦 Installing ArgoCD Autopilot..."
    
    if command -v argocd-autopilot &> /dev/null; then
        echo "✅ ArgoCD Autopilot already installed"
        argocd-autopilot version
        return
    fi
    
    # Detect architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    
    # Download and install
    curl -L --output - "https://github.com/argoproj-labs/argocd-autopilot/releases/latest/download/argocd-autopilot-linux-${ARCH}.tar.gz" | tar zx
    sudo mv ./argocd-autopilot-* /usr/local/bin/argocd-autopilot
    chmod +x /usr/local/bin/argocd-autopilot
    
    echo "✅ ArgoCD Autopilot installed successfully"
    argocd-autopilot version
}

# Create or update GitOps repository
setup_gitops_repo() {
    echo "🔧 Setting up GitOps repository: $GIT_REPO_URL"
    
    # Check if repo exists
    if git ls-remote "$GIT_REPO_URL" &> /dev/null; then
        echo "✅ Repository $GIT_REPO_URL already exists"
    else
        echo "📝 Repository does not exist. Please create it manually at:"
        echo "   https://github.com/new"
        echo "   Repository name: $GIT_REPO_NAME"
        echo "   Organization: $GIT_ORG"
        read -p "Press Enter when repository is created..."
    fi
}

# Bootstrap ArgoCD with Autopilot
bootstrap_argocd() {
    echo "🔄 Bootstrapping ArgoCD with Autopilot..."
    
    # Check if already bootstrapped
    if kubectl get application autopilot-bootstrap -n argocd &> /dev/null; then
        echo "✅ ArgoCD already bootstrapped with Autopilot"
        return
    fi
    
    # Bootstrap the repository
    argocd-autopilot repo bootstrap \
        --repo "$GIT_REPO_URL" \
        --git-token "$GIT_TOKEN" \
        --argocd-server "$ARGOCD_SERVER" \
        --insecure \
        --provider github
    
    echo "✅ ArgoCD bootstrapped successfully"
}

# Create projects
create_projects() {
    echo "📁 Creating ArgoCD projects..."
    
    # Create microservices project
    if ! argocd-autopilot project list | grep -q "microservices"; then
        argocd-autopilot project create microservices \
            --git-token "$GIT_TOKEN" \
            --repo "$GIT_REPO_URL"
        echo "✅ Created microservices project"
    else
        echo "✅ Microservices project already exists"
    fi
    
    # Create port-integration project
    if ! argocd-autopilot project list | grep -q "port-integration"; then
        argocd-autopilot project create port-integration \
            --git-token "$GIT_TOKEN" \
            --repo "$GIT_REPO_URL"
        echo "✅ Created port-integration project"
    else
        echo "✅ Port-integration project already exists"
    fi
}

# Setup Port.io system application
setup_port_system() {
    echo "🔧 Setting up Port.io system application..."
    
    # Create temporary directory for manifests
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Clone the gitops repository
    git clone "$GIT_REPO_URL" .
    
    # Create port-system app directory
    mkdir -p apps/platform/port-system
    
    # Create port-system application manifest
    cat > apps/platform/port-system/app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: port-system
  namespace: argocd
  labels:
    autopilot.argoproj.io/app-name: port-system
    managed-by: autopilot
  annotations:
    autopilot.argoproj.io/git-path: apps/platform/port-system
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: port-integration
  source:
    repoURL: $GIT_REPO_URL
    path: apps/platform/port-system/manifests
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: port-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
    
    # Create manifests directory with Port.io resources
    mkdir -p apps/platform/port-system/manifests
    
    # Copy Port.io manifests
    cp "$OLDPWD/port-integration/port-blueprints-actions.yaml" apps/platform/port-system/manifests/
    cp "$OLDPWD/port-integration/port-gitops-controller.yaml" apps/platform/port-system/manifests/
    
    # Create kustomization
    cat > apps/platform/port-system/manifests/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- port-blueprints-actions.yaml
- port-gitops-controller.yaml

namespace: port-system
EOF
    
    # Commit and push
    git add .
    git commit -m "Add Port.io system application via Autopilot"
    git push origin HEAD
    
    # Create the application via Autopilot
    argocd-autopilot app create port-system \
        --app "./apps/platform/port-system" \
        --project port-integration \
        --git-token "$GIT_TOKEN"
    
    echo "✅ Port.io system application created"
    
    # Cleanup
    cd "$OLDPWD"
    rm -rf "$TEMP_DIR"
}

# Verify installation
verify_installation() {
    echo "🔍 Verifying installation..."
    
    # Check ArgoCD applications
    echo "📱 ArgoCD Applications:"
    kubectl get applications -n argocd
    
    # Check projects
    echo "📁 ArgoCD Projects:"
    kubectl get appprojects -n argocd
    
    # Check Port.io system
    echo "🔧 Port.io System:"
    kubectl get pods -n port-system
    
    echo "✅ Installation verification complete"
}

# Main execution
main() {
    echo "🎯 Starting ArgoCD Autopilot setup for Port.io integration"
    echo "=================================================="
    
    check_prerequisites
    install_autopilot
    setup_gitops_repo
    bootstrap_argocd
    create_projects
    setup_port_system
    verify_installation
    
    echo ""
    echo "🎉 ArgoCD Autopilot setup complete!"
    echo "=================================================="
    echo "📊 Summary:"
    echo "   • ArgoCD Autopilot: Installed and configured"
    echo "   • GitOps Repository: $GIT_REPO_URL"
    echo "   • Projects Created: microservices, port-integration"
    echo "   • Port.io System: Deployed via Autopilot"
    echo ""
    echo "🔗 Access Points:"
    echo "   • ArgoCD UI: http://$ARGOCD_SERVER"
    echo "   • GitOps Repo: $GIT_REPO_URL"
    echo ""
    echo "📝 Next Steps:"
    echo "   1. Configure Port.io credentials in secrets"
    echo "   2. Import Port.io blueprints and actions"
    echo "   3. Start creating microservices via Port.io"
    echo ""
    echo "🛠️ Useful Commands:"
    echo "   • List projects: argocd-autopilot project list"
    echo "   • List apps: argocd-autopilot app list"
    echo "   • Create app: argocd-autopilot app create <name> --app <path> --project <project>"
}

# Execute main function
main "$@"
