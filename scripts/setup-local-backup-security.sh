#!/bin/bash

# Local GitOps Backup & Security Setup Script
# This script sets up local backup, security scanning, and rollback mechanisms

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
    log_info "Checking prerequisites for local setup..."
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "docker is not installed. Please install docker first."
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        log_info "For local development, you might need to start minikube or kind cluster"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Create local directories
create_local_directories() {
    log_info "Creating local storage directories..."
    
    # Create backup directory
    sudo mkdir -p /var/velero-backups
    sudo chown $(whoami):$(whoami) /var/velero-backups
    
    # Create security reports directory
    sudo mkdir -p /var/local-security-reports
    sudo chown $(whoami):$(whoami) /var/local-security-reports
    
    # Create subdirectories
    mkdir -p /var/local-security-reports/security-reports
    mkdir -p /var/local-security-reports/secret-reports
    
    log_success "Local directories created"
}

# Setup local container registry
setup_local_registry() {
    log_info "Setting up local container registry..."
    
    # Check if registry is already running
    if docker ps | grep -q "registry:2"; then
        log_info "Local registry already running"
        return 0
    fi
    
    # Start local registry
    docker run -d \
        --name local-registry \
        --restart=always \
        -p 5000:5000 \
        -v local-registry-data:/var/lib/registry \
        registry:2
    
    # Wait for registry to be ready
    sleep 5
    
    # Test registry
    if curl -f http://localhost:5000/v2/ > /dev/null 2>&1; then
        log_success "Local registry is running at localhost:5000"
    else
        log_error "Failed to start local registry"
        exit 1
    fi
}

# Install local Velero
install_local_velero() {
    log_info "Installing local Velero configuration..."
    
    # Apply Velero configuration
    kubectl apply -f backup/velero-local.yaml
    
    # Wait for Velero to be ready
    log_info "Waiting for Velero to be ready..."
    kubectl wait --for=condition=Ready pod -l app=velero -n velero --timeout=300s || {
        log_warning "Velero pods might still be starting. Check with: kubectl get pods -n velero"
    }
    
    log_success "Velero local installation completed"
}

# Install local security scanning
install_local_security() {
    log_info "Installing local security scanning..."
    
    # Apply security scanning configuration
    kubectl apply -f security/local-security-scanning.yaml
    
    # Wait for security scanner to be ready
    log_info "Waiting for security scanner to be ready..."
    kubectl wait --for=condition=Ready pod -l app=security-reports-viewer -n security-system --timeout=300s || {
        log_warning "Security scanner might still be starting. Check with: kubectl get pods -n security-system"
    }
    
    log_success "Local security scanning installation completed"
}

# Install local rollback automation
install_local_rollback() {
    log_info "Installing local rollback automation..."
    
    # Apply rollback configuration
    kubectl apply -f rollback/local-rollback.yaml
    
    # Wait for rollback automation to be ready
    log_info "Waiting for rollback automation to be ready..."
    kubectl wait --for=condition=Ready pod -l app=rollback-automation -n rollback-system --timeout=300s || {
        log_warning "Rollback automation might still be starting. Check with: kubectl get pods -n rollback-system"
    }
    
    log_success "Local rollback automation installation completed"
}

# Setup port forwarding for dashboards
setup_port_forwarding() {
    log_info "Setting up port forwarding for local dashboards..."
    
    # Create port-forward script
    cat > setup-port-forwards.sh << 'EOF'
#!/bin/bash
echo "Setting up port forwarding for local dashboards..."

# Kill existing port forwards
pkill -f "kubectl port-forward" || true

# Wait a moment
sleep 2

# Security Reports Viewer (port 8080)
kubectl port-forward -n security-system svc/security-reports-viewer 8080:80 &
echo "Security Reports available at: http://localhost:8080"

# Health Dashboard (port 8081)
kubectl port-forward -n rollback-system svc/health-dashboard 8081:80 &
echo "Health Dashboard available at: http://localhost:8081"

# ArgoCD Server (port 8082)
kubectl port-forward -n argocd svc/argocd-server 8082:80 &
echo "ArgoCD available at: http://localhost:8082"

echo "Port forwarding setup completed!"
echo "Press Ctrl+C to stop all port forwards"

# Wait for interrupt
trap 'echo "Stopping port forwards..."; pkill -f "kubectl port-forward"; exit 0' INT
while true; do sleep 1; done
EOF
    
    chmod +x setup-port-forwards.sh
    
    log_success "Port forwarding script created: ./setup-port-forwards.sh"
}

