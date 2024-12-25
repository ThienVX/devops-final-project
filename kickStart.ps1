# Script for Helm, Kubernetes Secret Setup, and GCP IAM Policy Bindings
[CmdletBinding()]
param (
    [ValidateScript({ Test-Path $_ })]
    [string]$KeyPath = "D:\Learning\DataPlatform\data-source-3\final_devops_project\gke-nth-1-933de76d9c63",
    [string]$projectId = "gke-nth-1",

    [string]$IngressNginxValuesFilePath = "D:\Learning\DataPlatform\data-source-3\final_devops_project\src\helm\helm_final\ingress-nginx\values-ingress-nginx.yaml",
    [string]$IngressNginxReleaseName = "ingress-nginx",

    [ValidateScript({ Test-Path $_ })]
    [string]$HelmChartPath = "D:\Learning\DataPlatform\data-source-3\final_devops_project\src\helm\helm_final\data-platform-hth",
    [string]$HelmChartValueFilePath = "D:\Learning\DataPlatform\data-source-3\final_devops_project\src\helm\helm_final\data-platform-hth\values.yaml",

    [string]$ReleaseName = "data-platform-hth",
    [string]$GcpServiceAccount = "gke-nth-1@gke-nth-1.iam.gserviceaccount.com",

    [string]$AirflowChartPath = "D:\Learning\DataPlatform\data-source-3\final_devops_project\src\helm\helm_final\airflow\values-airflow.yaml",
    [string]$AirflowModifiedValuesPath = "D:\Learning\DataPlatform\data-source-3\final_devops_project\src\helm\helm_final\airflow\values-airflow-modified.yaml",
    [string]$AirflowReleaseName = "airflow",
    [string]$airflowNamespace = "data-process",

    [string]$DataStorageChartPath = "D:\Learning\DataPlatform\data-source-3\final_devops_project\src\helm\helm_final\data-storage\values-postgresql.yaml",
    [string]$DataStorageReleaseName = "data-storage"
)

# Enable Logging
$LogFile = "deployment.log"
Start-Transcript -Path $LogFile -Append

#Function to remove load balancer
function remove_loadbalancer() {
    # Step: Remove Load Balancer resources created by Ingress-NGINX
    Write-Host "Removing Load Balancer resources created by Ingress-NGINX..." -ForegroundColor Cyan

    try {
        # Fetch forwarding rules associated with the LoadBalancer
        $forwardingRules = gcloud compute forwarding-rules list --filter="description~'k8s' AND name~'$IngressNginxReleaseName'" --format="value(name,region)"

        if ($forwardingRules) {
            foreach ($rule in $forwardingRules) {
                $ruleParts = $rule -split '\s+'
                $ruleName = $ruleParts[0]
                $ruleRegion = $ruleParts[1]

                Write-Host "Deleting forwarding rule: $ruleName in region: $ruleRegion" -ForegroundColor Yellow
                gcloud compute forwarding-rules delete $ruleName --region $ruleRegion --quiet

                Write-Host "Deleted forwarding rule: $ruleName" -ForegroundColor Green
            }
        } else {
            Write-Host "No forwarding rules found for Ingress-NGINX." -ForegroundColor Cyan
        }
    } catch {
        Write-Host "Error deleting Load Balancer resources: $_" -ForegroundColor Red
        exit 1
    }
}

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

