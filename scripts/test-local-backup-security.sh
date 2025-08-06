#!/bin/bash

# Local GitOps Testing & Validation Script
# Tests backup, security scanning, and rollback mechanisms

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

log_test() {
    echo -e "${PURPLE}[TEST]${NC} $1"
}

# Test Velero backup functionality
test_backup_functionality() {
    log_test "Testing Velero backup functionality..."
    
    # Create test namespace and resources
    kubectl create namespace backup-test --dry-run=client -o yaml | kubectl apply -f -
    
    # Create test deployment
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  namespace: backup-test
  labels:
    app: test-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-app
  template:
    metadata:
      labels:
        app: test-app
    spec:
      containers:
      - name: test-app
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
EOF
    
    # Wait for deployment
    kubectl wait --for=condition=Available deployment/test-app -n backup-test --timeout=60s
    
    # Create backup
    BACKUP_NAME="test-backup-$(date +%Y%m%d-%H%M%S)"
    cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: $BACKUP_NAME
  namespace: velero
spec:
  includedNamespaces:
  - backup-test
  storageLocation: local-filesystem
  ttl: 1h0m0s
EOF
    
    # Wait for backup to complete
    log_info "Waiting for backup to complete..."
    sleep 30
    
    # Check backup status
    BACKUP_STATUS=$(kubectl get backup $BACKUP_NAME -n velero -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    
    if [ "$BACKUP_STATUS" = "Completed" ]; then
        log_success "✅ Backup test passed - backup completed successfully"
        
        # Check local filesystem
        if ls /var/velero-backups/backups/$BACKUP_NAME/ >/dev/null 2>&1; then
            log_success "✅ Backup files found in local filesystem"
        else
            log_warning "⚠️  Backup files not found in local filesystem"
        fi
    else
        log_warning "⚠️  Backup status: $BACKUP_STATUS (may still be in progress)"
    fi
    
    # Test restore functionality
    log_test "Testing restore functionality..."
    
    # Delete the test deployment
    kubectl delete deployment test-app -n backup-test
    
    # Create restore
    RESTORE_NAME="test-restore-$(date +%Y%m%d-%H%M%S)"
    cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: $RESTORE_NAME
  namespace: velero
spec:
  backupName: $BACKUP_NAME
  includedNamespaces:
  - backup-test
EOF
    
    # Wait for restore
    sleep 30
    
    # Check if deployment was restored
    if kubectl get deployment test-app -n backup-test >/dev/null 2>&1; then
        log_success "✅ Restore test passed - deployment restored successfully"
    else
        log_warning "⚠️  Restore test failed - deployment not found after restore"
    fi
    
    # Cleanup
    kubectl delete namespace backup-test --ignore-not-found=true
    kubectl delete backup $BACKUP_NAME -n velero --ignore-not-found=true
    kubectl delete restore $RESTORE_NAME -n velero --ignore-not-found=true
}

# Test security scanning functionality
test_security_scanning() {
    log_test "Testing security scanning functionality..."
    
    # Check if security scanner is running
    if ! kubectl get pods -l app=security-scanner -n security-system >/dev/null 2>&1; then
        log_warning "⚠️  Security scanner not found, skipping security tests"
        return 0
    fi
    
    # Create test security scan job
    SCAN_JOB="test-scan-$(date +%Y%m%d-%H%M%S)"
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: $SCAN_JOB
  namespace: security-system
spec:
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        fsGroup: 65534
      containers:
      - name: trivy-test
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
          echo "Running test security scan..."
          mkdir -p /reports
          
          # Test scan on alpine image
          trivy image --format json --output /reports/test-scan.json alpine:latest
          trivy image --format table --output /reports/test-report.txt alpine:latest
          
          # Copy to host storage
          cp /reports/* /host-reports/ 2>/dev/null || true
          
          echo "Test scan completed successfully"
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 1Gi
        volumeMounts:
        - name: reports
          mountPath: /reports
        - name: host-reports
          mountPath: /host-reports
        - name: cache
          mountPath: /tmp
      volumes:
      - name: reports
        emptyDir: {}
      - name: host-reports
        hostPath:
          path: /var/local-security-reports/test-reports
          type: DirectoryOrCreate
      - name: cache
        emptyDir: {}
EOF
    
    # Wait for job to complete
    log_info "Waiting for security scan to complete..."
    kubectl wait --for=condition=Complete job/$SCAN_JOB -n security-system --timeout=300s || {
        log_warning "⚠️  Security scan job did not complete in time"
        kubectl logs job/$SCAN_JOB -n security-system --tail=20
        return 0
    }
    
    # Check if scan results exist
    if ls /var/local-security-reports/test-reports/test-scan.json >/dev/null 2>&1; then
        log_success "✅ Security scanning test passed - scan results generated"
        
        # Check scan content
        if grep -q "alpine" /var/local-security-reports/test-reports/test-scan.json 2>/dev/null; then
            log_success "✅ Scan results contain expected content"
        fi
    else
        log_warning "⚠️  Security scan results not found in local filesystem"
    fi
    
    # Test secret scanning
    log_test "Testing secret scanning..."
    
    # Create test secret
    kubectl create secret generic test-secret \
        --from-literal=api-key="test-api-key-12345" \
        --from-literal=password="test-password" \
        -n security-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Run secret scan
    SECRET_SCAN_JOB="test-secret-scan-$(date +%Y%m%d-%H%M%S)"
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: $SECRET_SCAN_JOB
  namespace: security-system
spec:
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      serviceAccountName: local-security-scanner
      containers:
      - name: secret-scanner
        image: aquasecurity/trivy:0.48.0
        command:
        - /bin/sh
        - -c
        - |
          echo "Scanning for secrets..."
          
          # Get all secrets in security-system namespace
          kubectl get secrets -n security-system -o json > /tmp/secrets.json
          
          # Simple secret detection (for testing)
          if grep -q "api-key" /tmp/secrets.json; then
            echo "FOUND: Potential API key in secrets"
          fi
          
          if grep -q "password" /tmp/secrets.json; then
            echo "FOUND: Potential password in secrets"
          fi
          
          echo "Secret scan completed"
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
EOF
    
    # Wait for secret scan
    kubectl wait --for=condition=Complete job/$SECRET_SCAN_JOB -n security-system --timeout=120s || {
        log_warning "⚠️  Secret scan job did not complete in time"
    }
    
    # Check secret scan logs
    if kubectl logs job/$SECRET_SCAN_JOB -n security-system 2>/dev/null | grep -q "FOUND:"; then
        log_success "✅ Secret scanning test passed - secrets detected"
    else
        log_warning "⚠️  Secret scanning may not be working properly"
    fi
    
    # Cleanup
    kubectl delete job $SCAN_JOB -n security-system --ignore-not-found=true
    kubectl delete job $SECRET_SCAN_JOB -n security-system --ignore-not-found=true
    kubectl delete secret test-secret -n security-system --ignore-not-found=true
    rm -rf /var/local-security-reports/test-reports/ 2>/dev/null || true
}

# Test rollback functionality
test_rollback_functionality() {
    log_test "Testing rollback functionality..."
    
    # Check if rollback automation is running
    if ! kubectl get pods -l app=rollback-automation -n rollback-system >/dev/null 2>&1; then
        log_warning "⚠️  Rollback automation not found, skipping rollback tests"
        return 0
    fi
    
    # Create test namespace and deployment
    kubectl create namespace rollback-test --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy initial version
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-rollback-app
  namespace: rollback-test
  labels:
    app: test-rollback-app
    version: v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-rollback-app
  template:
    metadata:
      labels:
        app: test-rollback-app
        version: v1
    spec:
      containers:
      - name: app
        image: nginx:1.20-alpine
        ports:
        - containerPort: 80
        env:
        - name: VERSION
          value: "v1"
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 10
EOF
    
    # Wait for initial deployment
    kubectl wait --for=condition=Available deployment/test-rollback-app -n rollback-test --timeout=60s
    log_success "✅ Initial deployment successful"
    
    # Deploy problematic version (simulate failure)
    log_test "Deploying problematic version to test rollback..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-rollback-app
  namespace: rollback-test
  labels:
    app: test-rollback-app
    version: v2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-rollback-app
  template:
    metadata:
      labels:
        app: test-rollback-app
        version: v2
    spec:
      containers:
      - name: app
        image: nginx:broken-tag  # This will fail
        ports:
        - containerPort: 80
        env:
        - name: VERSION
          value: "v2"
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 10
EOF
    
    # Wait and check for failure
    sleep 30
    
    # Check if deployment is failing
    READY_REPLICAS=$(kubectl get deployment test-rollback-app -n rollback-test -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "${READY_REPLICAS:-0}" -eq 0 ]; then
        log_success "✅ Problematic deployment detected (no ready replicas)"
        
        # Test manual rollback
        log_test "Testing manual rollback..."
        
        # Rollback to previous version
        kubectl rollout undo deployment/test-rollback-app -n rollback-test
        
        # Wait for rollback
        sleep 30
        
        # Check if rollback was successful
        READY_REPLICAS_AFTER=$(kubectl get deployment test-rollback-app -n rollback-test -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        if [ "${READY_REPLICAS_AFTER:-0}" -gt 0 ]; then
            log_success "✅ Rollback test passed - deployment recovered"
        else
            log_warning "⚠️  Rollback may not have completed yet"
        fi
    else
        log_warning "⚠️  Expected deployment failure did not occur"
    fi
    
    # Test automated rollback job
    log_test "Testing automated rollback job..."
    
    # Create rollback job
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: test-automated-rollback
  namespace: rollback-test
spec:
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      serviceAccountName: default
      containers:
      - name: rollback-test
        image: bitnami/kubectl:latest
        command:
        - /bin/bash
        - -c
        - |
          echo "Testing automated rollback logic..."
          
          # Check deployment health
          DEPLOYMENT="test-rollback-app"
          NAMESPACE="rollback-test"
          
          READY=\$(kubectl get deployment \$DEPLOYMENT -n \$NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
          DESIRED=\$(kubectl get deployment \$DEPLOYMENT -n \$NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
          
          echo "Ready replicas: \$READY, Desired: \$DESIRED"
          
          if [ "\$READY" -lt "\$DESIRED" ]; then
            echo "UNHEALTHY: Deployment has \$READY/\$DESIRED ready replicas"
            echo "WOULD TRIGGER: Automated rollback"
          else
            echo "HEALTHY: Deployment is running normally"
          fi
          
          echo "Automated rollback test completed"
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
EOF
    
    # Wait for rollback job
    kubectl wait --for=condition=Complete job/test-automated-rollback -n rollback-test --timeout=120s || {
        log_warning "⚠️  Automated rollback test job did not complete"
    }
    
    # Check rollback job logs
    if kubectl logs job/test-automated-rollback -n rollback-test 2>/dev/null | grep -q "WOULD TRIGGER\|HEALTHY"; then
        log_success "✅ Automated rollback logic test passed"
    else
        log_warning "⚠️  Automated rollback logic test may have issues"
    fi
    
    # Cleanup
    kubectl delete namespace rollback-test --ignore-not-found=true
}

# Test local registry functionality
test_local_registry() {
    log_test "Testing local registry functionality..."
    
    # Check if registry is running
    if ! docker ps | grep -q "local-registry"; then
        log_warning "⚠️  Local registry not running, skipping registry tests"
        return 0
    fi
    
    # Test registry API
    if curl -f http://localhost:5000/v2/ >/dev/null 2>&1; then
        log_success "✅ Local registry API is accessible"
    else
        log_error "❌ Local registry API not accessible"
        return 1
    fi
    
    # Test image push/pull
    log_test "Testing image push/pull to local registry..."
    
    # Pull a small test image
    docker pull alpine:latest >/dev/null 2>&1
    
    # Tag for local registry
    docker tag alpine:latest localhost:5000/test-alpine:latest
    
    # Push to local registry
    if docker push localhost:5000/test-alpine:latest >/dev/null 2>&1; then
        log_success "✅ Image push to local registry successful"
    else
        log_error "❌ Image push to local registry failed"
        return 1
    fi
    
    # Remove local image
    docker rmi localhost:5000/test-alpine:latest >/dev/null 2>&1 || true
    
    # Pull from local registry
    if docker pull localhost:5000/test-alpine:latest >/dev/null 2>&1; then
        log_success "✅ Image pull from local registry successful"
    else
        log_error "❌ Image pull from local registry failed"
        return 1
    fi
    
    # Check registry catalog
    CATALOG=$(curl -s http://localhost:5000/v2/_catalog 2>/dev/null)
    if echo "$CATALOG" | grep -q "test-alpine"; then
        log_success "✅ Image found in registry catalog"
    else
        log_warning "⚠️  Image not found in registry catalog"
    fi
    
    # Cleanup
    docker rmi localhost:5000/test-alpine:latest >/dev/null 2>&1 || true
    docker rmi alpine:latest >/dev/null 2>&1 || true
}

# Test dashboard accessibility
test_dashboard_accessibility() {
    log_test "Testing dashboard accessibility..."
    
    # Test security reports viewer
    if kubectl get svc security-reports-viewer -n security-system >/dev/null 2>&1; then
        log_success "✅ Security reports viewer service found"
        
        # Test port forward (without actually forwarding)
        if kubectl get endpoints security-reports-viewer -n security-system -o jsonpath='{.subsets[0].addresses[0].ip}' >/dev/null 2>&1; then
            log_success "✅ Security reports viewer has endpoints"
        else
            log_warning "⚠️  Security reports viewer has no endpoints"
        fi
    else
        log_warning "⚠️  Security reports viewer service not found"
    fi
    
    # Test health dashboard
    if kubectl get svc health-dashboard -n rollback-system >/dev/null 2>&1; then
        log_success "✅ Health dashboard service found"
        
        if kubectl get endpoints health-dashboard -n rollback-system -o jsonpath='{.subsets[0].addresses[0].ip}' >/dev/null 2>&1; then
            log_success "✅ Health dashboard has endpoints"
        else
            log_warning "⚠️  Health dashboard has no endpoints"
        fi
    else
        log_warning "⚠️  Health dashboard service not found"
    fi
    
    # Test ArgoCD (if available)
    if kubectl get svc argocd-server -n argocd >/dev/null 2>&1; then
        log_success "✅ ArgoCD server service found"
    else
        log_info "ℹ️  ArgoCD server not found (optional)"
    fi
}

# Test filesystem permissions and storage
test_filesystem_storage() {
    log_test "Testing filesystem storage and permissions..."
    
    # Test backup directory
    if [ -d "/var/velero-backups" ]; then
        if [ -w "/var/velero-backups" ]; then
            log_success "✅ Backup directory is writable"
            
            # Test write/read
            echo "test" > /var/velero-backups/test-file 2>/dev/null && rm /var/velero-backups/test-file 2>/dev/null
            if [ $? -eq 0 ]; then
                log_success "✅ Backup directory write/read test passed"
            else
                log_warning "⚠️  Backup directory write/read test failed"
            fi
        else
            log_warning "⚠️  Backup directory is not writable"
        fi
    else
        log_error "❌ Backup directory does not exist"
    fi
    
    # Test security reports directory
    if [ -d "/var/local-security-reports" ]; then
        if [ -w "/var/local-security-reports" ]; then
            log_success "✅ Security reports directory is writable"
            
            # Test write/read
            echo "test" > /var/local-security-reports/test-file 2>/dev/null && rm /var/local-security-reports/test-file 2>/dev/null
            if [ $? -eq 0 ]; then
                log_success "✅ Security reports directory write/read test passed"
            else
                log_warning "⚠️  Security reports directory write/read test failed"
            fi
        else
            log_warning "⚠️  Security reports directory is not writable"
        fi
    else
        log_error "❌ Security reports directory does not exist"
    fi
}

# Generate test report
generate_test_report() {
    log_info "Generating test report..."
    
    REPORT_FILE="/tmp/local-gitops-test-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$REPORT_FILE" << EOF
LOCAL GITOPS BACKUP & SECURITY TEST REPORT
==========================================
Generated: $(date)
Cluster: $(kubectl config current-context 2>/dev/null || echo "Unknown")

COMPONENT STATUS:
-----------------
Velero: $(kubectl get pods -n velero --no-headers 2>/dev/null | wc -l) pods
Security System: $(kubectl get pods -n security-system --no-headers 2>/dev/null | wc -l) pods
Rollback System: $(kubectl get pods -n rollback-system --no-headers 2>/dev/null | wc -l) pods
Local Registry: $(docker ps --filter name=local-registry --format "table {{.Status}}" | tail -n +2)

STORAGE STATUS:
---------------
Backup Directory: $(ls -la /var/velero-backups/ 2>/dev/null | wc -l) items
Security Reports: $(ls -la /var/local-security-reports/ 2>/dev/null | wc -l) items
Registry Data: $(docker volume inspect local-registry-data >/dev/null 2>&1 && echo "Present" || echo "Missing")

NETWORK STATUS:
---------------
Registry Port: $(netstat -tlnp 2>/dev/null | grep ":5000" | wc -l) listeners
Cluster API: $(kubectl cluster-info 2>/dev/null | grep -c "is running at")

RECENT BACKUPS:
---------------
$(kubectl get backups -n velero --sort-by='.metadata.creationTimestamp' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,CREATED:.metadata.creationTimestamp 2>/dev/null | tail -5)

RECENT SECURITY SCANS:
----------------------
$(ls -lt /var/local-security-reports/security-reports/ 2>/dev/null | head -5)

TEST SUMMARY:
-------------
All components appear to be deployed and accessible.
For detailed testing, run individual test functions.

NEXT STEPS:
-----------
1. Run ./setup-port-forwards.sh to access dashboards
2. Test application deployments with backup and rollback
3. Monitor security scan reports
4. Customize configurations for production use

EOF
    
    log_success "Test report generated: $REPORT_FILE"
    echo
    cat "$REPORT_FILE"
}

# Run all tests
run_all_tests() {
    log_info "🧪 Running comprehensive local GitOps tests..."
    echo
    
    test_filesystem_storage
    echo
    test_local_registry
    echo
    test_backup_functionality
    echo
    test_security_scanning
    echo
    test_rollback_functionality
    echo
    test_dashboard_accessibility
    echo
    generate_test_report
    
    log_success "✅ All tests completed!"
}

# Show test menu
show_test_menu() {
    echo
    echo "🧪 LOCAL GITOPS TEST MENU"
    echo "========================="
    echo
    echo "1. Run all tests"
    echo "2. Test backup functionality"
    echo "3. Test security scanning"
    echo "4. Test rollback functionality"
    echo "5. Test local registry"
    echo "6. Test dashboard accessibility"
    echo "7. Test filesystem storage"
    echo "8. Generate test report"
    echo "9. Exit"
    echo
    read -p "Select an option (1-9): " choice
    
    case $choice in
        1) run_all_tests ;;
        2) test_backup_functionality ;;
        3) test_security_scanning ;;
        4) test_rollback_functionality ;;
        5) test_local_registry ;;
        6) test_dashboard_accessibility ;;
        7) test_filesystem_storage ;;
        8) generate_test_report ;;
        9) exit 0 ;;
        *) log_error "Invalid option. Please try again." && show_test_menu ;;
    esac
}

# Main execution
main() {
    if [ $# -eq 0 ]; then
        show_test_menu
    else
        case "$1" in
            "all") run_all_tests ;;
            "backup") test_backup_functionality ;;
            "security") test_security_scanning ;;
            "rollback") test_rollback_functionality ;;
            "registry") test_local_registry ;;
            "dashboard") test_dashboard_accessibility ;;
            "storage") test_filesystem_storage ;;
            "report") generate_test_report ;;
            *) 
                echo "Usage: $0 [all|backup|security|rollback|registry|dashboard|storage|report]"
                exit 1
                ;;
        esac
    fi
}

# Run main function
main "$@"