# Run initial security scan
run_initial_scan() {
    log_info "Running initial security scan..."
    
    # Create a one-time security scan job
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: initial-security-scan
  namespace: security-system
spec:
  template:
    spec:
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        fsGroup: 65534
      containers:
      - name: trivy-scanner
        image: aquasecurity/trivy:0.48.0
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 65534
          capabilities:
            drop:
            - ALL
        command:
        - /bin/sh
        - -c
        - |
          echo "Running initial security scan..."
          mkdir -p /reports
          
          # Scan a sample image
          trivy image --format json --output /reports/sample-scan.json alpine:latest || true
          trivy image --format table --output /reports/sample-report.txt alpine:latest || true
          
          echo "Initial scan completed"
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
            ephemeral-storage: 1Gi
          limits:
            cpu: 1000m
            memory: 2Gi
            ephemeral-storage: 4Gi
        volumeMounts:
        - name: reports
          mountPath: /reports
        - name: cache
          mountPath: /tmp
        - name: local-storage
          mountPath: /local-storage
      volumes:
      - name: reports
        emptyDir:
          sizeLimit: 1Gi
      - name: cache
        emptyDir:
          sizeLimit: 2Gi
      - name: local-storage
        hostPath:
          path: /var/local-security-reports
          type: DirectoryOrCreate
EOF
    
    log_success "Initial security scan job created"
}

# Create sample backup
create_sample_backup() {
    log_info "Creating sample backup..."
    
    # Create a simple backup of the prod namespace
    cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: sample-backup-$(date +%Y%m%d-%H%M%S)
  namespace: velero
spec:
  includedNamespaces:
  - prod
  - default
  storageLocation: local-filesystem
  ttl: 168h0m0s
EOF
    
    log_success "Sample backup created"
}

# Verify installations
verify_installations() {
    log_info "Verifying local installations..."
    
    # Check all components
    echo
    log_info "=== VELERO STATUS ==="
    kubectl get pods -n velero 2>/dev/null || log_warning "Velero namespace not found"
    
    echo
    log_info "=== SECURITY SYSTEM STATUS ==="
    kubectl get pods -n security-system 2>/dev/null || log_warning "Security-system namespace not found"
    
    echo
    log_info "=== ROLLBACK SYSTEM STATUS ==="
    kubectl get pods -n rollback-system 2>/dev/null || log_warning "Rollback-system namespace not found"
    
    echo
    log_info "=== LOCAL REGISTRY STATUS ==="
    if docker ps | grep -q "local-registry"; then
        echo "✅ Local registry running on localhost:5000"
    else
        echo "❌ Local registry not running"
    fi
    
    echo
    log_info "=== LOCAL STORAGE STATUS ==="
    echo "Backup directory: $(ls -la /var/velero-backups/ 2>/dev/null | wc -l) items"
    echo "Security reports: $(ls -la /var/local-security-reports/ 2>/dev/null | wc -l) items"
    
    log_success "Verification completed"
}

# Print usage instructions
print_usage_instructions() {
    log_success "🎉 Local GitOps Backup & Security setup completed!"
    
    echo
    echo "📋 USAGE INSTRUCTIONS:"
    echo "====================="
    echo
    echo "🔗 Access Dashboards:"
    echo "  1. Run: ./setup-port-forwards.sh"
    echo "  2. Open http://localhost:8080 for Security Reports"
    echo "  3. Open http://localhost:8081 for Health Dashboard"
    echo "  4. Open http://localhost:8082 for ArgoCD"
    echo
    echo "🐳 Docker Registry:"
    echo "  • Local registry: localhost:5000"
    echo "  • Push images: docker push localhost:5000/myapp:latest"
    echo "  • Pull images: docker pull localhost:5000/myapp:latest"
    echo
    echo "💾 Backup Operations:"
    echo "  • List backups: kubectl get backups -n velero"
    echo "  • Create backup: kubectl apply -f backup/velero-local.yaml"
    echo "  • Check backup location: ls -la /var/velero-backups/"
    echo
    echo "🔍 Security Scanning:"
    echo "  • View scan results: ls -la /var/local-security-reports/"
    echo "  • Manual scan: kubectl create job --from=cronjob/local-security-scanner manual-scan -n security-system"
    echo "  • Check scanner logs: kubectl logs -l app=security-scanner -n security-system"
    echo
    echo "🔄 Rollback Operations:"
    echo "  • View automation logs: kubectl logs -l app=rollback-automation -n rollback-system"
    echo "  • Manual rollback: kubectl edit job manual-rollback-backend -n rollback-system"
    echo "  • Check app health: kubectl get pods -n prod"
    echo
    echo "🛠️  Useful Commands:"
    echo "  • kubectl get all -n velero"
    echo "  • kubectl get all -n security-system"
    echo "  • kubectl get all -n rollback-system"
    echo "  • docker logs local-registry"
    echo
    echo "📁 Local Directories:"
    echo "  • Backups: /var/velero-backups/"
    echo "  • Security Reports: /var/local-security-reports/"
    echo
}

# Main execution
main() {
    log_info "🏠 Starting Local GitOps Backup & Security Setup..."
    echo
    
    check_prerequisites
    create_local_directories
    setup_local_registry
    install_local_velero
    install_local_security
    install_local_rollback
    setup_port_forwarding
    run_initial_scan
    create_sample_backup
    verify_installations
    print_usage_instructions
    
    echo
    log_success "✅ Local setup completed successfully!"
    echo
    log_info "🚀 Next steps:"
    echo "  1. Run ./setup-port-forwards.sh to access dashboards"
    echo "  2. Build and push your applications to localhost:5000"
    echo "  3. Test the backup and rollback mechanisms"
    echo "  4. Customize the configurations for your specific needs"
}

# Run main function
main "$@"
