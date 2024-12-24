# Script for Helm, Kubernetes Secret Setup, and GCP IAM Policy Bindings
[CmdletBinding()]
param (
    [ValidateScript({ Test-Path $_ })]
    [string]$KeyPath = "D:\Learning\DataPlatform\data-source-3\final_devops_project\gke-nth-8e96578cc812.json",

    [ValidateScript({ Test-Path $_ })]
    [string]$HelmChartPath = "D:\Learning\DataPlatform\data-source-3\final_devops_project\src\helm\helm_final\data-platform-hth",
    [string]$HelmChartValueFilePath = "D:\Learning\DataPlatform\data-source-3\final_devops_project\src\helm\helm_final\data-platform-hth\values.yaml",

    [string]$ReleaseName = "data-platform-hth",
    [string]$GcpServiceAccount = "gke-admin@gke-nth.iam.gserviceaccount.com",

    [string]$AirflowChartPath = "D:\Learning\DataPlatform\data-source-3\final_devops_project\src\helm\helm_final\airflow\values-airflow.yaml",
    [string]$AirflowModifiedValuesPath = "D:\Learning\DataPlatform\data-source-3\final_devops_project\src\helm\helm_final\airflow\values-airflow-modified.yaml",
    [string]$AirflowReleaseName = "airflow"
)

# Enable Logging
$LogFile = "deployment.log"
Start-Transcript -Path $LogFile -Append

# Function to Fetch Load Balancer IP
function Get-LoadBalancerIP {
    param (
        [string]$ServiceName,
        [string]$Namespace = "default",
        [int]$MaxRetries = 5,
        [int]$RetryDelay = 10
    )
    $retries = 0
    while ($retries -lt $MaxRetries) {
        try {
            $service = kubectl get svc $ServiceName -n $Namespace -o json | ConvertFrom-Json
            $loadBalancerIP = $service.status.loadBalancer.ingress[0].ip
            if ($loadBalancerIP) {
                return $loadBalancerIP
            }
        } catch {
            Write-Host "Error fetching LoadBalancer IP: $_" -ForegroundColor Red
        }
        $retries++
        Write-Host "Retrying to fetch LoadBalancer IP ($retries/$MaxRetries)..."
        Start-Sleep -Seconds $RetryDelay
    }
    Write-Host "Failed to fetch LoadBalancer IP after $MaxRetries retries." -ForegroundColor Red
    exit 1
}

# Function to Replace LoadBalancerIP in airflow-values.yaml
# Function to Replace LoadBalancerIP in airflow-values.yaml
# Function to Replace LoadBalancerIP in airflow-values.yaml and display changes
# Function to Replace LoadBalancerIP in airflow-values.yaml and display changes
function Update-AirflowValues {
    param (
        [string]$FilePath,
        [string]$LoadBalancerIP
    )
    try {
        # Read the content of the file
        $content = Get-Content $FilePath -Raw

        # Display the original content of the file
        Write-Host "`nOriginal content of ${FilePath}:" -ForegroundColor Yellow
        $content -split "`n" | ForEach-Object { Write-Host $_ }

        # Replace the placeholder with LoadBalancerIP
        $updatedContent = $content -replace "IngressLoadBalancerIP", $LoadBalancerIP

        # Create a new file path for the modified content (append "-modified" to the original file name)
        $newFilePath = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($FilePath),
                [System.IO.Path]::GetFileNameWithoutExtension($FilePath) + "-modified" + [System.IO.Path]::GetExtension($FilePath))

        Write-Host "Using modified Airflow values file: $newFilePath" -ForegroundColor Cyan
        # Write the updated content to the new file
        Set-Content -Path $newFilePath -Value $updatedContent
        Write-Host "`nCreated new modified file at: $newFilePath with LoadBalancer IP: $LoadBalancerIP" -ForegroundColor Green
        return $newFilePath
    } catch {
        Write-Host "Error updating ${FilePath}: $_" -ForegroundColor Red
        exit 1
    }

    return "";
}

# Main Script Execution
Write-Host "`nStarting data platform setup...`n" -ForegroundColor Cyan

# Step 1: Create Kubernetes Secret
Write-Host "Creating Kubernetes secret 'gac-keys'..." -ForegroundColor Cyan
kubectl create secret generic gac-keys --from-file=$KeyPath --dry-run=client -o yaml | kubectl apply -f -

# Step 2: Deploy Helm Release
Write-Host "Update and Build Helm chart's Dependency '$ReleaseName'..." -ForegroundColor Cyan
helm dependency update $HelmChartPath
helm dependency build $HelmChartPath
helm uninstall $ReleaseName

Write-Host "Deploying Helm chart '$ReleaseName'..." -ForegroundColor Cyan
# Capture both stdout and stderr from helm install and write to the log file
$helmInstallResult = helm install $ReleaseName $HelmChartPath -f $HelmChartValueFilePath
# Write Helm install result (including errors) to the log file

if ($helmInstallResult -match "Error") {
    Write-Host "Helm install failed: $helmInstallResult" -ForegroundColor Red
    exit 1
}
Write-Host "Helm chart '$ReleaseName' deployed successfully!" -ForegroundColor Green

# Fetch Ingress NGINX LoadBalancer IP
Write-Host "Fetching LoadBalancer IP for ingress-nginx..." -ForegroundColor Cyan
$LoadBalancerIP = Get-LoadBalancerIP -ServiceName "data-platform-hth-ingress-nginx-controller" -Namespace "default"
Write-Host "LoadBalancer IP fetched: $LoadBalancerIP" -ForegroundColor Green

# Update airflow-values.yaml with LoadBalancer IP
$AirflowModifiedValuesPath = Update-AirflowValues -FilePath $AirflowChartPath -LoadBalancerIP $LoadBalancerIP

# Step 4: Deploy Airflow Chart
Write-Host "Deploying Airflow chart with updated values..." -ForegroundColor Cyan
helm uninstall $AirflowReleaseName -n data-process 2>&1 | Out-Null

# Capture any error output from helm install for Airflow
Write-Host "Using modified Airflow values file: $AirflowModifiedValuesPath" -ForegroundColor Cyan
kubectl create namespace data-process
$airflowInstallResult = helm install $AirflowReleaseName apache-airflow/airflow --version 1.15.0 -f $AirflowModifiedValuesPath -n data-process  2>&1
if ($airflowInstallResult -match "Error") {
    Write-Host "Airflow Helm install failed: $airflowInstallResult" -ForegroundColor Red
    exit 1
}
Write-Host "Airflow chart deployed successfully!" -ForegroundColor Green

# Step 5: Add IAM Policy Bindings
Write-Host "Adding IAM policy bindings for GCP service account..." -ForegroundColor Cyan
try {
    gcloud iam service-accounts add-iam-policy-binding $GcpServiceAccount --member="serviceAccount:gke-nth.svc.id.goog[default/data-platform-hth-airflow-worker]" --role="roles/owner"
    gcloud iam service-accounts add-iam-policy-binding $GcpServiceAccount --member="serviceAccount:gke-nth.svc.id.goog[default/data-platform-hth-airflow-worker]" --role="roles/iam.workloadIdentityUser"
    Write-Host "IAM policy bindings added successfully!" -ForegroundColor Green
} catch {
    Write-Host "Error adding IAM policy bindings: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`nSetup complete! Check '$LogFile' for detailed logs.`n" -ForegroundColor Green

# End Logging
Stop-Transcript
