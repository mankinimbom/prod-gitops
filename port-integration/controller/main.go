package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/go-git/go-git/v5"
	"github.com/go-git/go-git/v5/plumbing/object"
	githttp "github.com/go-git/go-git/v5/plumbing/transport/http"
	"gopkg.in/yaml.v2"
)

// Port.io webhook payloads
type PortWebhookPayload struct {
	Action     string                 `json:"action"`
	Entity     PortEntity             `json:"entity,omitempty"`
	Context    PortContext            `json:"context"`
	Properties map[string]interface{} `json:"properties"`
}

type PortEntity struct {
	Identifier string                 `json:"identifier"`
	Blueprint  string                 `json:"blueprint"`
	Properties map[string]interface{} `json:"properties"`
}

type PortContext struct {
	Entity     string `json:"entity"`
	Blueprint  string `json:"blueprint"`
	RunID      string `json:"runId"`
	UserEmail  string `json:"userEmail"`
}

// Microservice template structure
type MicroserviceManifest struct {
	Name        string            `yaml:"name"`
	Team        string            `yaml:"team"`
	Language    string            `yaml:"language"`
	Framework   string            `yaml:"framework"`
	Port        int               `yaml:"port"`
	Replicas    int               `yaml:"replicas"`
	Resources   ResourceRequests  `yaml:"resources"`
	Environment map[string]string `yaml:"environment,omitempty"`
	Database    bool              `yaml:"database"`
	Redis       bool              `yaml:"redis"`
	Public      bool              `yaml:"public"`
}

type ResourceRequests struct {
	CPU    string `yaml:"cpu"`
	Memory string `yaml:"memory"`
}

// ArgoCD Application template
type ArgoApplication struct {
	APIVersion string                  `yaml:"apiVersion"`
	Kind       string                  `yaml:"kind"`
	Metadata   ArgoApplicationMetadata `yaml:"metadata"`
	Spec       ArgoApplicationSpec     `yaml:"spec"`
}

type ArgoApplicationMetadata struct {
	Name        string            `yaml:"name"`
	Namespace   string            `yaml:"namespace"`
	Labels      map[string]string `yaml:"labels"`
	Annotations map[string]string `yaml:"annotations"`
}

type ArgoApplicationSpec struct {
	Project     string                 `yaml:"project"`
	Source      ArgoApplicationSource  `yaml:"source"`
	Destination ArgoApplicationDest    `yaml:"destination"`
	SyncPolicy  ArgoApplicationSync    `yaml:"syncPolicy"`
}

type ArgoApplicationSource struct {
	RepoURL        string `yaml:"repoURL"`
	TargetRevision string `yaml:"targetRevision"`
	Path           string `yaml:"path"`
}

type ArgoApplicationDest struct {
	Server    string `yaml:"server"`
	Namespace string `yaml:"namespace"`
}

type ArgoApplicationSync struct {
	Automated ArgoApplicationAutomated `yaml:"automated"`
}

type ArgoApplicationAutomated struct {
	Prune    bool `yaml:"prune"`
	SelfHeal bool `yaml:"selfHeal"`
}

// Global configuration
var (
	gitRepoURL    = os.Getenv("GIT_REPO_URL")
	gitToken      = os.Getenv("GITHUB_TOKEN")
	argoCDServer  = os.Getenv("ARGOCD_SERVER")
	argoCDToken   = os.Getenv("ARGOCD_TOKEN")
	portClientID  = os.Getenv("PORT_CLIENT_ID")
	portSecret    = os.Getenv("PORT_CLIENT_SECRET")
	gitCacheDir   = "/git-cache"
)

func main() {
	// Initialize Gin router
	gin.SetMode(gin.ReleaseMode)
	r := gin.Default()

	// Health check endpoints
	r.GET("/health", healthCheck)
	r.GET("/ready", readinessCheck)

	// Port.io webhook endpoints
	r.POST("/webhooks/create-microservice", handleCreateMicroservice)
	r.POST("/webhooks/deploy", handleDeploy)
	r.POST("/webhooks/promote", handlePromote)
	r.POST("/webhooks/rollback", handleRollback)
	r.POST("/webhooks/scale", handleScale)
	r.POST("/webhooks/argocd", handleArgoCDWebhook)

	// Start server
	log.Println("Starting Port GitOps Controller on :8080")
	log.Fatal(r.Run(":8080"))
}

func healthCheck(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "healthy"})
}

func readinessCheck(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ready"})
}

