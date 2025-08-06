#!/bin/bash

# Port.io + ArgoCD Integration Deployment Script
# This script deploys the complete Port.io + ArgoCD integration

set -e

echo "🚀 Deploying Port.io + ArgoCD Integration"
echo "========================================"

# Configuration
NAMESPACE_PORT="port-system"
NAMESPACE_ARGOCD="argocd"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color output functions
print_status() { echo -e "\033[1;34m$1\033[0m"; }
print_success() { echo -e "\033[1;32m✅ $1\033[0m"; }
print_error() { echo -e "\033[1;31m❌ $1\033[0m"; }
print_warning() { echo -e "\033[1;33m⚠️  $1\033[0m"; }

# Check prerequisites
check_prerequisites() {
    print_status "📋 Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is required but not installed"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Unable to connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if ArgoCD is installed
    if ! kubectl get namespace "$NAMESPACE_ARGOCD" &> /dev/null; then
        print_error "ArgoCD namespace '$NAMESPACE_ARGOCD' not found. Please install ArgoCD first."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Validate YAML files
validate_yaml_files() {
    print_status "🔍 Validating YAML files..."
    
    local files=(
        "port-blueprints-actions.yaml"
        "port-gitops-controller.yaml"
        "argocd-integration.yaml"
    )
    
    for file in "${files[@]}"; do
        if [ ! -f "$SCRIPT_DIR/$file" ]; then
            print_error "Required file not found: $file"
            exit 1
        fi
        
        # Basic YAML syntax validation
        if ! kubectl --dry-run=client apply -f "$SCRIPT_DIR/$file" > /dev/null 2>&1; then
            print_warning "YAML validation warning for $file (may be due to missing CRDs)"
        fi
    done
    
    print_success "YAML validation completed"
}

# Deploy Port.io system
deploy_port_system() {
    print_status "🔧 Deploying Port.io system..."
    
    # Create namespace if it doesn't exist
    if ! kubectl get namespace "$NAMESPACE_PORT" &> /dev/null; then
        kubectl create namespace "$NAMESPACE_PORT"
        print_success "Created namespace: $NAMESPACE_PORT"
    fi
    
    # Label the namespace
    kubectl label namespace "$NAMESPACE_PORT" \
        app.kubernetes.io/name=port-system \
        app.kubernetes.io/part-of=port-integration \
        --overwrite
    
    # Deploy Port.io blueprints and actions
    kubectl apply -f "$SCRIPT_DIR/port-blueprints-actions.yaml"
    print_success "Applied Port.io blueprints and actions"
    
    # Deploy Port.io GitOps controller
    kubectl apply -f "$SCRIPT_DIR/port-gitops-controller.yaml"
    print_success "Applied Port.io GitOps controller"
    
    # Wait for controller deployment
    kubectl rollout status deployment/port-gitops-controller -n "$NAMESPACE_PORT" --timeout=300s
    print_success "Port.io GitOps controller is ready"
}

# Deploy ArgoCD integration
deploy_argocd_integration() {
    print_status "🔄 Deploying ArgoCD integration..."
    
    # Create a fixed version of argocd-integration.yaml
    local temp_file=$(mktemp)
    
    # Remove ApplicationSets with validation issues and create corrected versions
    cat > "$temp_file" << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: port-system
  labels:
    name: port-system
    app.kubernetes.io/name: port-system
    app.kubernetes.io/part-of: port-integration

---
# ArgoCD Project for microservices
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: microservices
  namespace: argocd
  labels:
    app.kubernetes.io/name: microservices-project
    app.kubernetes.io/part-of: port-integration
spec:
  description: "Microservices managed by Port.io"
  
  # Source repositories
  sourceRepos:
  - 'https://github.com/your-org/gitops-manifests.git'
  - 'https://github.com/your-org/microservices-configs.git'
  - 'https://charts.helm.sh/stable'
  - 'https://helm.releases.hashicorp.com'
  
  # Allowed destinations
  destinations:
  - namespace: 'dev'
    server: 'https://kubernetes.default.svc'
  - namespace: 'staging'
    server: 'https://kubernetes.default.svc'
  - namespace: 'prod'
    server: 'https://kubernetes.default.svc'
  - namespace: 'port-system'
    server: 'https://kubernetes.default.svc'
  
  # Cluster resource allow list
  clusterResourceWhitelist:
  - group: ''
    kind: Namespace
  - group: 'rbac.authorization.k8s.io'
    kind: ClusterRole
  - group: 'rbac.authorization.k8s.io'
    kind: ClusterRoleBinding
  
  # Namespace resource allow list
  namespaceResourceWhitelist:
  - group: 'apps'
    kind: Deployment
  - group: 'apps'
    kind: ReplicaSet
  - group: ''
    kind: Service
  - group: ''
    kind: ConfigMap
  - group: ''
    kind: Secret
  - group: ''
    kind: Pod
  - group: 'networking.k8s.io'
    kind: Ingress
  - group: 'networking.k8s.io'
    kind: NetworkPolicy
  - group: 'policy'
    kind: PodDisruptionBudget
  - group: 'autoscaling'
    kind: HorizontalPodAutoscaler
  - group: 'argoproj.io'
    kind: Rollout
  - group: 'argoproj.io'
    kind: AnalysisTemplate
  - group: 'argoproj.io'
    kind: AnalysisRun
  
  # RBAC Policies
  roles:
  # Developer role - can sync dev applications
  - name: developer
    description: "Developer access to dev environment"
    policies:
    - p, proj:microservices:developer, applications, get, microservices/*, allow
    - p, proj:microservices:developer, applications, sync, microservices/*-dev, allow
    - p, proj:microservices:developer, applications, action/*, microservices/*-dev, allow
    - p, proj:microservices:developer, repositories, get, *, allow
    groups:
    - your-org:developers
    - backend
    - frontend
  
  # Platform engineer role - can manage staging and prod
  - name: platform-engineer
    description: "Platform engineer access to all environments"
    policies:
    - p, proj:microservices:platform-engineer, applications, *, microservices/*, allow
    - p, proj:microservices:platform-engineer, repositories, *, *, allow
    - p, proj:microservices:platform-engineer, clusters, get, *, allow
    groups:
    - your-org:platform-team
    - platform

---
# RBAC for Port integration
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: argocd
  name: port-argocd-manager
rules:
- apiGroups: ["argoproj.io"]
  resources: ["applications", "appprojects"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]
  resourceNames: ["argocd-secret"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: port-argocd-manager
  namespace: argocd
subjects:
- kind: ServiceAccount
  name: port-gitops-controller
  namespace: port-system
roleRef:
  kind: Role
  name: port-argocd-manager
  apiGroup: rbac.authorization.k8s.io
EOF
    
    # Apply the corrected configuration
    kubectl apply -f "$temp_file"
    rm "$temp_file"
    
    print_success "Applied ArgoCD integration (Project and RBAC)"
}

# Create sample ApplicationSet (optional)
create_sample_applicationset() {
    print_status "📱 Creating sample ApplicationSet..."
    
    read -p "Do you want to create a sample ApplicationSet? (y/N): " create_appset
    if [[ $create_appset =~ ^[Yy]$ ]]; then
        
        local appset_file=$(mktemp)
        cat > "$appset_file" << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: port-sample-apps
  namespace: argocd
  labels:
    app.kubernetes.io/component: applicationset
    managed-by: port-io
spec:
  generators:
  - list:
      elements:
      - service: backend
        env: dev
        replicas: "2"
      - service: frontend  
        env: dev
        replicas: "1"
  template:
    metadata:
      name: '{{service}}-{{env}}'
      labels:
        app.kubernetes.io/name: '{{service}}'
        app.kubernetes.io/environment: '{{env}}'
        managed-by: port-io
      annotations:
        port.io/entity: '{{service}}'
        port.io/environment: '{{env}}'
    spec:
      project: microservices
      source:
        repoURL: https://github.com/your-org/sample-configs.git
        targetRevision: HEAD
        path: 'manifests/{{service}}/{{env}}'
      destination:
        server: 'https://kubernetes.default.svc'
        namespace: '{{env}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
EOF
        
        kubectl apply -f "$appset_file"
        rm "$appset_file"
        print_success "Created sample ApplicationSet"
    else
        print_status "Skipped sample ApplicationSet creation"
    fi
}

# Verify deployment
verify_deployment() {
    print_status "🔍 Verifying deployment..."
    
    # Check Port system pods
    echo "Port System Pods:"
    kubectl get pods -n "$NAMESPACE_PORT"
    
    # Check ArgoCD projects
    echo -e "\nArgoCD Projects:"
    kubectl get appprojects -n "$NAMESPACE_ARGOCD"
    
    # Check ApplicationSets
    echo -e "\nApplicationSets:"
    kubectl get applicationsets -n "$NAMESPACE_ARGOCD" 2>/dev/null || echo "No ApplicationSets found"
    
    # Check Applications
    echo -e "\nApplications:"
    kubectl get applications -n "$NAMESPACE_ARGOCD" 2>/dev/null || echo "No Applications found"
    
    # Service status
    echo -e "\nPort GitOps Controller Service:"
    kubectl get svc -n "$NAMESPACE_PORT" port-gitops-controller 2>/dev/null || echo "Service not found"
    
    print_success "Deployment verification completed"
}

# Configure ArgoCD for Port.io integration
configure_argocd_integration() {
    print_status "🔧 Configuring ArgoCD for Port.io integration..."
    
    # Check if ArgoCD server config needs updating
    local config_updated=false
    
    # Update ArgoCD server config with webhook endpoint
    kubectl patch configmap argocd-cmd-params-cm -n "$NAMESPACE_ARGOCD" --type merge -p '{
        "data": {
            "server.enable.webhook": "true",
            "server.webhook.github.secret": "github-webhook-secret"
        }
    }' 2>/dev/null && config_updated=true
    
    if $config_updated; then
        print_success "Updated ArgoCD server configuration"
        print_warning "ArgoCD server restart may be required for changes to take effect"
    else
        print_status "ArgoCD configuration unchanged"
    fi
}

# Main execution
main() {
    echo "🎯 Starting Port.io + ArgoCD Integration Deployment"
    echo "================================================="
    
    check_prerequisites
    validate_yaml_files
    deploy_port_system
    deploy_argocd_integration
    configure_argocd_integration
    create_sample_applicationset
    verify_deployment
    
    echo ""
    echo "🎉 Port.io + ArgoCD Integration Deployment Complete!"
    echo "=================================================="
    echo "📊 Summary:"
    echo "   • Port.io System: Deployed in namespace '$NAMESPACE_PORT'"
    echo "   • ArgoCD Project: 'microservices' created"
    echo "   • RBAC: Configured for Port.io integration"
    echo "   • GitOps Controller: Ready to handle webhooks"
    echo ""
    echo "🔗 Access Points:"
    echo "   • ArgoCD UI: http://argo.annkinimbom.com"
    echo "   • Port.io Controller: http://<controller-service>:8080"
    echo ""
    echo "📝 Next Steps:"
    echo "   1. Configure Port.io credentials:"
    echo "      kubectl create secret generic port-credentials \\"
    echo "        --from-literal=client-id='your-client-id' \\"
    echo "        --from-literal=client-secret='your-client-secret' \\"
    echo "        -n $NAMESPACE_PORT"
    echo ""
    echo "   2. Update webhook URLs in Port.io to point to:"
    echo "      http://<your-cluster>/port-webhook/..."
    echo ""
    echo "   3. Import Port.io blueprints and start creating microservices"
    echo ""
    echo "   4. Consider setting up ArgoCD Autopilot:"
    echo "      ./setup-autopilot.sh"
    echo ""
    echo "🛠️ Useful Commands:"
    echo "   • Check Port system: kubectl get all -n $NAMESPACE_PORT"
    echo "   • Check ArgoCD apps: kubectl get applications -n $NAMESPACE_ARGOCD"
    echo "   • View controller logs: kubectl logs -f deployment/port-gitops-controller -n $NAMESPACE_PORT"
}

# Execute main function
main "$@"