# Function to Check Domain Readiness
function Check-DomainReadiness {
    param (
        [string]$Url
    )
    try {
        Write-Host "`nChecking if the domain $Url is ready..." -ForegroundColor Cyan

        # Send an HTTP GET request
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10

        # Check if the response status code is 200 (OK)
        if ($response.StatusCode -eq 200) {
            Write-Host "Domain $Url is ready and responding with status code 200!" -ForegroundColor Green
            return $true
        } else {
            Write-Host "Domain $Url is responding but with status code $($response.StatusCode)." -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-Host "Error accessing the domain {$Url}: $_" -ForegroundColor Red
        return $false
    }
}

# Function to Register Airflow Connection
function Register-AirflowConnection {
    param (
        [string]$AirflowApiUrl,
        [string]$ConnectionId,
        [string]$ConnectionType,
        [string]$Description,
        [string]$Extra
    )
    try {
        Write-Host "`nRegistering Airflow connection with ID: $ConnectionId..." -ForegroundColor Cyan

        # Prepare the POST body
        $body = @{
            connection_id = $ConnectionId
            conn_type     = $ConnectionType
            description   = $Description
            extra         = $Extra
        } | ConvertTo-Json -Depth 10

        # Send the POST request
        $response = Invoke-RestMethod -Uri $AirflowApiUrl -Method POST -Body $body -ContentType "application/json"

        Write-Host "Airflow connection registered successfully! Response:" -ForegroundColor Green
        $response | ConvertTo-Json -Depth 10 | Write-Host
    } catch {
        Write-Host "Error registering Airflow connection: $_" -ForegroundColor Red
    }
}

# Main Script Execution
Write-Host "`nStarting data platform setup...`n" -ForegroundColor Cyan

# Step 1: Create Kubernetes Secret
Write-Host "Creating Kubernetes secret 'gac-keys'..." -ForegroundColor Cyan
kubectl create secret generic gac-keys --from-file=$KeyPath --dry-run=client -o yaml | kubectl apply -f -

# Step 2: Create Ingress NGINX
Write-Host "Create Ingress NGINX '$ReleaseName'..." -ForegroundColor Cyan
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

# Check if Ingress-NGINX is already installed
$existingIngress = helm list --namespace default | Where-Object { $_ -match $IngressNginxReleaseName }

if ($existingIngress) {
    # Ask the user if they want to uninstall the existing release
    $userInput = Read-Host "Ingress-NGINX release '$IngressNginxReleaseName' already exists. Do you want to uninstall it? (Y/N) [Default: N]"

    # Set default value to 'N' if no input is provided
    if ([string]::IsNullOrWhiteSpace($userInput)) {
        $userInput = 'N'
    }

    if ($userInput -eq 'Y' -or $userInput -eq 'y') {
        # Uninstall existing release
        Write-Host "Uninstalling existing Ingress-NGINX release..." -ForegroundColor Yellow
        helm uninstall $IngressNginxReleaseName --namespace default

        # Proceed with installation since the existing release was uninstalled
        Write-Host "Installing new Ingress-NGINX release..." -ForegroundColor Cyan
        $helmInstallResult = helm install $IngressNginxReleaseName ingress-nginx/ingress-nginx --version 4.12.0-beta.0 -f $IngressNginxValuesFilePath --namespace default

        if ($helmInstallResult -match "Error") {
            Write-Host "Helm install failed: $helmInstallResult" -ForegroundColor Red
            exit 1
        }
        Write-Host "Helm chart '$IngressNginxReleaseName' deployed successfully!" -ForegroundColor Green
    } else {
        Write-Host "Skipping uninstallation and installation of Ingress-NGINX." -ForegroundColor Yellow
        Write-Host "Ingress-NGINX release '$IngressNginxReleaseName' remains unchanged." -ForegroundColor Green
    }
} else {
    # If Ingress-NGINX is not installed, proceed with installation
    Write-Host "Ingress-NGINX is not installed. Installing new release..." -ForegroundColor Cyan
    $helmInstallResult = helm install $IngressNginxReleaseName ingress-nginx/ingress-nginx --version 4.12.0-beta.0 -f $IngressNginxValuesFilePath --namespace default

    if ($helmInstallResult -match "Error") {
        Write-Host "Helm install failed: $helmInstallResult" -ForegroundColor Red
        exit 1
    }
    Write-Host "Helm chart '$IngressNginxReleaseName' deployed successfully!" -ForegroundColor Green
}


# Step 3: Deploy Helm Release
Write-Host "Update and Build Helm chart's Dependency '$ReleaseName'..." -ForegroundColor Cyan
helm dependency update $HelmChartPath
helm dependency build $HelmChartPath
# Uninstall the existing Helm release
helm uninstall $ReleaseName

# Wait for the desired number of seconds before proceeding
Write-Host "Waiting for resources to clean up..." -ForegroundColor Yellow
Start-Sleep -Seconds 5  # Adjust the number of seconds as needed

# Deploy the new Helm chart
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
$LoadBalancerIP = Get-LoadBalancerIP -ServiceName "ingress-nginx-controller" -Namespace "default"
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

# Step 5: Deploy Postgresql Chart
Write-Host "Deploying Postgresql chart with values..." -ForegroundColor Cyan
kubectl create namespace data-storage
helm uninstall $DataStorageReleaseName -n data-storage
$postgresqlInstallResult = helm install $DataStorageReleaseName apache-airflow/airflow --version 1.15.0 -f $DataStorageChartPath -n data-storage  2>&1
if ($postgresqlInstallResult -match "Error") {
    Write-Host "Postgresql Helm install failed: $airflowInstallResult" -ForegroundColor Red
    exit 1
}
Write-Host "Postgresql chart deployed successfully!" -ForegroundColor Green


# Step 6: Add IAM Policy Bindings
Write-Host "Adding IAM policy bindings for GCP service account..." -ForegroundColor Cyan
try {
    kubectl annotate serviceaccount airflow-worker --namespace $airflowNamespace iam.gke.io/gcp-service-account=$GcpServiceAccount
    gcloud iam service-accounts add-iam-policy-binding $GcpServiceAccount --member="serviceAccount:$projectId.svc.id.goog[$airflowNamespace/airflow-worker]" --role="roles/owner"
    gcloud iam service-accounts add-iam-policy-binding $GcpServiceAccount --member="serviceAccount:$projectId.svc.id.goog[$airflowNamespace/airflow-worker]" --role="roles/iam.workloadIdentityUser"
    Write-Host "IAM policy bindings added successfully!" -ForegroundColor Green
} catch {
    Write-Host "Error adding IAM policy bindings: $_" -ForegroundColor Red
    exit 1
}

# Step 7
$AirflowDomain = "http://airflow.$LoadBalancerIP.nip.io"
Write-Host "Constructed Airflow Domain: $AirflowDomain" -ForegroundColor Green

# Define username and password
$username = "admin"
$password = "admin"

# Combine username and password into a plain string
#$plainCredentials = "$username:$password"

#Write-Host "Basic Credentials: $plainCredentials"

# Ensure the credentials are properly encoded in Base64 for Basic Authentication
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${username}:${password}"))

# Output the Base64 encoded string (for debugging)
Write-Host "Encoded Credentials: $base64AuthInfo"


# Set the Authorization header
$Headers = @{
"Authorization" = "Basic $base64AuthInfo"
}

# Maximum number of retries
$maxRetries = 10
# Wait time between retries (in seconds)
$waitTime = 59
# Retry counter
$retryCount = 0
# Flag to track if the domain is ready
$isDomainReady = $false

## Retry logic for domain readiness
#while ($retryCount -lt $maxRetries -and -not $isDomainReady) {
#    $retryCount++
#    Write-Host "Attempt {$retryCount}: Checking Airflow domain readiness..." -ForegroundColor Yellow
#
#    if (Check-DomainReadiness -Url $AirflowDomain) {
#        $isDomainReady = $true
#        Write-Host "Airflow domain is ready." -ForegroundColor Green
#        break
#    } else {
#        Write-Host "Airflow domain is not ready. Retrying in $waitTime seconds..." -ForegroundColor Red
#        Start-Sleep -Seconds $waitTime
#    }
#}
#
## If the domain is ready, register the connection
#if ($isDomainReady) {
#    $AirflowApiUrl = "$AirflowDomain/api/v1/connections"
#    Register-AirflowConnection -AirflowApiUrl $AirflowApiUrl `
#      -ConnectionId "google_cloud_default" `
#      -ConnectionType "google_cloud_platform" `
#      -Description "Google Cloud Default Connection with Anonymous Authentication" `
#      -Extra '{"project_id": "gke-nth-1"}' `
#      -Headers $Headers
#
#} else {
#    Write-Host "Airflow domain is not ready after $maxRetries attempts. Skipping connection registration." -ForegroundColor Red
#}

Write-Host "`nSetup complete! Check '$LogFile' for detailed logs.`n" -ForegroundColor Green

# End Logging
Stop-Transcript
