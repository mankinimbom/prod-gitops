#!/bin/bash

# Comprehensive Backup & Security Setup Script
# This script sets up Velero, Trivy security scanning, and automated rollback mechanisms

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to log messages
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
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed. Please install helm first."
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Install Velero
install_velero() {
    log_info "Installing Velero..."
    
    # Add Velero Helm repository
    helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
    helm repo update
    
    # Create velero namespace
    kubectl create namespace velero --dry-run=client -o yaml | kubectl apply -f -
    
    # Install Velero with Helm
    helm upgrade --install velero vmware-tanzu/velero \
        --namespace velero \
        --version 5.1.4 \
        --values - <<EOF
image:
  repository: velero/velero
  tag: v1.12.1
  pullPolicy: IfNotPresent

initContainers:
- name: velero-plugin-for-aws
  image: velero/velero-plugin-for-aws:v1.8.1
  imagePullPolicy: IfNotPresent
  volumeMounts:
  - mountPath: /target
    name: plugins

configuration:
  provider: aws
  backupStorageLocation:
    bucket: ${VELERO_BUCKET:-velero-backups}
    prefix: cluster-backups
    config:
      region: ${AWS_REGION:-us-west-2}
  volumeSnapshotLocation:
    provider: aws
    config:
      region: ${AWS_REGION:-us-west-2}
  features: EnableCSI
  logLevel: info
  defaultBackupTTL: 720h

serviceAccount:
  server:
    create: true
    name: velero-server
    annotations:
      eks.amazonaws.com/role-arn: ${VELERO_IAM_ROLE:-}

resources:
  requests:
    cpu: 500m
    memory: 128Mi
  limits:
    cpu: 1000m
    memory: 512Mi

securityContext:
  runAsNonRoot: true
  runAsUser: 65534
  runAsGroup: 65534
  fsGroup: 65534

nodeSelector:
  node-type: system

tolerations:
- key: node-role.kubernetes.io/system
  operator: Exists
  effect: NoSchedule
EOF
    
    # Apply custom Velero configurations
    kubectl apply -f backup/velero-schedules.yaml
    
    log_success "Velero installation completed"
}

# Install Trivy Operator
install_trivy() {
    log_info "Installing Trivy Operator..."
    
    # Add Trivy Helm repository
    helm repo add aqua https://aquasecurity.github.io/helm-charts/
    helm repo update
    
    # Create trivy-system namespace
    kubectl create namespace trivy-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Install Trivy Operator
    helm upgrade --install trivy-operator aqua/trivy-operator \
        --namespace trivy-system \
        --version 0.18.0 \
        --values - <<EOF
operator:
  configAuditScannerEnabled: true
  vulnerabilityScannerEnabled: true
  exposedSecretScannerEnabled: true
  clusterComplianceEnabled: true
  
trivyOperator:
  scanJobTimeout: 5m
  scanJobsRetryDelay: 30s
  
serviceMonitor:
  enabled: true
  namespace: monitoring

resources:
  requests:
    cpu: 100m
    memory: 100Mi
  limits:
    cpu: 500m
    memory: 500Mi

securityContext:
  runAsNonRoot: true
  runAsUser: 65534
  capabilities:
    drop:
    - ALL
EOF
    
    # Apply custom Trivy configurations
    kubectl apply -f security/trivy-security-scanning.yaml
    
    log_success "Trivy Operator installation completed"
}

# Setup monitoring for backup and security
setup_monitoring() {
    log_info "Setting up monitoring configurations..."
    
    # Apply monitoring configurations
    kubectl apply -f monitoring/gitops-monitoring.yaml
    
    # Apply backup monitoring
    kubectl apply -f backup/velero-backup-config.yaml
    
    log_success "Monitoring setup completed"
}

# Setup automated rollback
setup_rollback() {
    log_info "Setting up automated rollback mechanisms..."
    
    # Apply rollback configurations
    kubectl apply -f rollback/automated-rollback.yaml
    
    log_success "Automated rollback setup completed"
}

# Verify installations
verify_installations() {
    log_info "Verifying installations..."
    
    # Check Velero
    log_info "Checking Velero status..."
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=velero -n velero --timeout=300s
    
    # Check Trivy Operator
    log_info "Checking Trivy Operator status..."
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=trivy-operator -n trivy-system --timeout=300s
    
    # List backup schedules
    log_info "Backup schedules:"
    kubectl get schedules -n velero
    
    # Check security scanning
    log_info "Security scanning jobs:"
    kubectl get cronjobs -n trivy-system
    
    log_success "All components are running successfully"
}

# Create initial backup
create_initial_backup() {
    log_info "Creating initial backup..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: initial-backup-$(date +%Y%m%d-%H%M%S)
  namespace: velero
spec:
  includedNamespaces:
  - prod
  - argocd
  storageLocation: aws-s3-backup
  volumeSnapshotLocations:
  - aws-ebs-snapshots
  ttl: 720h0m0s
EOF
    
    log_success "Initial backup created"
}

# Main execution
main() {
    log_info "Starting Backup & Security Setup..."
    
    # Set required environment variables if not provided
    export VELERO_BUCKET=${VELERO_BUCKET:-"your-velero-backup-bucket"}
    export AWS_REGION=${AWS_REGION:-"us-west-2"}
    
    if [ -z "$VELERO_IAM_ROLE" ]; then
        log_warning "VELERO_IAM_ROLE not set. Please configure IAM role for Velero."
    fi
    
    check_prerequisites
    install_velero
    install_trivy
    setup_monitoring
    setup_rollback
    verify_installations
    create_initial_backup
    
    log_success "✅ Backup & Security setup completed successfully!"
    
    echo
    log_info "📋 Next Steps:"
    echo "1. Configure your backup storage bucket: $VELERO_BUCKET"
    echo "2. Set up IAM roles for Velero backup permissions"
    echo "3. Configure notification webhooks for alerts"
    echo "4. Test backup and restore procedures"
    echo "5. Review and customize security scanning policies"
    echo
    log_info "📖 Useful Commands:"
    echo "• List backups: kubectl get backups -n velero"
    echo "• Create on-demand backup: velero backup create my-backup --include-namespaces prod"
    echo "• Restore from backup: velero restore create --from-backup backup-name"
    echo "• Check security scans: kubectl get vulnerabilityreports -A"
    echo "• View rollback automation logs: kubectl logs -l app=rollback-automation -n argocd"
}

# Run main function
main "$@"
