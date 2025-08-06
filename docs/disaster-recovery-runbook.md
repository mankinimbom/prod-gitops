# 🛡️ Disaster Recovery Runbook

## 📋 Overview

This runbook provides step-by-step procedures for recovering from various disaster scenarios in your GitOps environment.

### 🎯 Recovery Objectives
- **RTO (Recovery Time Objective)**: 4 hours
- **RPO (Recovery Point Objective)**: 24 hours
- **Availability Target**: 99.9%

---

## 🚨 Emergency Response Procedures

### 1. Immediate Response (0-15 minutes)

#### 🔍 Assessment Phase
```bash
# Check cluster status
kubectl cluster-info
kubectl get nodes

# Check critical namespaces
kubectl get pods -n prod
kubectl get pods -n argocd
kubectl get pods -n monitoring

# Check ArgoCD applications
kubectl get applications -n argocd
argocd app list
```

#### 📞 Communication
1. **Alert the team**: Use your incident management system
2. **Create incident channel**: Set up dedicated communication channel
3. **Notify stakeholders**: Inform relevant business stakeholders

### 2. Triage and Diagnosis (15-30 minutes)

#### 🏥 Health Checks
```bash
# Check application health
argocd app get prod-backend
argocd app get prod-frontend

# Check sync status
argocd app sync-status prod-backend
argocd app sync-status prod-frontend

# Review recent events
kubectl get events --sort-by='.lastTimestamp' -n prod
kubectl get events --sort-by='.lastTimestamp' -n argocd
```

#### 📊 Metrics Review
```bash
# Check Prometheus alerts
curl -s http://prometheus.monitoring.svc.cluster.local:9090/api/v1/alerts

# Review application metrics
curl -s "http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query?query=up{job='backend'}"
curl -s "http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query?query=up{job='frontend'}"
```

---

## 🔄 Recovery Scenarios

### Scenario 1: ArgoCD Server Failure

#### Symptoms
- ArgoCD UI inaccessible
- Applications not syncing
- GitOps automation stopped

#### Recovery Steps
```bash
# 1. Check ArgoCD pods
kubectl get pods -n argocd

# 2. Restart ArgoCD components
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout restart deployment/argocd-application-controller -n argocd
kubectl rollout restart deployment/argocd-repo-server -n argocd

# 3. Wait for pods to be ready
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=server -n argocd --timeout=300s

# 4. Verify ArgoCD functionality
argocd app list
argocd app sync --all
```

#### If Complete Reinstallation Required
```bash
# 1. Backup current state (if possible)
kubectl get applications -n argocd -o yaml > argocd-apps-backup.yaml
kubectl get appprojects -n argocd -o yaml > argocd-projects-backup.yaml

# 2. Reinstall ArgoCD
kubectl delete namespace argocd
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. Restore configurations
kubectl apply -f argocd/argocd-server-ha.yaml
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/app-of-apps.yaml

# 4. Restore applications
kubectl apply -f argocd-apps-backup.yaml
kubectl apply -f argocd-projects-backup.yaml
```

### Scenario 2: Application Deployment Failure

#### Symptoms
- Application pods not starting
- Health checks failing
- High error rates

#### Immediate Rollback
```bash
# 1. Check current application status
argocd app get prod-backend

# 2. Get revision history
argocd app history prod-backend

# 3. Rollback to previous working version
LAST_GOOD_REVISION=$(argocd app history prod-backend | grep -v "REVISION" | head -2 | tail -1 | awk '{print $1}')
argocd app rollback prod-backend $LAST_GOOD_REVISION

# 4. Force sync to ensure changes apply
argocd app sync prod-backend --force
```

#### Manual Rollback via Git
```bash
# 1. Clone GitOps repository
git clone https://github.com/mankinimbom/prod-gitops.git
cd prod-gitops

# 2. Revert to last known good commit
git log --oneline -10  # Find last good commit
LAST_GOOD_COMMIT="abc123"  # Replace with actual commit hash
git revert HEAD...$LAST_GOOD_COMMIT

# 3. Push changes
git push origin main

# 4. Wait for ArgoCD to sync
argocd app sync prod-backend
```

### Scenario 3: Complete Cluster Failure

#### Recovery from Velero Backup
```bash
# 1. Create new cluster (cluster-specific steps)
# Follow your cloud provider's cluster creation process

# 2. Install Velero on new cluster
./scripts/setup-backup-security.sh

# 3. List available backups
velero backup get

# 4. Restore from latest backup
LATEST_BACKUP=$(velero backup get --output json | jq -r '.items | sort_by(.metadata.creationTimestamp) | last | .metadata.name')
velero restore create restore-$(date +%Y%m%d-%H%M%S) --from-backup $LATEST_BACKUP

# 5. Monitor restore progress
velero restore get
velero restore describe restore-$(date +%Y%m%d-%H%M%S)

# 6. Verify applications
kubectl get pods -n prod
kubectl get pods -n argocd
argocd app list
```

### Scenario 4: Data Corruption

#### Database Recovery
```bash
# 1. Scale down applications
kubectl scale deployment backend --replicas=0 -n prod

# 2. Restore database from backup
# (Database-specific restore procedures)

# 3. Verify data integrity
# (Application-specific verification)

# 4. Scale applications back up
kubectl scale deployment backend --replicas=3 -n prod

# 5. Monitor application health
kubectl get pods -n prod -w
```

### Scenario 5: Security Incident