func handleCreateMicroservice(c *gin.Context) {
	var payload PortWebhookPayload
	if err := c.ShouldBindJSON(&payload); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	log.Printf("Creating microservice: %+v", payload)

	// Extract properties from payload
	serviceName := payload.Properties["name"].(string)
	team := payload.Properties["team"].(string)
	language := payload.Properties["language"].(string)
	framework := payload.Properties["framework"].(string)
	template := "basic"
	if t, ok := payload.Properties["template"]; ok {
		template = t.(string)
	}

	// Create microservice manifest
	manifest := MicroserviceManifest{
		Name:      serviceName,
		Team:      team,
		Language:  language,
		Framework: framework,
		Port:      8080,
		Replicas:  2,
		Resources: ResourceRequests{
			CPU:    "200m",
			Memory: "256Mi",
		},
		Database: false,
		Redis:    false,
		Public:   false,
	}

	// Generate Git repository structure
	if err := createMicroserviceRepo(manifest, template); err != nil {
		log.Printf("Error creating microservice repo: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Create ArgoCD application
	if err := createArgoApplication(manifest, "dev"); err != nil {
		log.Printf("Error creating ArgoCD application: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Update Port.io entity
	if err := updatePortEntity(serviceName, "microservice", map[string]interface{}{
		"status":      "created",
		"repository":  fmt.Sprintf("%s/services/%s", gitRepoURL, serviceName),
		"argocd_app":  fmt.Sprintf("%s-dev", serviceName),
		"created_at":  time.Now().Format(time.RFC3339),
	}); err != nil {
		log.Printf("Error updating Port entity: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{
		"message":    "Microservice created successfully",
		"service":    serviceName,
		"repository": fmt.Sprintf("%s/services/%s", gitRepoURL, serviceName),
		"argocd_app": fmt.Sprintf("%s-dev", serviceName),
	})
}

func handleDeploy(c *gin.Context) {
	var payload PortWebhookPayload
	if err := c.ShouldBindJSON(&payload); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	log.Printf("Deploying service: %+v", payload)

	serviceName := payload.Properties["service"].(string)
	environment := payload.Properties["environment"].(string)
	version := payload.Properties["version"].(string)
	autoSync := true
	if as, ok := payload.Properties["auto_sync"]; ok {
		autoSync = as.(bool)
	}

	// Update Kustomization with new image version
	if err := updateImageVersion(serviceName, environment, version); err != nil {
		log.Printf("Error updating image version: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Create or update ArgoCD application for environment
	manifest := MicroserviceManifest{Name: serviceName}
	if err := createArgoApplication(manifest, environment); err != nil {
		log.Printf("Error creating/updating ArgoCD application: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Create deployment entity in Port.io
	deploymentID := fmt.Sprintf("%s-%s", serviceName, environment)
	if err := createPortEntity(deploymentID, "deployment", map[string]interface{}{
		"service":      serviceName,
		"environment":  environment,
		"version":      version,
		"status":       "Progressing",
		"sync_status":  "OutOfSync",
		"auto_sync":    autoSync,
		"deployed_at":  time.Now().Format(time.RFC3339),
	}); err != nil {
		log.Printf("Error creating Port deployment entity: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{
		"message":     "Deployment initiated",
		"service":     serviceName,
		"environment": environment,
		"version":     version,
		"argocd_app":  fmt.Sprintf("%s-%s", serviceName, environment),
	})
}

func handlePromote(c *gin.Context) {
	var payload PortWebhookPayload
	if err := c.ShouldBindJSON(&payload); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	log.Printf("Promoting deployment: %+v", payload)

	// Extract current deployment info
	sourceEnv := payload.Entity.Properties["environment"].(string)
	serviceName := payload.Entity.Properties["service"].(string)
	currentVersion := payload.Entity.Properties["version"].(string)
	targetEnv := payload.Properties["target_environment"].(string)
	runTests := true
	if rt, ok := payload.Properties["run_tests"]; ok {
		runTests = rt.(bool)
	}

	// Update target environment with current version
	if err := updateImageVersion(serviceName, targetEnv, currentVersion); err != nil {
		log.Printf("Error promoting to %s: %v", targetEnv, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Create deployment entity for target environment
	deploymentID := fmt.Sprintf("%s-%s", serviceName, targetEnv)
	if err := createPortEntity(deploymentID, "deployment", map[string]interface{}{
		"service":       serviceName,
		"environment":   targetEnv,
		"version":       currentVersion,
		"status":        "Progressing",
		"sync_status":   "OutOfSync",
		"promoted_from": sourceEnv,
		"tests_run":     runTests,
		"promoted_at":   time.Now().Format(time.RFC3339),
	}); err != nil {
		log.Printf("Error creating Port deployment entity: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{
		"message":      "Promotion initiated",
		"service":      serviceName,
		"from":         sourceEnv,
		"to":           targetEnv,
		"version":      currentVersion,
		"tests_run":    runTests,
	})
}

func handleRollback(c *gin.Context) {
	var payload PortWebhookPayload
	if err := c.ShouldBindJSON(&payload); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	log.Printf("Rolling back deployment: %+v", payload)

	serviceName := payload.Entity.Properties["service"].(string)
	environment := payload.Entity.Properties["environment"].(string)
	reason := payload.Properties["reason"].(string)
	
	var targetVersion string
	if tv, ok := payload.Properties["target_version"]; ok && tv != "" {
		targetVersion = tv.(string)
	} else {
		// Get previous version from Git history
		var err error
		targetVersion, err = getPreviousVersion(serviceName, environment)
		if err != nil {
			log.Printf("Error getting previous version: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	// Update to previous version
	if err := updateImageVersion(serviceName, environment, targetVersion); err != nil {
		log.Printf("Error rolling back: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Update deployment entity
	deploymentID := fmt.Sprintf("%s-%s", serviceName, environment)
	if err := updatePortEntity(deploymentID, "deployment", map[string]interface{}{
		"version":      targetVersion,
		"status":       "Progressing",
		"sync_status":  "OutOfSync",
		"rollback_reason": reason,
		"rolled_back_at": time.Now().Format(time.RFC3339),
	}); err != nil {
		log.Printf("Error updating Port deployment entity: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{
		"message":      "Rollback initiated",
		"service":      serviceName,
		"environment":  environment,
		"version":      targetVersion,
		"reason":       reason,
	})
}

func handleScale(c *gin.Context) {
	var payload PortWebhookPayload
	if err := c.ShouldBindJSON(&payload); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	log.Printf("Scaling resources: %+v", payload)

	serviceName := payload.Entity.Properties["service"].(string)
	environment := payload.Entity.Properties["environment"].(string)
	replicas := int(payload.Properties["replicas"].(float64))
	
	var cpuLimit, memoryLimit string
	if cl, ok := payload.Properties["cpu_limit"]; ok {
		cpuLimit = cl.(string)
	}
	if ml, ok := payload.Properties["memory_limit"]; ok {
		memoryLimit = ml.(string)
	}

	// Update deployment configuration
	if err := updateDeploymentResources(serviceName, environment, replicas, cpuLimit, memoryLimit); err != nil {
		log.Printf("Error scaling resources: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Update deployment entity
	deploymentID := fmt.Sprintf("%s-%s", serviceName, environment)
	updateData := map[string]interface{}{
		"replicas":    replicas,
		"scaled_at":   time.Now().Format(time.RFC3339),
	}
	if cpuLimit != "" {
		updateData["cpu_limit"] = cpuLimit
	}
	if memoryLimit != "" {
		updateData["memory_limit"] = memoryLimit
	}

	if err := updatePortEntity(deploymentID, "deployment", updateData); err != nil {
		log.Printf("Error updating Port deployment entity: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{
		"message":      "Scaling initiated",
		"service":      serviceName,
		"environment":  environment,
		"replicas":     replicas,
		"cpu_limit":    cpuLimit,
		"memory_limit": memoryLimit,
	})
}

func handleArgoCDWebhook(c *gin.Context) {
	var payload map[string]interface{}
	if err := c.ShouldBindJSON(&payload); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	log.Printf("ArgoCD webhook received: %+v", payload)

	// Process ArgoCD application status updates
	// This would sync status back to Port.io entities

	c.JSON(http.StatusOK, gin.H{"message": "ArgoCD webhook processed"})
}

// Helper functions (implementation details)
func createMicroserviceRepo(manifest MicroserviceManifest, template string) error {
	// Implementation would:
	// 1. Clone/update Git repository
	// 2. Create service directory structure
	// 3. Generate Kubernetes manifests from templates
	// 4. Commit and push changes
	log.Printf("Creating repo structure for %s with template %s", manifest.Name, template)
	return nil
}

func createArgoApplication(manifest MicroserviceManifest, environment string) error {
	// Implementation would:
	// 1. Generate ArgoCD Application YAML
	// 2. Apply via ArgoCD API or commit to Git
	log.Printf("Creating ArgoCD application for %s in %s", manifest.Name, environment)
	return nil
}

func updateImageVersion(serviceName, environment, version string) error {
	// Implementation would:
	// 1. Update kustomization.yaml with new image tag
	// 2. Commit and push changes
	log.Printf("Updating %s in %s to version %s", serviceName, environment, version)
	return nil
}

func updateDeploymentResources(serviceName, environment string, replicas int, cpuLimit, memoryLimit string) error {
	// Implementation would:
	// 1. Update deployment manifest with new resource limits
	// 2. Commit and push changes
	log.Printf("Scaling %s in %s: replicas=%d, cpu=%s, memory=%s", serviceName, environment, replicas, cpuLimit, memoryLimit)
	return nil
}

func getPreviousVersion(serviceName, environment string) (string, error) {
	// Implementation would:
	// 1. Query Git history for previous image versions
	// 2. Return the most recent previous version
	return "v1.0.0", nil
}

func createPortEntity(identifier, blueprint string, properties map[string]interface{}) error {
	// Implementation would call Port.io API to create entity
	log.Printf("Creating Port entity %s of type %s", identifier, blueprint)
	return nil
}

func updatePortEntity(identifier, blueprint string, properties map[string]interface{}) error {
	// Implementation would call Port.io API to update entity
	log.Printf("Updating Port entity %s of type %s", identifier, blueprint)
	return nil
}
