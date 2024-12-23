# Function to set up Helm and Kubernetes secret
function Setup {
    param (
        [string]$KeyPath = "D:\Learning\DataPlatform\data-source-2\final_devops_project\gke-nth-8e96578cc812.json",  # Default value for KeyPath
        [string]$HelmChartPath = ".",  # Default value for HelmChartPath
        [string]$ReleaseName = "data-platform-hth"  # Default value for ReleaseName
    )

    # Check if the key file exists
    if (-Not (Test-Path -Path $KeyPath)) {
        Write-Host "Error: File at '$KeyPath' not found. Please check the path and try again." -ForegroundColor Red
        exit 1
    }

    # Check if the Helm chart path exists
    if (-Not (Test-Path -Path $HelmChartPath)) {
        Write-Host "Error: File at '$HelmChartPath' not found. Please check the path and try again." -ForegroundColor Red
        exit 1
    }

    Write-Host "`nStart data-platform hth setup`n" -ForegroundColor Cyan

    Write-Host "Updating Helm dependencies...`n" -ForegroundColor Cyan
    helm dependency update $HelmChartPath

    Write-Host "Building Helm dependencies...`n" -ForegroundColor Cyan
    helm dependency build $HelmChartPath

    Write-Host "Creating Kubernetes secret 'gac-keys'...`n" -ForegroundColor Cyan
    kubectl create secret generic gac-keys --from-file=$KeyPath --dry-run=client -o yaml | kubectl apply -f -

    Write-Host "Secret 'gac-keys' created successfully!`n" -ForegroundColor Green

    Write-Host "Starting Helm installation for '$ReleaseName'...`n" -ForegroundColor Cyan

    Write-Host "Checking if Helm release '$ReleaseName' exists before uninstalling...`n" -ForegroundColor Cyan

    # Check if the Helm release exists
    $releaseCheck = helm list --all --filter "^$ReleaseName$" --output json | ConvertFrom-Json
    if ($releaseCheck.Count -gt 0) {
        Write-Host "Helm release '$ReleaseName' exists. Uninstalling...`n" -ForegroundColor Cyan
        helm uninstall $ReleaseName 2>&1 | Write-Host
    } else {
        Write-Host "Helm release '$ReleaseName' does not exist. Skipping uninstall...`n" -ForegroundColor Yellow
    }


    # Helm install command and error handling
    $helmInstallResult = helm install $ReleaseName $HelmChartPath 2>&1

    # Check if Helm installation failed
    if ($helmInstallResult -match "Error: INSTALLATION FAILED") {
        Write-Host "Error: Helm installation for '$ReleaseName' failed. Details: $helmInstallResult" -ForegroundColor Red
        exit 1
    }

    Write-Host "Helm installation for '$ReleaseName' was successful!`n" -ForegroundColor Green

    Write-Host "Checking Helm release status for '$ReleaseName'...`n" -ForegroundColor Cyan
    # Checking Helm release status in a loop until it is successfully deployed
    while ($true) {
        $status = helm status $ReleaseName 2>&1

        if ($status -match "STATUS: deployed") {
            Write-Host "Helm release '$ReleaseName' is successfully deployed!`n" -ForegroundColor Green
            break
        } elseif ($status -match "STATUS: failed") {
            Write-Host "Helm release '$ReleaseName' has failed. Please check the logs for details.`n" -ForegroundColor Red
            exit 1
        } else {
            Write-Host "Waiting for Helm release '$ReleaseName' to be deployed...`n" -ForegroundColor Yellow
            Start-Sleep -Seconds 10
        }
    }
}

# Function to create Kubernetes namespaces and IAM policy bindings
function Create_Connections {
    param (
        [string]$GcpServiceAccount = "gke-admin@gke-nth.iam.gserviceaccount.com"  # Default value for GCP service account
    )

    Write-Host "Creating Kubernetes namespaces...`n" -ForegroundColor Cyan
    kubectl create namespace data-process
    kubectl create namespace data-storage

    Write-Host "Adding IAM policy binding for GCP service account...`n" -ForegroundColor Cyan
    gcloud iam service-accounts add-iam-policy-binding $GcpServiceAccount `
        --member="serviceAccount:gke-nth.svc.id.goog[default/data-platform-hth-airflow-worker]" `
        --role="roles/owner"

    gcloud iam service-accounts add-iam-policy-binding gke-admin@gke-nth.iam.gserviceaccount.com `
    --member="serviceAccount:gke-nth.svc.id.goog[default/data-platform-hth-airflow-worker]" `
    --role="roles/iam.workloadIdentityUser"


    Write-Host "Connections created successfully!`n" -ForegroundColor Green
}

# Function to prompt for user input with default values
function Prompt-ForInput {
    param (
        [string]$PromptText,
        [string]$DefaultValue
    )
    Write-Host "$PromptText (leave blank for default):"
    $input = Read-Host
    if (-not $input) { return $DefaultValue }
    return $input
}

# Main script execution
$KeyPath = Prompt-ForInput "Enter the path to the key file" "D:\Learning\DataPlatform\data-source\final_devops_project\gke-nth-8e96578cc812.json"
$HelmChartPath = Prompt-ForInput "Enter the path to the Helm chart" "."
$ReleaseName = Prompt-ForInput "Enter the Helm release name" "data-platform-hth"
$GcpServiceAccount = Prompt-ForInput "Enter the GCP service account email" "gke-admin@gke-nth.iam.gserviceaccount.com"

# Call the setup function with the provided or default paths
Setup -KeyPath $KeyPath -HelmChartPath $HelmChartPath -ReleaseName $ReleaseName

# Call the create_connections function with the GCP service account
Create_Connections -GcpServiceAccount $GcpServiceAccount
