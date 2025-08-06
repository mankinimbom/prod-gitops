#!/bin/bash
# ArgoCD Autopilot Setup Script for Port.io Integration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_URL="${AUTOPILOT_REPO_URL:-https://github.com/your-org/gitops-bootstrap}"
ARGOCD_SERVER="${ARGOCD_SERVER:-argo.annkinimbom.com}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
PORT_NAMESPACE="${PORT_NAMESPACE:-port-system}"

# Required environment variables
REQUIRED_VARS=("GIT_TOKEN")

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check required environment variables
    for var in "${REQUIRED_VARS[@]}"; do
        if [[ -z "${!var}" ]]; then
            log_error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if ArgoCD CLI is available
    if ! command -v argocd &> /dev/null; then
        log_warning "ArgoCD CLI not found. Some operations may require manual intervention."
    fi
    
    log_success "Prerequisites check passed"
}

# Install ArgoCD Autopilot
install_autopilot() {
    if command -v argocd-autopilot &> /dev/null; then
        log_info "ArgoCD Autopilot is already installed"
        return
    fi
    
    log_info "Installing ArgoCD Autopilot..."
    
    # Determine OS and architecture
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            log_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
    
    # Download and install
    AUTOPILOT_URL="https://github.com/argoproj-labs/argocd-autopilot/releases/latest/download/argocd-autopilot-${OS}-${ARCH}.tar.gz"
    
    curl -L --output - "$AUTOPILOT_URL" | tar zx
    sudo mv ./argocd-autopilot-* /usr/local/bin/argocd-autopilot
    chmod +x /usr/local/bin/argocd-autopilot
    
    log_success "ArgoCD Autopilot installed successfully"
}

# Setup ArgoCD Autopilot repository
bootstrap_repository() {
    log_info "Bootstrapping ArgoCD Autopilot repository..."
    
    # Check if repository is already bootstrapped
    if argocd-autopilot repo get --repo "$REPO_URL" --git-token "$GIT_TOKEN" &> /dev/null; then
        log_info "Repository is already bootstrapped"
        return
    fi
    
    # Bootstrap the repository
    argocd-autopilot repo bootstrap \
        --repo "$REPO_URL" \
        --git-token "$GIT_TOKEN" \
        --argocd-server "$ARGOCD_SERVER" \
        --insecure \
        --namespace "$ARGOCD_NAMESPACE"
    
    log_success "Repository bootstrapped successfully"
}

# Create projects
create_projects() {
    log_info "Creating ArgoCD projects..."
    
    local projects=("microservices" "port-integration" "platform")
    
    for project in "${projects[@]}"; do
        log_info "Creating project: $project"
        
        if argocd-autopilot project get "$project" --git-token "$GIT_TOKEN" &> /dev/null; then
            log_info "Project $project already exists"
            continue
        fi
        
        argocd-autopilot project create "$project" \
            --git-token "$GIT_TOKEN" \
            --repo "$REPO_URL"
        
        log_success "Project $project created successfully"
    done
}

# Create bootstrap applications
create_bootstrap_apps() {
    log_info "Creating bootstrap applications..."
    
    # Port.io System Application
    if ! argocd-autopilot app get port-system --git-token "$GIT_TOKEN" &> /dev/null; then
        log_info "Creating Port.io system application..."
        
        argocd-autopilot app create port-system \
            --app ./apps/platform/port-system \
            --project port-integration \
            --git-token "$GIT_TOKEN" \
            --repo "$REPO_URL"
        
        log_success "Port.io system application created"
    else
        log_info "Port.io system application already exists"
    fi
    
    # Monitoring Application
    if ! argocd-autopilot app get monitoring --git-token "$GIT_TOKEN" &> /dev/null; then
        log_info "Creating monitoring application..."
        
        argocd-autopilot app create monitoring \
            --app ./apps/platform/monitoring \
            --project platform \
            --git-token "$GIT_TOKEN" \
            --repo "$REPO_URL"
        
        log_success "Monitoring application created"
    else
        log_info "Monitoring application already exists"
    fi
}

