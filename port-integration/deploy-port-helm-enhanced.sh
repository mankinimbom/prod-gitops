#!/bin/bash

# Enhanced Port.io Helm Charts Deployment
# This script deploys Port.io integrations using custom values files for better configuration management

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_K8S_EXPORTER="$SCRIPT_DIR/values-k8s-exporter.yaml"
VALUES_ARGOCD_OCEAN="$SCRIPT_DIR/values-argocd-ocean.yaml"

# Color output functions
print_status() { echo -e "\033[1;34m$1\033[0m"; }
print_success() { echo -e "\033[1;32m✅ $1\033[0m"; }
print_error() { echo -e "\033[1;31m❌ $1\033[0m"; }
print_warning() { echo -e "\033[1;33m⚠️  $1\033[0m"; }

echo "🚀 Enhanced Port.io Helm Charts Deployment"
echo "=========================================="

# Check if values files exist
check_values_files() {
    print_status "📋 Checking values files..."
    
    if [ ! -f "$VALUES_K8S_EXPORTER" ]; then
        print_error "Values file not found: $VALUES_K8S_EXPORTER"
        exit 1
    fi
    
    if [ ! -f "$VALUES_ARGOCD_OCEAN" ]; then
        print_error "Values file not found: $VALUES_ARGOCD_OCEAN"
        exit 1
    fi
    
    print_success "Values files found and ready"
}

# Validate credentials
validate_credentials() {
    print_status "🔐 Validating Port.io credentials..."
    
    # Extract credentials from values files for validation
    CLIENT_ID=$(grep "portClientId\|clientId" "$VALUES_K8S_EXPORTER" | head -1 | cut -d'"' -f2)
    CLIENT_SECRET=$(grep "portClientSecret\|clientSecret" "$VALUES_K8S_EXPORTER" | head -1 | cut -d'"' -f2)
    
    if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
        print_error "Port.io credentials not found in values files"
        print_status "Please update the credentials in:"
        print_status "  - $VALUES_K8S_EXPORTER"
        print_status "  - $VALUES_ARGOCD_OCEAN"
        exit 1
    fi
    
    print_success "Port.io credentials validated"
}

# Install with values files
install_with_values() {
    print_status "📦 Adding Port.io Helm repository..."
    helm repo add --force-update port-labs https://port-labs.github.io/helm-charts
    helm repo update
    
    print_status "🔧 Installing Port.io Kubernetes Exporter with custom values..."
    helm upgrade --install port-k8s-exporter port-labs/port-k8s-exporter \
        --create-namespace --namespace port-k8s-exporter \
        --values "$VALUES_K8S_EXPORTER" \
        --wait --timeout=300s
    
    print_success "Port.io Kubernetes Exporter installed"
    
    print_status "🌊 Installing Port.io ArgoCD Ocean Integration with custom values..."
    helm upgrade --install argocd-ocean port-labs/port-ocean \
        --create-namespace --namespace port-ocean-argocd \
        --values "$VALUES_ARGOCD_OCEAN" \
        --wait --timeout=300s
    
    print_success "Port.io ArgoCD Ocean Integration installed"
}

# Apply enhanced ArgoCD configuration
apply_argocd_config() {
    print_status "🔄 Applying enhanced ArgoCD configuration..."
    
    # Apply the updated ArgoCD server configuration
    if [ -f "$SCRIPT_DIR/../argocd/argocd-server-ha.yaml" ]; then
        kubectl apply -f "$SCRIPT_DIR/../argocd/argocd-server-ha.yaml"
        print_success "ArgoCD server configuration updated"
        
        # Restart ArgoCD server to pick up changes
        kubectl rollout restart deployment/argocd-server -n argocd
        print_status "ArgoCD server restarted to apply changes"
    else
        print_warning "ArgoCD configuration file not found, skipping update"
    fi
}

