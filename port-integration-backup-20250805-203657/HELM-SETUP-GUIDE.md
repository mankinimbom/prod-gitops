# Port.io Helm Charts Integration Guide

## 🎯 **Recommended Setup Approach**

Based on your ArgoCD configuration and the Port.io integration requirements, here's the **recommended approach** for setting up the Helm charts:

### 📋 **Prerequisites**

1. **Kubernetes cluster** with ArgoCD already installed
2. **Helm 3.x** installed on your machine
3. **kubectl** configured to access your cluster
4. **Port.io account** with API credentials
5. **ArgoCD API token** for Ocean integration

---

## 🚀 **Quick Start (Recommended)**

### **Option 1: Enhanced Deployment Script**

Use the enhanced script with custom values files for better configuration management:

```bash
cd prod-gitops/port-integration

# Review and update credentials in values files
vi values-k8s-exporter.yaml
vi values-argocd-ocean.yaml

# Deploy with enhanced configuration
./deploy-port-helm-enhanced.sh
```

### **Option 2: Basic Deployment Script**

Use the basic script with inline parameters:

```bash
cd prod-gitops/port-integration
./setup-port-helm-charts.sh
```

### **Option 3: Manual Helm Commands**

Your original commands, but with namespace organization:

```bash
# Add Port.io repository
helm repo add --force-update port-labs https://port-labs.github.io/helm-charts
helm repo update

# Install Kubernetes Exporter
helm upgrade --install port-k8s-exporter port-labs/port-k8s-exporter \
    --create-namespace --namespace port-k8s-exporter \
    --set secret.secrets.portClientId="57qkRMZxmGcfVKfipr2to8pBMII77FYK" \
    --set secret.secrets.portClientSecret="n0eBOFw6SVO5nDYUAcM56Dk6jJKpeb11ePgzGC8O5FS0J4YrkplXrM1VPR7Fk6wN" \
    --set portBaseUrl="https://api.port.io" \
    --set stateKey="production-cluster" \
    --set eventListener.type="POLLING" \
    --set "extraEnv[0].name"="CLUSTER_NAME" \
    --set "extraEnv[0].value"="production-cluster"

# Install ArgoCD Ocean Integration  
helm upgrade --install argocd-ocean port-labs/port-ocean \
    --create-namespace --namespace port-ocean-argocd \
    --set port.clientId="57qkRMZxmGcfVKfipr2to8pBMII77FYK" \
    --set port.clientSecret="n0eBOFw6SVO5nDYUAcM56Dk6jJKpeb11ePgzGC8O5FS0J4YrkplXrM1VPR7Fk6wN" \
    --set port.baseUrl="https://api.port.io" \
    --set initializePortResources=true \
    --set sendRawDataExamples=true \
    --set scheduledResyncInterval=360 \
    --set integration.identifier="argocd" \
    --set integration.type="argocd" \
    --set integration.eventListener.type="POLLING" \
    --set integration.secrets.token="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJhcmdvY2QiLCJzdWIiOiJtaWNoYWVsLXRva2VuOmFwaUtleSIsIm5iZiI6MTc1NDI1NTE3NiwiaWF0IjoxNzU0MjU1MTc2LCJqdGkiOiIxOGM5MWI0OS1iYjVjLTQwMzYtYjNkMy1kYmQxNDA3YmIzYzMifQ.FI92Y6OYuO_QoIvVTlUNqVerE0aT89ekRyCxT3Xgff0" \
    --set integration.config.serverUrl="http://argo.annkinimbom.com/" \
    --set integration.config.insecure=true
```

---

## 🔧 **Configuration Improvements**

### **1. Enhanced ArgoCD Server Configuration**

Your `argocd-server-ha.yaml` has been updated to support **multiple Port.io webhook endpoints**:

- **Custom GitOps Controller**: `http://port-gitops-controller.port-system.svc.cluster.local:8080/webhooks/argocd`
- **Port.io Ocean Integration**: `http://argocd-ocean.port-ocean-argocd.svc.cluster.local:8000/webhooks/argocd`

