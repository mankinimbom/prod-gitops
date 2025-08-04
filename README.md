# Production GitOps Repository

This repository contains the ArgoCD configuration and Kubernetes manifests for the production environment.

## 🏗️ Repository Structure

```
prod-gitops/
├── argocd/                    # ArgoCD configuration
│   ├── project.yaml           # AppProject definition
│   ├── app-of-apps.yaml       # Root application
│   ├── applicationset.yaml    # ApplicationSet for automated app discovery
│   ├── kustomization.yaml     # ArgoCD kustomization
│   └── apps/                  # Individual application definitions
│       ├── namespace.yaml     # Namespace application
│       ├── secrets.yaml       # Secrets application
│       ├── backend.yaml       # Backend application
│       ├── frontend.yaml      # Frontend application
│       └── kustomization.yaml # Apps kustomization
├── apps/                      # Application manifests
│   ├── backend/               # Backend service
│   │   ├── base/             # Base configuration
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   ├── serviceaccount.yaml
│   │   │   └── kustomization.yaml
│   │   └── overlays/         # Environment-specific overrides
│   │       └── prod/
│   │           └── kustomization.yaml
│   └── frontend/             # Frontend service
│       ├── base/             # Base configuration
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   ├── serviceaccount.yaml
│       │   ├── nginx-config.yaml
│       │   └── kustomization.yaml
│       └── overlays/         # Environment-specific overrides
│           └── prod/
│               └── kustomization.yaml
├── namespace/                 # Namespace and network policies
│   ├── prod-namespace.yaml
│   ├── network-policy.yaml
│   └── kustomization.yaml
├── secrets/                   # Application secrets
│   ├── backend-secrets.yaml
│   └── kustomization.yaml
├── rollouts/                  # Argo Rollouts configurations
│   ├── backend-rollout.yaml
│   └── frontend-rollout.yaml
├── image-updater/             # ArgoCD Image Updater config
│   └── config.yaml
└── validate-gitops-enhanced.sh  # Validation script
```

## 🚀 Deployment Instructions

### Prerequisites

1. **Kubernetes Cluster**: Ensure you have a running Kubernetes cluster with:
   - ArgoCD installed
   - Argo Rollouts installed (optional, for advanced deployments)
   - ArgoCD Image Updater installed (optional, for automated image updates)

2. **Access**: Ensure you have appropriate RBAC permissions to create resources in the `argocd` and `prod` namespaces.

### Step 1: Validation

Run the validation script to check for configuration issues:

```bash
chmod +x validate-gitops-enhanced.sh
./validate-gitops-enhanced.sh
```

### Step 2: Deploy ArgoCD Configuration

1. **Apply the AppProject**:
   ```bash
   kubectl apply -f argocd/project.yaml
   ```

2. **Deploy the App-of-Apps**:
   ```bash
   kubectl apply -f argocd/app-of-apps.yaml
   ```

3. **Optional: Deploy ApplicationSet** (for automated discovery):
   ```bash
   kubectl apply -f argocd/applicationset.yaml
   ```

### Step 3: Verify Deployment

1. **Check ArgoCD Applications**:
   ```bash
   kubectl get applications -n argocd
   ```

2. **Check Application Status**:
   ```bash
   argocd app list
   argocd app get prod-backend
   argocd app get prod-frontend
   ```

3. **Verify Resources in Production Namespace**:
   ```bash
   kubectl get all -n prod
   ```

## 🔧 Configuration Details

### Security Features

- **Service Accounts**: Each deployment uses dedicated service accounts
- **Security Contexts**: Non-root users, read-only filesystems, dropped capabilities
- **Network Policies**: Restricted ingress/egress traffic
- **Resource Limits**: CPU, memory, and storage limits defined
- **Health Probes**: Readiness, liveness, and startup probes configured

### High Availability

- **Replica Counts**: 3 replicas in production overlays
- **Rolling Updates**: Configured with proper surge and unavailable settings
- **Pod Disruption Budgets**: Implicit through replica configuration
- **Health Checks**: Multiple probe types for reliability

### Monitoring & Observability

- **Prometheus Metrics**: Annotations for metric scraping
- **Labels**: Consistent labeling for monitoring and alerting
- **Health Endpoints**: Dedicated health check endpoints

### GitOps Best Practices

- **Separation of Concerns**: Base configurations and environment overlays
- **Kustomization**: Proper use of Kustomize for configuration management
- **Sync Policies**: Automated sync with self-healing enabled
- **Revision History**: Limited revision history for clean state
- **Finalizers**: Proper cleanup with ArgoCD finalizers

## 🔄 Image Updates

### Automated Updates with ArgoCD Image Updater

The repository is configured for automated image updates using ArgoCD Image Updater:

- **Semantic Versioning**: Updates follow semver constraints (~1.0)
- **Git Integration**: Updates committed back to the repository
- **Tag Filtering**: Only allows versioned tags (v1.0.0 format)

### Manual Updates

To manually update image versions:

1. Edit the image tag in the appropriate kustomization file
2. Commit and push changes
3. ArgoCD will automatically sync the changes

## 📊 Monitoring

### Application Health

- **Health Checks**: `/healthz` for backend, `/health` for frontend
- **Metrics**: Prometheus metrics exposed on dedicated ports
- **Logs**: Structured logging with appropriate log levels

### ArgoCD Monitoring

- **Sync Status**: Monitor application sync status
- **Health Status**: Track application health in ArgoCD UI
- **Notifications**: Configure notifications for sync failures

## 🔒 Security Considerations

### Secrets Management

- **Kubernetes Secrets**: Stored as Kubernetes secrets
- **Environment Variables**: Injected via secretRef
- **Rotation**: Manual secret rotation required

### Network Security

- **Network Policies**: Restrict pod-to-pod communication
- **Service Mesh**: Consider implementing Istio for advanced security
- **TLS**: Implement TLS termination at ingress level

### RBAC

- **Service Accounts**: Dedicated service accounts per application
- **Minimal Permissions**: Principle of least privilege
- **Regular Audits**: Review and audit permissions regularly

## 🔧 Troubleshooting

### Common Issues

1. **Sync Failures**:
   ```bash
   argocd app sync <app-name> --force
   ```

2. **Resource Conflicts**:
   ```bash
   kubectl delete -f <conflicting-resource>
   ```

3. **Validation Errors**:
   ```bash
   ./validate-gitops-enhanced.sh
   ```

### Debugging

1. **Check Application Events**:
   ```bash
   kubectl describe application <app-name> -n argocd
   ```

2. **View Pod Logs**:
   ```bash
   kubectl logs -f deployment/<deployment-name> -n prod
   ```

3. **Check Resource Status**:
   ```bash
   kubectl get events -n prod --sort-by='.lastTimestamp'
   ```

## 📝 Contributing

1. **Validation**: Always run the validation script before committing
2. **Testing**: Test changes in a development environment first
3. **Documentation**: Update documentation for configuration changes
4. **Review**: Ensure proper code review for GitOps changes

## 📚 Additional Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Kustomize Documentation](https://kustomize.io/)
- [Argo Rollouts Documentation](https://argoproj.github.io/argo-rollouts/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