# Create monitoring resources
create_monitoring() {
    print_status "📊 Creating monitoring resources..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceMonitor
metadata:
  name: port-k8s-exporter
  namespace: port-k8s-exporter
  labels:
    app: port-k8s-exporter
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: port-k8s-exporter
  endpoints:
  - port: metrics
    path: /metrics
    interval: 30s
---
apiVersion: v1
kind: ServiceMonitor
metadata:
  name: argocd-ocean
  namespace: port-ocean-argocd
  labels:
    app: argocd-ocean
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: port-ocean
  endpoints:
  - port: metrics
    path: /metrics
    interval: 30s
EOF

    print_success "Monitoring resources created"
}

# Verify and display status
verify_and_status() {
    print_status "🔍 Verifying deployments..."
    
    echo "📊 Port.io Kubernetes Exporter Status:"
    kubectl get pods,svc -n port-k8s-exporter
    
    echo -e "\n🌊 Port.io ArgoCD Ocean Status:"
    kubectl get pods,svc -n port-ocean-argocd
    
    echo -e "\n📈 Helm Release Status:"
    helm status port-k8s-exporter -n port-k8s-exporter
    helm status argocd-ocean -n port-ocean-argocd
    
    print_success "Verification completed"
}

# Display integration URLs and endpoints
display_integration_info() {
    print_status "🔗 Integration Information"
    echo "=========================="
    echo ""
    echo "📡 Service Endpoints:"
    
    # Get service IPs and ports
    K8S_EXPORTER_IP=$(kubectl get svc port-k8s-exporter -n port-k8s-exporter -o jsonpath='{.spec.clusterIP}')
    K8S_EXPORTER_PORT=$(kubectl get svc port-k8s-exporter -n port-k8s-exporter -o jsonpath='{.spec.ports[0].port}')
    
    OCEAN_IP=$(kubectl get svc argocd-ocean -n port-ocean-argocd -o jsonpath='{.spec.clusterIP}')
    OCEAN_PORT=$(kubectl get svc argocd-ocean -n port-ocean-argocd -o jsonpath='{.spec.ports[0].port}')
    
    echo "   • K8s Exporter: http://$K8S_EXPORTER_IP:$K8S_EXPORTER_PORT"
    echo "   • ArgoCD Ocean: http://$OCEAN_IP:$OCEAN_PORT"
    echo "   • ArgoCD Ocean Webhook: http://$OCEAN_IP:$OCEAN_PORT/webhooks/argocd"
    echo ""
    echo "🔧 Configuration Files Used:"
    echo "   • K8s Exporter Values: $VALUES_K8S_EXPORTER"
    echo "   • ArgoCD Ocean Values: $VALUES_ARGOCD_OCEAN"
    echo ""
    echo "📋 Useful Commands:"
    echo "   • View K8s Exporter logs: kubectl logs -f deployment/port-k8s-exporter -n port-k8s-exporter"
    echo "   • View Ocean logs: kubectl logs -f deployment/argocd-ocean -n port-ocean-argocd"
    echo "   • Update K8s Exporter: helm upgrade port-k8s-exporter port-labs/port-k8s-exporter -n port-k8s-exporter -f $VALUES_K8S_EXPORTER"
    echo "   • Update Ocean: helm upgrade argocd-ocean port-labs/port-ocean -n port-ocean-argocd -f $VALUES_ARGOCD_OCEAN"
    echo ""
    echo "🎯 Next Steps:"
    echo "   1. Check Port.io catalog for imported Kubernetes resources"
    echo "   2. Verify ArgoCD applications are syncing to Port.io"
    echo "   3. Customize blueprints and mappings in values files as needed"
    echo "   4. Set up monitoring and alerting for the integrations"
}

# Main execution
main() {
    echo "🎯 Starting Enhanced Port.io Integration Deployment"
    echo "=================================================="
    
    check_values_files
    validate_credentials
    install_with_values
    apply_argocd_config
    create_monitoring
    verify_and_status
    display_integration_info
    
    echo ""
    echo "🎉 Enhanced Port.io Integration Complete!"
    echo "========================================"
    print_success "All integrations deployed with custom configurations"
    print_status "Monitor the logs and check Port.io catalog for data flow"
}

# Execute main function
main "$@"
