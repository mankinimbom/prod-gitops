# ArgoCD Autopilot Bootstrap Configuration

## 🚀 ArgoCD Autopilot Integration

ArgoCD Autopilot helps bootstrap GitOps repositories and manages ArgoCD applications declaratively. This complements our Port.io integration by providing automated repository structure generation.

## 📁 Autopilot Repository Structure

```
gitops-bootstrap/
├── bootstrap/
│   ├── argo-cd.yaml
│   ├── argo-cd-autopilot.yaml
│   └── cluster-resources/
│       ├── in-cluster/
│       │   ├── namespace_argocd.yaml
│       │   └── namespace_port-system.yaml
│       └── overlays/
│           └── production/
├── projects/
│   ├── microservices.yaml
│   └── port-integration.yaml
└── apps/
    ├── microservices/
    │   ├── payment-service/
    │   ├── user-service/
    │   └── auth-service/
    └── platform/
        ├── port-system/
        └── monitoring/
```

## 🔧 Autopilot Configuration

### 1. Bootstrap Configuration
```yaml
# bootstrap/argo-cd-autopilot.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: autopilot-bootstrap
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io
  labels:
    app.kubernetes.io/name: autopilot-bootstrap
    app.kubernetes.io/part-of: argocd-autopilot
    managed-by: port-io
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops-bootstrap
    path: bootstrap
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

### 2. Project Configuration
```yaml
# projects/microservices.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: microservices
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd-autopilot
    managed-by: port-io
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  description: Microservices managed by Port.io
  sourceRepos:
  - 'https://github.com/your-org/*'
  destinations:
  - namespace: 'dev'
    server: 'https://kubernetes.default.svc'
  - namespace: 'staging'
    server: 'https://kubernetes.default.svc'
  - namespace: 'prod'
    server: 'https://kubernetes.default.svc'
  clusterResourceWhitelist:
  - group: ''
    kind: Namespace
  namespaceResourceWhitelist:
  - group: 'apps'
    kind: Deployment
  - group: ''
    kind: Service
  - group: ''
    kind: ConfigMap
  - group: ''
    kind: Secret
  roles:
  - name: developers
    description: Developer access to dev environment
    policies:
    - p, proj:microservices:developers, applications, sync, microservices/*-dev, allow
    groups:
    - your-org:developers
```

### 3. Port.io System Application Template
```yaml
# apps/platform/port-system/app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: port-system
  namespace: argocd
  labels:
    app.kubernetes.io/name: port-system
    app.kubernetes.io/part-of: port-integration
    managed-by: autopilot
  annotations:
    autopilot.argoproj.io/git-path: apps/platform/port-system
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: port-integration
  source:
    repoURL: https://github.com/your-org/gitops-bootstrap
    path: apps/platform/port-system
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
```

## 🛠️ Autopilot CLI Commands

### Bootstrap Repository
```bash
# Initialize Autopilot repository
argocd-autopilot repo bootstrap \
    --repo https://github.com/your-org/gitops-bootstrap \
    --git-token $GIT_TOKEN \
    --argocd-server argo.annkinimbom.com \
    --insecure

# Create projects
argocd-autopilot project create microservices \
    --git-token $GIT_TOKEN

argocd-autopilot project create port-integration \
    --git-token $GIT_TOKEN
```

### Application Management
```bash
# Create application from local manifests
argocd-autopilot app create backend \
    --app ./apps/microservices/backend \
    --project microservices \
    --git-token $GIT_TOKEN

# Create application from remote repository
argocd-autopilot app create frontend \
    --repo https://github.com/your-org/frontend-configs \
    --path manifests \
    --project microservices \
    --git-token $GIT_TOKEN
```

## 🔄 Enhanced Port.io Controller with Autopilot Support

### Controller Configuration
```yaml
# Enhanced controller configuration for Autopilot
apiVersion: v1
kind: ConfigMap
metadata:
  name: port-gitops-config
  namespace: port-system
data:
  autopilot.enabled: "true"
  autopilot.repo: "https://github.com/your-org/gitops-bootstrap"
  autopilot.projects.microservices: "microservices"
  autopilot.projects.platform: "port-integration"
  
  # Port.io webhook endpoints
  port.webhook.create: "/webhooks/port/create"
  port.webhook.deploy: "/webhooks/port/deploy"
  port.webhook.promote: "/webhooks/port/promote"
  
  # ArgoCD integration
  argocd.server: "argo.annkinimbom.com"
  argocd.namespace: "argocd"
```

### Enhanced Webhook Handlers (Go Code)
```go
// pkg/autopilot/client.go
package autopilot

import (
    "context"
    "fmt"
    "os/exec"
)

type AutopilotClient struct {
    repo      string
    gitToken  string
    server    string
}

func NewAutopilotClient(repo, token, server string) *AutopilotClient {
    return &AutopilotClient{
        repo:     repo,
        gitToken: token,
        server:   server,
    }
}

func (c *AutopilotClient) CreateApplication(ctx context.Context, name, project, path string) error {
    cmd := exec.CommandContext(ctx, "argocd-autopilot", "app", "create", name,
        "--app", path,
        "--project", project,
        "--git-token", c.gitToken,
    )
    
    output, err := cmd.CombinedOutput()
    if err != nil {
        return fmt.Errorf("autopilot app create failed: %w, output: %s", err, string(output))
    }
    
    return nil
}

func (c *AutopilotClient) CreateProject(ctx context.Context, name string) error {
    cmd := exec.CommandContext(ctx, "argocd-autopilot", "project", "create", name,
        "--git-token", c.gitToken,
    )
    
    output, err := cmd.CombinedOutput()
    if err != nil {
        return fmt.Errorf("autopilot project create failed: %w, output: %s", err, string(output))
    }
    
    return nil
}
```

### Webhook Handler Integration
```go
// Enhanced webhook handler with Autopilot support
func (h *WebhookHandler) handleCreateMicroservice(w http.ResponseWriter, r *http.Request) {
    var payload struct {
        ServiceName string `json:"serviceName"`
        Repository  string `json:"repository"`
        Environment string `json:"environment"`
    }
    
    if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    
    // Create application using Autopilot
    if h.autopilotEnabled {
        err := h.autopilotClient.CreateApplication(r.Context(),
            fmt.Sprintf("%s-%s", payload.ServiceName, payload.Environment),
            "microservices",
            fmt.Sprintf("./apps/microservices/%s/%s", payload.ServiceName, payload.Environment),
        )
        if err != nil {
            log.Printf("Failed to create application via Autopilot: %v", err)
            // Fall back to direct ArgoCD API
        }
    }
    
    // Continue with existing logic...
}
```

## 📋 Autopilot Directory Structure for Port.io

```
apps/
├── microservices/
│   ├── backend/
│   │   ├── dev/
│   │   │   ├── app.yaml
│   │   │   └── kustomization.yaml
│   │   ├── staging/
│   │   └── prod/
│   └── frontend/
│       ├── dev/
│       ├── staging/
│       └── prod/
└── platform/
    ├── port-system/
    │   ├── app.yaml
    │   └── manifests/
    │       ├── controller.yaml
    │       ├── blueprints.yaml
    │       └── rbac.yaml
    └── monitoring/
        ├── app.yaml
        └── manifests/
```

## 🚀 Deployment with Autopilot

### 1. Setup Script
```bash
#!/bin/bash
# setup-autopilot-bootstrap.sh

set -e

# Configuration
REPO_URL="https://github.com/your-org/gitops-bootstrap"
ARGOCD_SERVER="argo.annkinimbom.com"

echo "🚀 Setting up ArgoCD Autopilot Bootstrap"

# Install Autopilot if not present
if ! command -v argocd-autopilot &> /dev/null; then
    echo "Installing ArgoCD Autopilot..."
    curl -L --output - "https://github.com/argoproj-labs/argocd-autopilot/releases/latest/download/argocd-autopilot-linux-amd64.tar.gz" | tar zx
    sudo mv ./argocd-autopilot-* /usr/local/bin/argocd-autopilot
fi

# Bootstrap repository
echo "Bootstrapping Autopilot repository..."
argocd-autopilot repo bootstrap \
    --repo "$REPO_URL" \
    --git-token "$GIT_TOKEN" \
    --argocd-server "$ARGOCD_SERVER" \
    --insecure

# Create projects
echo "Creating projects..."
argocd-autopilot project create microservices --git-token "$GIT_TOKEN"
argocd-autopilot project create port-integration --git-token "$GIT_TOKEN"

# Create Port.io system application
echo "Creating Port.io system application..."
argocd-autopilot app create port-system \
    --app ./apps/platform/port-system \
    --project port-integration \
    --git-token "$GIT_TOKEN"

echo "✅ Autopilot bootstrap complete!"
```

### 2. Integration with Existing Setup
```bash
# Move existing manifests to Autopilot structure
mkdir -p apps/platform/port-system/manifests
cp ../port-integration/port-*.yaml apps/platform/port-system/manifests/

# Update paths in ArgoCD applications
find apps/ -name "*.yaml" -exec sed -i "s|repoURL: .*|repoURL: $REPO_URL|g" {} \;
```

## 🔍 Monitoring and Verification

### Check Autopilot Status
```bash
# List projects
argocd-autopilot project list

# List applications
argocd-autopilot app list

# Check repository status
argocd-autopilot repo get

# Verify ArgoCD applications
kubectl get applications -n argocd -l app.kubernetes.io/part-of=argocd-autopilot
```

### Port.io Integration Verification
```bash
# Check Port.io controller logs
kubectl logs -f deployment/port-gitops-controller -n port-system

# Test webhook endpoints
curl -X POST http://port-gitops-controller.port-system.svc.cluster.local:8080/webhooks/port/create \
  -H "Content-Type: application/json" \
  -d '{"serviceName": "test-service", "repository": "https://github.com/test/repo"}'
```

## 🎯 Benefits of Autopilot Integration

1. **Automated Repository Management**: Autopilot handles GitOps repository structure
2. **Declarative Application Management**: Applications managed as code
3. **Enhanced Port.io Integration**: Seamless webhook-to-Autopilot flow
4. **Simplified Scaling**: Easy addition of new services and environments
5. **Consistent Structure**: Standardized application and project layout
6. **Git-Driven**: All changes tracked in Git with full audit trail

This configuration provides a complete ArgoCD Autopilot setup that integrates seamlessly with the Port.io Internal Developer Platform, enabling fully automated GitOps workflows.
