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

### 2. Port.io System Applications
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

## 🛠️ Autopilot CLI Integration

### 1. Installation Script
```bash
#!/bin/bash
# install-autopilot.sh

# Install ArgoCD Autopilot CLI
curl -L --output - https://github.com/argoproj-labs/argocd-autopilot/releases/latest/download/argocd-autopilot-linux-amd64.tar.gz | tar zx
sudo mv ./argocd-autopilot-* /usr/local/bin/argocd-autopilot
chmod +x /usr/local/bin/argocd-autopilot

# Verify installation
argocd-autopilot version
```

### 2. Bootstrap Repository Setup
```bash
#!/bin/bash
# bootstrap-setup.sh

# Set environment variables
export GIT_TOKEN="your-github-token"
export GIT_REPO="https://github.com/your-org/gitops-bootstrap"
export ARGOCD_SERVER="argo.annkinimbom.com"

# Bootstrap the GitOps repository
argocd-autopilot repo bootstrap \
  --repo $GIT_REPO \
  --git-token $GIT_TOKEN \
  --argocd-server $ARGOCD_SERVER \
  --insecure

# Create microservices project
argocd-autopilot project create microservices \
  --git-token $GIT_TOKEN

# Create port-integration project  
argocd-autopilot project create port-integration \
  --git-token $GIT_TOKEN
```

### 3. Application Creation Commands
```bash
#!/bin/bash
# create-app-via-autopilot.sh

# Function to create microservice app
create_microservice_app() {
  local service_name=$1
  local environment=$2
  local auto_sync=${3:-true}
  
  argocd-autopilot app create $service_name-$environment \
    --app https://github.com/your-org/microservices-$service_name/manifests/$environment \
    --project microservices \
    --git-token $GIT_TOKEN
}

# Function to create platform app
create_platform_app() {
  local app_name=$1
  local app_path=$2
  
  argocd-autopilot app create $app_name \
    --app $app_path \
    --project port-integration \
    --git-token $GIT_TOKEN
}

# Examples
create_microservice_app "payment-service" "dev" "true"
create_microservice_app "payment-service" "staging" "true"  
create_microservice_app "payment-service" "prod" "false"

create_platform_app "port-system" "./apps/platform/port-system"
```

## 🔗 Integration with Port.io Controller

### Enhanced Controller with Autopilot Support
```go
// Add to controller/main.go

import (
    "os/exec"
    "fmt"
)

// Function to create app via autopilot
func createAppViaAutopilot(serviceName, environment string, autoSync bool) error {
    cmd := exec.Command("argocd-autopilot", "app", "create", 
        fmt.Sprintf("%s-%s", serviceName, environment),
        "--app", fmt.Sprintf("https://github.com/your-org/microservices-%s/manifests/%s", serviceName, environment),
        "--project", "microservices",
        "--git-token", os.Getenv("GIT_TOKEN"),
    )
    
    output, err := cmd.CombinedOutput()
    if err != nil {
        return fmt.Errorf("autopilot failed: %v, output: %s", err, output)
    }
    
    log.Printf("Autopilot created app: %s", output)
    return nil
}

// Enhanced handleCreateMicroservice function
func handleCreateMicroservice(c *gin.Context) {
    // ... existing code ...
    
    // Create applications for all environments using autopilot
    environments := []string{"dev", "staging", "prod"}
    for _, env := range environments {
        autoSync := env != "prod" // prod requires manual sync
        
        if err := createAppViaAutopilot(serviceName, env, autoSync); err != nil {
            log.Printf("Error creating app via autopilot: %v", err)
            // Fallback to direct ArgoCD API
            createArgoApplication(manifest, env)
        }
    }
    
    // ... rest of the function ...
}
```

## 📋 Autopilot Configuration Files

### 1. Autopilot Config
```yaml
# .argocd-autopilot.yaml
apiVersion: autopilot.argoproj.io/v1alpha1
kind: Config
metadata:
  name: autopilot-config
spec:
  git:
    repo: https://github.com/your-org/gitops-bootstrap
    revision: HEAD
    token: "${GIT_TOKEN}"
  argocd:
    server: http://argo.annkinimbom.com
    username: admin
    password: "${ARGOCD_PASSWORD}"
    insecure: true
  bootstrap:
    namespaces:
    - argocd
    - port-system
    - dev
    - staging  
    - prod
```

### 2. Repository Structure Generator
```yaml
# .autopilot/repo-structure.yaml
kind: RepoStructure
metadata:
  name: port-io-structure
spec:
  directories:
  - path: "projects"
    description: "ArgoCD AppProject definitions"
  - path: "apps/microservices"
    description: "Microservice applications"
  - path: "apps/platform"
    description: "Platform applications (Port.io, monitoring, etc.)"
  - path: "bootstrap"
    description: "Bootstrap applications"
  - path: "cluster-resources"
    description: "Cluster-wide resources"
  
  templates:
  - name: "microservice"
    path: "apps/microservices/_template.yaml"
    description: "Template for microservice applications"
  - name: "platform-app"
    path: "apps/platform/_template.yaml" 
    description: "Template for platform applications"
```

## 🚀 Benefits of Autopilot Integration

### ✅ **Automated Repository Management**
- **Git Structure**: Automatically generates GitOps repository structure
- **Application Lifecycle**: Manages application creation, updates, and deletion
- **Branch Management**: Handles Git operations and PR workflows

### ✅ **Enhanced Port.io Integration**  
- **Template-Driven**: Uses templates for consistent application generation
- **Project Organization**: Organizes applications by projects and teams
- **Automated Sync**: Integrates with Port.io actions for app creation

### ✅ **Enterprise Governance**
- **Standardized Structure**: Enforces consistent GitOps patterns
- **RBAC Integration**: Works with existing ArgoCD RBAC
- **Audit Trail**: Complete Git history of all changes

## 🎯 Usage Workflow

1. **Bootstrap**: Use Autopilot to create initial GitOps repository
2. **Port.io Integration**: Controller uses Autopilot for app creation
3. **Developer Self-Service**: Port.io actions trigger Autopilot commands
4. **Automated Management**: Autopilot handles Git operations and ArgoCD sync

This Autopilot integration completes your GitOps platform by providing automated repository bootstrap and management capabilities alongside the Port.io developer experience! 🚀