# Setup namespace and RBAC
setup_namespaces() {
    log_info "Setting up namespaces and RBAC..."
    
    # Create namespaces if they don't exist
    local namespaces=("$ARGOCD_NAMESPACE" "$PORT_NAMESPACE" "dev" "staging" "prod")
    
    for ns in "${namespaces[@]}"; do
        if ! kubectl get namespace "$ns" &> /dev/null; then
            kubectl create namespace "$ns"
            log_success "Created namespace: $ns"
        else
            log_info "Namespace $ns already exists"
        fi
    done
    
    # Apply RBAC for Port.io integration
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: port-gitops-controller
  namespace: $PORT_NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: port-gitops-controller
rules:
- apiGroups: ["argoproj.io"]
  resources: ["applications", "applicationsets", "appprojects"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list", "create", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: port-gitops-controller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: port-gitops-controller
subjects:
- kind: ServiceAccount
  name: port-gitops-controller
  namespace: $PORT_NAMESPACE
EOF
    
    log_success "RBAC configuration applied"
}

# Verify installation
verify_installation() {
    log_info "Verifying ArgoCD Autopilot installation..."
    
    # Check Autopilot CLI
    if ! command -v argocd-autopilot &> /dev/null; then
        log_error "ArgoCD Autopilot CLI is not available"
        return 1
    fi
    
    # Check repository status
    if ! argocd-autopilot repo get --repo "$REPO_URL" --git-token "$GIT_TOKEN" &> /dev/null; then
        log_error "Repository is not properly bootstrapped"
        return 1
    fi
    
    # Check projects
    local projects=("microservices" "port-integration" "platform")
    for project in "${projects[@]}"; do
        if ! argocd-autopilot project get "$project" --git-token "$GIT_TOKEN" &> /dev/null; then
            log_error "Project $project not found"
            return 1
        fi
    done
    
    # Check ArgoCD applications
    kubectl get applications -n "$ARGOCD_NAMESPACE" -l app.kubernetes.io/part-of=argocd-autopilot
    
    log_success "ArgoCD Autopilot installation verified successfully"
}

# Display usage information
show_usage() {
    cat << EOF
ArgoCD Autopilot Setup Script for Port.io Integration

Usage: $0 [OPTIONS]

Environment Variables:
  GIT_TOKEN             GitHub token with repository access (required)
  AUTOPILOT_REPO_URL    GitOps repository URL (default: https://github.com/your-org/gitops-bootstrap)
  ARGOCD_SERVER         ArgoCD server URL (default: argo.annkinimbom.com)
  ARGOCD_NAMESPACE      ArgoCD namespace (default: argocd)
  PORT_NAMESPACE        Port.io namespace (default: port-system)

Options:
  --help               Show this help message
  --verify-only        Only verify existing installation
  --bootstrap-only     Only bootstrap repository
  --dry-run           Show what would be done without executing

Examples:
  # Full setup
  export GIT_TOKEN="ghp_xxxxxxxxxxxx"
  $0

  # Verify existing installation
  $0 --verify-only

  # Bootstrap repository only
  $0 --bootstrap-only

EOF
}

# Main execution
main() {
    local verify_only=false
    local bootstrap_only=false
    local dry_run=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                show_usage
                exit 0
                ;;
            --verify-only)
                verify_only=true
                shift
                ;;
            --bootstrap-only)
                bootstrap_only=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Show configuration
    log_info "Configuration:"
    log_info "  Repository URL: $REPO_URL"
    log_info "  ArgoCD Server: $ARGOCD_SERVER"
    log_info "  ArgoCD Namespace: $ARGOCD_NAMESPACE"
    log_info "  Port.io Namespace: $PORT_NAMESPACE"
    echo
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "DRY RUN MODE - No changes will be made"
        return 0
    fi
    
    if [[ "$verify_only" == "true" ]]; then
        verify_installation
        return 0
    fi
    
    # Full setup process
    check_prerequisites
    install_autopilot
    
    if [[ "$bootstrap_only" == "true" ]]; then
        bootstrap_repository
        return 0
    fi
    
    bootstrap_repository
    setup_namespaces
    create_projects
    create_bootstrap_apps
    verify_installation
    
    log_success "ArgoCD Autopilot setup completed successfully!"
    
    cat << EOF

🎉 Setup Complete! 

Next steps:
1. Verify ArgoCD applications: kubectl get apps -n $ARGOCD_NAMESPACE
2. Check Port.io controller: kubectl get pods -n $PORT_NAMESPACE
3. Access ArgoCD UI: https://$ARGOCD_SERVER
4. Test Port.io webhooks: curl -X POST http://port-gitops-controller.$PORT_NAMESPACE.svc.cluster.local:8080/health

For more information, see the README.md in the argocd/autopilot directory.
EOF
}

# Execute main function with all arguments
main "$@"