#### Immediate Response
```bash
# 1. Isolate affected components
kubectl patch networkpolicy prod-network-policy -n prod --patch '{"spec":{"ingress":[],"egress":[]}}'

# 2. Scale down affected applications
kubectl scale deployment backend --replicas=0 -n prod
kubectl scale deployment frontend --replicas=0 -n prod

# 3. Analyze security scans
kubectl get vulnerabilityreports -A
kubectl describe vulnerabilityreport <report-name>

# 4. Check for exposed secrets
kubectl get secrets -A -o yaml | grep -i "password\|token\|key"
```

#### Recovery After Security Review
```bash
# 1. Update images with security fixes
# (Update image tags in GitOps repository)

# 2. Rotate all secrets
kubectl delete secret backend-secrets -n prod
kubectl apply -f secrets/backend-secrets-enhanced.yaml

# 3. Restore network policies
kubectl apply -f namespace/network-policy.yaml

# 4. Scale applications back up
kubectl scale deployment backend --replicas=3 -n prod
kubectl scale deployment frontend --replicas=3 -n prod
```

---

## 🔧 Automation Scripts

### Automated Health Check Script
```bash
#!/bin/bash
# health-check.sh

check_argocd() {
    echo "Checking ArgoCD health..."
    kubectl get pods -n argocd | grep -v Running && return 1
    argocd app list | grep -v Healthy && return 1
    return 0
}

check_applications() {
    echo "Checking application health..."
    kubectl get pods -n prod | grep -v Running && return 1
    return 0
}

check_backups() {
    echo "Checking backup status..."
    LATEST_BACKUP=$(velero backup get --output json | jq -r '.items | sort_by(.metadata.creationTimestamp) | last')
    BACKUP_STATUS=$(echo $LATEST_BACKUP | jq -r '.status.phase')
    [ "$BACKUP_STATUS" != "Completed" ] && return 1
    return 0
}

main() {
    check_argocd || echo "❌ ArgoCD issues detected"
    check_applications || echo "❌ Application issues detected"
    check_backups || echo "❌ Backup issues detected"
    echo "✅ Health check completed"
}

main
```

### Automated Rollback Script
```bash
#!/bin/bash
# auto-rollback.sh

APP_NAME="$1"
HEALTH_THRESHOLD=300  # 5 minutes

if [ -z "$APP_NAME" ]; then
    echo "Usage: $0 <app-name>"
    exit 1
fi

# Monitor application health
start_time=$(date +%s)
while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    # Check if app is healthy
    HEALTH_STATUS=$(argocd app get $APP_NAME -o json | jq -r '.status.health.status')
    
    if [ "$HEALTH_STATUS" == "Healthy" ]; then
        echo "✅ Application $APP_NAME is healthy"
        break
    fi
    
    # If unhealthy for more than threshold, rollback
    if [ $elapsed -gt $HEALTH_THRESHOLD ]; then
        echo "🔄 Rolling back $APP_NAME due to health issues"
        LAST_REVISION=$(argocd app history $APP_NAME | grep -v "REVISION" | head -2 | tail -1 | awk '{print $1}')
        argocd app rollback $APP_NAME $LAST_REVISION
        break
    fi
    
    sleep 30
done
```

---

## 📞 Emergency Contacts

### Primary Contacts
- **DevOps Team Lead**: devops-lead@company.com
- **Platform Team**: platform@company.com
- **Security Team**: security@company.com

### Escalation Matrix
1. **L1 - On-call Engineer** (0-30 minutes)
2. **L2 - Senior Engineer** (30-60 minutes)
3. **L3 - Team Lead** (1-2 hours)
4. **L4 - Management** (2+ hours)

### External Vendors
- **Cloud Provider Support**: [Support portal link]
- **Monitoring Vendor**: [Support contact]
- **Security Vendor**: [Emergency contact]

---

## 📚 Additional Resources

### Documentation Links
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Velero Documentation](https://velero.io/docs/)
- [Kubernetes Troubleshooting](https://kubernetes.io/docs/tasks/debug-application-cluster/)

### Monitoring Dashboards
- **Grafana**: [Grafana URL]
- **ArgoCD UI**: [ArgoCD URL]
- **Prometheus**: [Prometheus URL]

### Log Aggregation
- **Application Logs**: [Log platform URL]
- **Infrastructure Logs**: [Infrastructure logs URL]
- **Security Logs**: [Security platform URL]

---

## 🧪 Recovery Testing

### Monthly DR Tests
1. **Backup Verification**: Restore from backup to staging
2. **Application Rollback**: Test rollback procedures
3. **Security Incident**: Simulate security response
4. **Communication**: Test incident response communication

### Quarterly Full DR Exercises
1. **Complete Cluster Recreation**: Full disaster simulation
2. **Multi-component Failure**: Complex failure scenarios
3. **Recovery Time Measurement**: Validate RTO/RPO targets
4. **Process Improvement**: Update procedures based on lessons learned

---

## 📝 Post-Incident Procedures

### Immediate Post-Recovery (0-2 hours)
1. **Verify Full Functionality**: All systems operational
2. **Monitor Stability**: Watch for any recurring issues
3. **Document Timeline**: Record all actions taken
4. **Communicate Status**: Update stakeholders

### Post-Incident Review (24-48 hours)
1. **Root Cause Analysis**: Determine what caused the incident
2. **Process Review**: Evaluate response effectiveness
3. **Action Items**: Identify improvements needed
4. **Documentation Update**: Update runbooks and procedures

### Follow-up (1 week)
1. **Implement Improvements**: Address identified gaps
2. **Update Monitoring**: Add new alerts if needed
3. **Training Updates**: Update team training materials
4. **Vendor Communications**: Report issues to vendors if applicable
