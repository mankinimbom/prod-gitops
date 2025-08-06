# ArgoCD Autopilot Configuration for Port.io Integration

## 🚀 ArgoCD Autopilot Integration

ArgoCD Autopilot helps bootstrap GitOps repositories and manages ArgoCD applications declaratively. This complements our Port.io integration by providing automated repository structure generation.

## 📁 Autopilot Repository Structure

```text
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
    repoURL: https://github.com/your-org/gitops-bootstrap.git
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

### 2. Microservices Project Configuration

```yaml
# projects/microservices.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: microservices
  namespace: argocd
  labels:
    autopilot.argoproj.io/project: microservices
    managed-by: port-io
  annotations:
    port.io/project: microservices
    autopilot.argoproj.io/git-path: projects/microservices
spec:
  description: "Microservices managed by Port.io via Autopilot"
  
  sourceRepos:
  - 'https://github.com/your-org/gitops-bootstrap.git'
  - 'https://github.com/your-org/microservices-*.git'
  - 'https://charts.helm.sh/stable'
  - 'https://argoproj.github.io/argo-helm'
  
  destinations:
  - namespace: 'dev'
    server: 'https://kubernetes.default.svc'
  - namespace: 'staging' 
    server: 'https://kubernetes.default.svc'
  - namespace: 'prod'
    server: 'https://kubernetes.default.svc'
  - namespace: 'port-system'
    server: 'https://kubernetes.default.svc'
  
  clusterResourceWhitelist:
  - group: ''
    kind: Namespace
  - group: 'rbac.authorization.k8s.io'
    kind: ClusterRole
  - group: 'rbac.authorization.k8s.io'
    kind: ClusterRoleBinding
  - group: 'apiextensions.k8s.io'
    kind: CustomResourceDefinition
  
  namespaceResourceWhitelist:
  - group: '*'
    kind: '*'
  
  roles:
  - name: microservices-admin
    description: "Admin access to microservices project"
    policies:
    - p, proj:microservices:microservices-admin, applications, *, microservices/*, allow
    - p, proj:microservices:microservices-admin, repositories, *, *, allow
    groups:
    - your-org:platform-team
    - your-org:devops-team
  
  - name: microservices-developer
    description: "Developer access to microservices project"
    policies:
    - p, proj:microservices:microservices-developer, applications, get, microservices/*, allow
    - p, proj:microservices:microservices-developer, applications, sync, microservices/*-dev, allow
    - p, proj:microservices:microservices-developer, applications, sync, microservices/*-staging, allow
    groups:
    - your-org:developers
    - your-org:backend-team
    - your-org:frontend-team
```

### 3. Port.io Integration Project

```yaml
# projects/port-integration.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: port-integration
  namespace: argocd
  labels:
    autopilot.argoproj.io/project: port-integration
    managed-by: port-io
  annotations:
    port.io/project: port-integration
    autopilot.argoproj.io/git-path: projects/port-integration
spec:
  description: "Port.io platform integration components"
  
  sourceRepos:
  - 'https://github.com/your-org/gitops-bootstrap.git'
  - 'https://port-labs.github.io/helm-charts'
  
  destinations:
  - namespace: 'port-system'
    server: 'https://kubernetes.default.svc'
  - namespace: 'argocd'
    server: 'https://kubernetes.default.svc'
  
  namespaceResourceWhitelist:
  - group: '*'
    kind: '*'
  
  clusterResourceWhitelist:
  - group: 'rbac.authorization.k8s.io'
    kind: ClusterRole
  - group: 'rbac.authorization.k8s.io'
    kind: ClusterRoleBinding
  
  roles:
  - name: port-admin
    description: "Admin access to Port.io integration"
    policies:
    - p, proj:port-integration:port-admin, applications, *, port-integration/*, allow
    groups:
    - your-org:platform-team
```

## 🔄 Autopilot Application Templates

### 1. Microservice Application Template

```yaml
# apps/microservices/_template.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: '{{.ServiceName}}-{{.Environment}}'
  namespace: argocd
  labels:
    app.kubernetes.io/name: '{{.ServiceName}}'
    app.kubernetes.io/environment: '{{.Environment}}'
    autopilot.argoproj.io/app-name: '{{.ServiceName}}-{{.Environment}}'
    managed-by: port-io
  annotations:
    port.io/entity: '{{.ServiceName}}'
    port.io/environment: '{{.Environment}}'
    autopilot.argoproj.io/git-path: 'apps/microservices/{{.ServiceName}}/{{.Environment}}'
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: microservices
  source:
    repoURL: 'https://github.com/your-org/microservices-{{.ServiceName}}.git'
    path: 'manifests/{{.Environment}}'
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: '{{.Environment}}'
  syncPolicy:
    automated:
      prune: true
      selfHeal: '{{.AutoSync}}'
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### 2. Port.io System Application

```yaml
# apps/platform/port-system/app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: port-system
  namespace: argocd
  labels:
    autopilot.argoproj.io/app-name: port-system
    managed-by: autopilot
  annotations:
    autopilot.argoproj.io/git-path: apps/platform/port-system
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: port-integration
  source:
    repoURL: https://github.com/your-org/gitops-bootstrap.git
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

## 🛠️ Enhanced Controller with Autopilot Support

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

```text
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

## 🚀 Integration Benefits

### ✅ **Automated Repository Management**
- Git Structure: Automatically generates GitOps repository structure
- Application Lifecycle: Manages application creation, updates, and deletion
- Branch Management: Handles Git operations and PR workflows

### ✅ **Enhanced Port.io Integration**  
- Template-Driven: Uses templates for consistent application generation
- Project Organization: Organizes applications by projects and teams
- Automated Sync: Integrates with Port.io actions for app creation

### ✅ **Enterprise Governance**
- Standardized Structure: Enforces consistent GitOps patterns
- RBAC Integration: Works with existing ArgoCD RBAC
- Audit Trail: Complete Git history of all changes

## 🎯 Usage Workflow

1. **Bootstrap**: Use Autopilot to create initial GitOps repository
2. **Port.io Integration**: Controller uses Autopilot for app creation
3. **Developer Self-Service**: Port.io actions trigger Autopilot commands
4. **Automated Management**: Autopilot handles Git operations and ArgoCD sync

This Autopilot integration completes your GitOps platform by providing automated repository bootstrap and management capabilities alongside the Port.io developer experience! 🚀
