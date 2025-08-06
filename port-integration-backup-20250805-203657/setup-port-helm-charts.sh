#!/bin/bash

# Port.io Helm Charts Setup Script
# This script sets up Port.io Kubernetes Exporter and ArgoCD Ocean integration

set -e

# Color output functions
print_status() { echo -e "\033[1;34m$1\033[0m"; }
print_success() { echo -e "\033[1;32m✅ $1\033[0m"; }
print_error() { echo -e "\033[1;31m❌ $1\033[0m"; }
print_warning() { echo -e "\033[1;33m⚠️  $1\033[0m"; }

echo "🚀 Setting up Port.io Helm Charts Integration"
echo "============================================="

# Configuration - UPDATE THESE VALUES
PORT_CLIENT_ID="57qkRMZxmGcfVKfipr2to8pBMII77FYK"
PORT_CLIENT_SECRET="n0eBOFw6SVO5nDYUAcM56Dk6jJKpeb11ePgzGC8O5FS0J4YrkplXrM1VPR7Fk6wN"
PORT_BASE_URL="https://api.port.io"
ARGOCD_SERVER_URL="http://argo.annkinimbom.com/"
ARGOCD_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJhcmdvY2QiLCJzdWIiOiJtaWNoYWVsLXRva2VuOmFwaUtleSIsIm5iZiI6MTc1NDI1NTE3NiwiaWF0IjoxNzU0MjU1MTc2LCJqdGkiOiIxOGM5MWI0OS1iYjVjLTQwMzYtYjNkMy1kYmQxNDA3YmIzYzMifQ.FI92Y6OYuO_QoIvVTlUNqVerE0aT89ekRyCxT3Xgff0"
CLUSTER_NAME="port-k8s-exporter"