### **2. Namespace Organization**

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| **Port.io K8s Exporter** | `port-k8s-exporter` | Kubernetes resource discovery and sync |
| **Port.io ArgoCD Ocean** | `port-ocean-argocd` | ArgoCD applications and projects sync |
| **Custom GitOps Controller** | `port-system` | Self-service actions and webhooks |

### **3. Values Files for Better Management**

- **`values-k8s-exporter.yaml`**: Custom configuration for Kubernetes Exporter
- **`values-argocd-ocean.yaml`**: Custom configuration for ArgoCD Ocean Integration

---

## 🎯 **Integration Architecture**

```
Port.io Catalog
       ↑
   ┌───┴───┐
   │ Ocean │ ← ArgoCD Applications, Projects, Repositories
   └───┬───┘
       │
   ┌───┴───┐
   │ K8s   │ ← Kubernetes Resources (Pods, Services, Deployments)
   │Export │
   └───┬───┘
       │
   ┌───┴───┐
   │Custom │ ← Self-Service Actions, Webhooks
   │GitOps │
   └───────┘
```

---

## 📊 **Data Flow**

### **1. Kubernetes Exporter → Port.io**
- **Discovers**: Pods, Services, Deployments, Namespaces
- **Updates**: Every polling interval (default: 30s)
- **Blueprints**: `microservice`, `deployment`, `service`, `namespace`

### **2. ArgoCD Ocean → Port.io**
- **Discovers**: Applications, Projects, Repositories  
- **Updates**: Every 360 seconds
- **Blueprints**: `argocd-application`, `argocd-project`, `repository`

### **3. Custom GitOps Controller → ArgoCD**
- **Receives**: Port.io webhook actions
- **Creates**: ArgoCD Applications via ApplicationSets
- **Manages**: Git operations and deployments

---

## 🔍 **Verification Steps**

After deployment, verify the integration:

```bash
# 1. Check Pod Status
kubectl get pods -n port-k8s-exporter
kubectl get pods -n port-ocean-argocd

# 2. Check Service Endpoints
kubectl get svc -n port-k8s-exporter
kubectl get svc -n port-ocean-argocd

# 3. Verify Webhook Configuration
kubectl get configmap argocd-server-config -n argocd -o yaml | grep webhook

# 4. Monitor Logs
kubectl logs -f deployment/port-k8s-exporter -n port-k8s-exporter
kubectl logs -f deployment/argocd-ocean -n port-ocean-argocd

# 5. Check Port.io Catalog
# Visit your Port.io catalog to see imported resources
```

---

## 🛠️ **Troubleshooting**

### **Common Issues**

1. **Authentication Errors**
   ```bash
   # Check credentials in secrets
   kubectl get secret port-credentials -n port-k8s-exporter -o yaml
   ```

2. **ArgoCD Token Issues**
   ```bash
   # Verify token validity
   curl -H "Authorization: Bearer $ARGOCD_TOKEN" http://argo.annkinimbom.com/api/v1/version
   ```

3. **Webhook Connectivity**
   ```bash
   # Test webhook endpoints
   kubectl exec -it deployment/argocd-server -n argocd -- curl -v http://argocd-ocean.port-ocean-argocd.svc.cluster.local:8000/health
   ```

### **Log Analysis**

```bash
# Detailed logs with timestamps
kubectl logs deployment/port-k8s-exporter -n port-k8s-exporter --timestamps
kubectl logs deployment/argocd-ocean -n port-ocean-argocd --timestamps
```

---

## 📝 **Next Steps**

1. **Deploy the integration** using one of the recommended methods
2. **Verify data flow** to Port.io catalog
3. **Customize blueprints** and mappings as needed
4. **Set up monitoring** and alerting
5. **Configure additional integrations** (CI/CD, monitoring tools)

---

## 🎉 **Benefits of This Setup**

- ✅ **Complete visibility** into Kubernetes and ArgoCD resources
- ✅ **Real-time synchronization** with Port.io catalog
- ✅ **Self-service capabilities** through custom GitOps controller
- ✅ **Proper namespace isolation** for better management
- ✅ **Enhanced webhook integration** with ArgoCD
- ✅ **Monitoring and observability** built-in
- ✅ **Easy customization** through values files

**This setup provides a comprehensive Internal Developer Platform with Port.io + ArgoCD integration!** 🚀
