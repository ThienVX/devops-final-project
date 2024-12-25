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
    [string]$PostgresqlReleaseName = "data-storage",
    [string]$PostgresqlNamespace = "data-storage",

    [string]$jupyterFileValuesPath = "D:\Learning\DataPlatform\data-source-3\final_devops_project\src\helm\helm_final\data-query\values-jupyterhub.yaml",
    [string]$jupyterModifiedValuesPath = "D:\Learning\DataPlatform\data-source-3\final_devops_project\src\helm\helm_final\data-query\values-jupyterhub-modified.yaml",
    [string]$JupyterReleaseName = "jupyter",
    [string]$JupyterNamespace = "data-query"
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
function replace_loadbalancer_ip {
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
$AirflowModifiedValuesPath = replace_loadbalancer_ip -FilePath $AirflowChartPath -LoadBalancerIP $LoadBalancerIP
$jupyterModifiedValuesPath = replace_loadbalancer_ip -FilePath $jupyterFileValuesPath -LoadBalancerIP $LoadBalancerIP

# Step 4: Deploy Airflow Chart
# Check if Airflow release already exists
kubectl create namespace $AirflowNamespace
$existingAirflow = helm list --namespace $AirflowNamespace | Select-String -Pattern $AirflowReleaseName

if ($existingAirflow) {
    # Ask the user if they want to uninstall the existing release
    $userInput = Read-Host "Airflow release '$AirflowReleaseName' already exists. Do you want to uninstall it? (Y/N) [Default: N]"

    if ([string]::IsNullOrWhiteSpace($userInput)) {
        $userInput = 'N'
    }

    if ($userInput -eq 'Y' -or $userInput -eq 'y') {
        # Uninstall existing Airflow release
        Write-Host "Uninstalling existing Airflow release..." -ForegroundColor Yellow
        helm uninstall $AirflowReleaseName --namespace $AirflowNamespace

        # Proceed with installation after uninstall
        Write-Host "Installing new Airflow release..." -ForegroundColor Cyan
        $helmInstallResult = helm install $AirflowReleaseName $AirflowChartPath -f $AirflowValuesFilePath --namespace $AirflowNamespace

        if ($helmInstallResult -match "Error") {
            Write-Host "Helm install failed: $helmInstallResult" -ForegroundColor Red
            exit 1
        }
        Write-Host "Airflow release '$AirflowReleaseName' deployed successfully!" -ForegroundColor Green
    } else {
        Write-Host "Skipping uninstallation and installation of Airflow." -ForegroundColor Yellow
        Write-Host "Airflow release '$AirflowReleaseName' remains unchanged." -ForegroundColor Green
    }
} else {
    # Install Airflow if not already installed
    Write-Host "Airflow is not installed. Installing new release..." -ForegroundColor Cyan
    $helmInstallResult = helm install $AirflowReleaseName $AirflowChartPath -f $AirflowValuesFilePath --namespace $AirflowNamespace

    if ($helmInstallResult -match "Error") {
        Write-Host "Helm install failed: $helmInstallResult" -ForegroundColor Red
        exit 1
    }
    Write-Host "Airflow release '$AirflowReleaseName' deployed successfully!" -ForegroundColor Green
}


# Step 5: Deploy Jupyter Chart
# Check if Jupyter release already exists
kubectl create namespace $JupyterNamespace
$existingJupyter = helm list --namespace $JupyterNamespace | Select-String -Pattern $JupyterReleaseName

if ($existingJupyter) {
    # Ask the user if they want to uninstall the existing release
    $userInput = Read-Host "Jupyter release '$JupyterReleaseName' already exists. Do you want to uninstall it? (Y/N) [Default: N]"

    if ([string]::IsNullOrWhiteSpace($userInput)) {
        $userInput = 'N'
    }

    if ($userInput -eq 'Y' -or $userInput -eq 'y') {
        # Uninstall existing Jupyter release
        Write-Host "Uninstalling existing Jupyter release..." -ForegroundColor Yellow
        helm uninstall $JupyterReleaseName --namespace $JupyterNamespace

        # Proceed with installation after uninstall
        Write-Host "Installing new Jupyter release..." -ForegroundColor Cyan
        $helmInstallResult = helm install $JupyterReleaseName jupyterhub/jupyterhub --namespace $JupyterNamespace --version 4.0.1-0.dev.git.6889.h262097b2 -f $jupyterModifiedValuesPath

        if ($helmInstallResult -match "Error") {
            Write-Host "Helm install failed: $helmInstallResult" -ForegroundColor Red
            exit 1
        }
        Write-Host "Jupyter release '$JupyterReleaseName' deployed successfully!" -ForegroundColor Green
    } else {
        Write-Host "Skipping uninstallation and installation of Jupyter." -ForegroundColor Yellow
        Write-Host "Jupyter release '$JupyterReleaseName' remains unchanged." -ForegroundColor Green
    }
} else {
    # Install Jupyter if not already installed
    Write-Host "Jupyter is not installed. Installing new release..." -ForegroundColor Cyan
    $helmInstallResult = helm install $JupyterReleaseName jupyterhub/jupyterhub --namespace $JupyterNamespace --version 4.0.1-0.dev.git.6889.h262097b2 -f $jupyterModifiedValuesPath

    if ($helmInstallResult -match "Error") {
        Write-Host "Helm install failed: $helmInstallResult" -ForegroundColor Red
        exit 1
    }
    Write-Host "Jupyter release '$JupyterReleaseName' deployed successfully!" -ForegroundColor Green
}


# Step 6: Deploy Postgresql Chart
# Check if PostgreSQL release already exists
kubectl create namespace $PostgresqlNamespace
$existingPostgresql = helm list --namespace $PostgresqlNamespace | Select-String -Pattern $PostgresqlReleaseName

if ($existingPostgresql) {
    # Ask the user if they want to uninstall the existing release
    $userInput = Read-Host "PostgreSQL release '$PostgresqlReleaseName' already exists. Do you want to uninstall it? (Y/N) [Default: N]"

    if ([string]::IsNullOrWhiteSpace($userInput)) {
        $userInput = 'N'
    }

    if ($userInput -eq 'Y' -or $userInput -eq 'y') {
        # Uninstall existing PostgreSQL release
        Write-Host "Uninstalling existing PostgreSQL release..." -ForegroundColor Yellow
        helm uninstall $PostgresqlReleaseName --namespace $PostgresqlNamespace

        # Proceed with installation after uninstall
        Write-Host "Installing new PostgreSQL release..." -ForegroundColor Cyan
        $helmInstallResult = helm install $PostgresqlReleaseName $PostgresqlChartPath -f $PostgresqlValuesFilePath --namespace $PostgresqlNamespace

        if ($helmInstallResult -match "Error") {
            Write-Host "Helm install failed: $helmInstallResult" -ForegroundColor Red
            exit 1
        }
        Write-Host "PostgreSQL release '$PostgresqlReleaseName' deployed successfully!" -ForegroundColor Green
    } else {
        Write-Host "Skipping uninstallation and installation of PostgreSQL." -ForegroundColor Yellow
        Write-Host "PostgreSQL release '$PostgresqlReleaseName' remains unchanged." -ForegroundColor Green
    }
} else {
    # Install PostgreSQL if not already installed
    Write-Host "PostgreSQL is not installed. Installing new release..." -ForegroundColor Cyan
    $helmInstallResult = helm install $PostgresqlReleaseName $PostgresqlChartPath -f $PostgresqlValuesFilePath --namespace $PostgresqlNamespace

    if ($helmInstallResult -match "Error") {
        Write-Host "Helm install failed: $helmInstallResult" -ForegroundColor Red
        exit 1
    }
    Write-Host "PostgreSQL release '$PostgresqlReleaseName' deployed successfully!" -ForegroundColor Green
}


# Step 7: Add IAM Policy Bindings
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

# Step 8
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