# Check prerequisites
check_prerequisites() {
    print_status "📋 Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is required but not installed"
        exit 1
    fi
    
    if ! command -v helm &> /dev/null; then
        print_error "Helm is required but not installed"
        print_status "Installing Helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Unable to connect to Kubernetes cluster"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Add Port.io Helm repository
add_port_helm_repo() {
    print_status "📦 Adding Port.io Helm repository..."
    
    helm repo add --force-update port-labs https://port-labs.github.io/helm-charts
    helm repo update
    
    print_success "Port.io Helm repository added and updated"
}

# Install Port.io Kubernetes Exporter
install_k8s_exporter() {
    print_status "🔧 Installing Port.io Kubernetes Exporter..."
    
    # Create namespace if it doesn't exist
    kubectl create namespace port-k8s-exporter --dry-run=client -o yaml | kubectl apply -f -
    
    # Install or upgrade the exporter
    helm upgrade --install port-k8s-exporter port-labs/port-k8s-exporter \
        --create-namespace --namespace port-k8s-exporter \
        --set secret.secrets.portClientId="$PORT_CLIENT_ID" \
        --set secret.secrets.portClientSecret="$PORT_CLIENT_SECRET" \
        --set portBaseUrl="$PORT_BASE_URL" \
        --set stateKey="$CLUSTER_NAME" \
        --set eventListener.type="POLLING" \
        --set "extraEnv[0].name"="CLUSTER_NAME" \
        --set "extraEnv[0].value"="$CLUSTER_NAME" \
        --set "extraEnv[1].name"="INTEGRATION_TYPE" \
        --set "extraEnv[1].value"="kubernetes" \
        --wait --timeout=300s
    
    print_success "Port.io Kubernetes Exporter installed successfully"
}

# Install Port.io ArgoCD Ocean Integration
install_argocd_ocean() {
    print_status "🌊 Installing Port.io ArgoCD Ocean Integration..."
    
    # Create namespace if it doesn't exist
    kubectl create namespace port-ocean-argocd --dry-run=client -o yaml | kubectl apply -f -
    
    # Install or upgrade the ArgoCD Ocean integration
    helm upgrade --install argocd-ocean port-labs/port-ocean \
        --create-namespace --namespace port-ocean-argocd \
        --set port.clientId="$PORT_CLIENT_ID" \
        --set port.clientSecret="$PORT_CLIENT_SECRET" \
        --set port.baseUrl="$PORT_BASE_URL" \
        --set initializePortResources=true \
        --set sendRawDataExamples=true \
        --set scheduledResyncInterval=360 \
        --set integration.identifier="argocd" \
        --set integration.type="argocd" \
        --set integration.eventListener.type="POLLING" \
        --set integration.secrets.token="$ARGOCD_TOKEN" \
        --set integration.config.serverUrl="$ARGOCD_SERVER_URL" \
        --set integration.config.insecure=true \
        --wait --timeout=300s
    
    print_success "Port.io ArgoCD Ocean Integration installed successfully"
}

# Create RBAC for Port.io integrations
setup_rbac() {
    print_status "🔐 Setting up RBAC for Port.io integrations..."
    
    # Create RBAC for Kubernetes Exporter
    cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: port-k8s-exporter-reader
rules:
- apiGroups: [""]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["networking.k8s.io"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["argoproj.io"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["extensions"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: port-k8s-exporter-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: port-k8s-exporter-reader
subjects:
- kind: ServiceAccount
  name: port-k8s-exporter
  namespace: port-k8s-exporter
EOF

    print_success "RBAC configuration applied"
}

# Configure ArgoCD for Port.io webhook integration
configure_argocd_webhooks() {
    print_status "🔗 Configuring ArgoCD webhooks for Port.io..."
    
    # Update ArgoCD server config to include Port.io webhook endpoints
    kubectl patch configmap argocd-server-config -n argocd --type merge -p '{
        "data": {
            "webhook.port.url": "http://port-ocean-argocd.port-ocean-argocd.svc.cluster.local:8000/webhooks/argocd",
            "application.resourceTrackingMethod": "annotation",
            "statusbadge.enabled": "true"
        }
    }'
    
    # Restart ArgoCD server to pick up configuration changes
    kubectl rollout restart deployment/argocd-server -n argocd
    
    print_success "ArgoCD webhook configuration updated"
}

# Create Port.io configuration for enhanced integration
create_port_config() {
    print_status "📄 Creating Port.io configuration..."
    
    # Create a ConfigMap with Port.io blueprints and mappings
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: port-integration-config
  namespace: port-system
data:
  blueprints.yaml: |
    # Extended blueprints for Helm chart integration
    blueprints:
      - identifier: cluster
        title: Kubernetes Cluster
        icon: Cluster
        schema:
          properties:
            name:
              type: string
              title: Cluster Name
            region:
              type: string
              title: Region
            version:
              type: string
              title: Kubernetes Version
            nodes:
              type: number
              title: Node Count
        relations:
          microservice:
            target: microservice
            many: true
      
      - identifier: argocd-application
        title: ArgoCD Application
        icon: Argo
        schema:
          properties:
            syncStatus:
              type: string
              title: Sync Status
              enum:
                - Synced
                - OutOfSync
                - Unknown
            healthStatus:
              type: string
              title: Health Status
              enum:
                - Healthy
                - Progressing
                - Degraded
                - Missing
            lastSyncTime:
              type: string
              format: date-time
              title: Last Sync Time
            repoUrl:
              type: string
              title: Repository URL
            targetRevision:
              type: string
              title: Target Revision
            namespace:
              type: string
              title: Namespace
        relations:
          microservice:
            target: microservice
            many: false
          environment:
            target: environment
            many: false
  
  mapping.yaml: |
    # Resource mappings for the integrations
    mappings:
      - kind: v1/Pod
        selector:
          query: '.metadata.labels["app.kubernetes.io/name"] != null'
        port:
          entity:
            mappings:
              identifier: '.metadata.name + "-" + .metadata.namespace'
              title: '.metadata.name'
              blueprint: '"microservice"'
              properties:
                namespace: '.metadata.namespace'
                labels: '.metadata.labels'
                creationTimestamp: '.metadata.creationTimestamp'
                image: '.spec.containers[0].image // ""'
              relations:
                environment: '.metadata.namespace'
      
      - kind: argoproj.io/v1alpha1/Application
        selector:
          query: 'true'
        port:
          entity:
            mappings:
              identifier: '.metadata.name + "-" + .metadata.namespace'
              title: '.metadata.name'
              blueprint: '"argocd-application"'
              properties:
                syncStatus: '.status.sync.status'
                healthStatus: '.status.health.status'
                lastSyncTime: '.status.operationState.finishedAt'
                repoUrl: '.spec.source.repoURL'
                targetRevision: '.spec.source.targetRevision'
                namespace: '.spec.destination.namespace'
              relations:
                environment: '.spec.destination.namespace'
EOF

    print_success "Port.io configuration created"
}

# Verify installations
verify_installations() {
    print_status "🔍 Verifying installations..."
    
    # Check Kubernetes Exporter
    echo "📊 Port.io Kubernetes Exporter:"
    kubectl get pods -n port-k8s-exporter
    kubectl get svc -n port-k8s-exporter
    
    echo -e "\n🌊 Port.io ArgoCD Ocean Integration:"
    kubectl get pods -n port-ocean-argocd
    kubectl get svc -n port-ocean-argocd
    
    # Check ArgoCD integration
    echo -e "\n🔄 ArgoCD Integration Status:"
    kubectl get configmap argocd-server-config -n argocd -o jsonpath='{.data.webhook\.port\.url}' || echo "Webhook not configured"
    
    # Check if services are ready
    echo -e "\n📡 Service Status:"
    kubectl rollout status deployment/port-k8s-exporter -n port-k8s-exporter --timeout=60s
    kubectl rollout status deployment/argocd-ocean -n port-ocean-argocd --timeout=60s
    
    print_success "Installation verification completed"
}

# Display connection information
display_connection_info() {
    print_status "📊 Port.io Integration Information"
    echo "=================================="
    echo ""
    echo "🔗 Integration Endpoints:"
    echo "   • Kubernetes Exporter: Running in port-k8s-exporter namespace"
    echo "   • ArgoCD Ocean: Running in port-ocean-argocd namespace"
    echo "   • ArgoCD Server: $ARGOCD_SERVER_URL"
    echo ""
    echo "📋 Configured Integrations:"
    echo "   • Cluster Name: $CLUSTER_NAME"
    echo "   • Port.io Base URL: $PORT_BASE_URL"
    echo "   • Event Listener: POLLING mode"
    echo "   • Sync Interval: 360 seconds"
    echo ""
    echo "🎯 Next Steps:"
    echo "   1. Verify data is flowing to Port.io:"
    echo "      - Check your Port.io catalog for Kubernetes resources"
    echo "      - Verify ArgoCD applications are syncing"
    echo ""
    echo "   2. Configure additional blueprints in Port.io:"
    echo "      - Import the provided blueprint configurations"
    echo "      - Customize entity mappings as needed"
    echo ""
    echo "   3. Set up monitoring:"
    echo "      kubectl logs -f deployment/port-k8s-exporter -n port-k8s-exporter"
    echo "      kubectl logs -f deployment/argocd-ocean -n port-ocean-argocd"
    echo ""
    echo "🛠️ Useful Commands:"
    echo "   • List Port.io pods: kubectl get pods -n port-k8s-exporter -n port-ocean-argocd"
    echo "   • Check integration status: helm status port-k8s-exporter -n port-k8s-exporter"
    echo "   • Update configurations: helm upgrade port-k8s-exporter port-labs/port-k8s-exporter -n port-k8s-exporter"
}

# Main execution
main() {
    echo "🎯 Starting Port.io Helm Charts Setup"
    echo "====================================="
    
    check_prerequisites
    add_port_helm_repo
    install_k8s_exporter
    install_argocd_ocean
    setup_rbac
    configure_argocd_webhooks
    create_port_config
    verify_installations
    display_connection_info
    
    echo ""
    echo "🎉 Port.io Helm Charts Setup Complete!"
    echo "======================================"
    print_success "All integrations installed and configured successfully"
    print_status "Check Port.io catalog to see your Kubernetes and ArgoCD data"
}

# Execute main function
main "$@"
