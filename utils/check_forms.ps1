# Get command line parameters
param(
    [switch]$test
)

# Define paths relative to script location
$scriptPath = $PSScriptRoot
$rootPath = Split-Path $scriptPath -Parent
$inputPath = Join-Path $rootPath "input\leadbox_urls.txt"
$outputPath = Join-Path $rootPath "output\form_check_results.csv"

# Read URLs from the file
if (Test-Path $inputPath) {
    $urls = Get-Content -Path $inputPath
} else {
    Write-Error "Input file not found at: $inputPath"
    exit 1
}

# If in test mode, only take first 5 URLs
if ($test) {
    $urls = $urls | Select-Object -First 5
    Write-Host "Running in test mode - checking only first 5 URLs"
}

# Create arrays to store results
$results = @()

# Function to get root domain from URL
function Get-RootDomain {
    param([string]$url)
    try {
        # Remove any 'https://' or 'http://' prefix
        $url = $url -replace '^https?://', ''
        
        # Split by first '/' and take only the domain part
        $domain = $url.Split('/')[0]
        
        return $domain
    } catch {
        Write-Warning "Error extracting domain from $url : $_"
        return $null
    }
}

# Initialize cache from existing results if file exists
$domainFormIds = @{}
if (Test-Path $outputPath) {
    Import-Csv $outputPath | ForEach-Object {
        if ($_.FormID) {
            $rootDomain = Get-RootDomain -url $_.URL
            if (-not $domainFormIds.ContainsKey($rootDomain)) {
                $domainFormIds[$rootDomain] = [System.Collections.Generic.HashSet[string]]::new()
            }
            [void]$domainFormIds[$rootDomain].Add($_.FormID)
        }
    }
}

# Progress counter
$total = $urls.Count
$current = 0

foreach ($url in $urls) {
    $current++
    Write-Progress -Activity "Checking URLs" -Status "$current of $total" -PercentComplete (($current / $total) * 100)
      try {
        $domainForResults = Get-RootDomain -url $url
        Write-Host "Processing $url"
        Write-Host "Domain extracted: $domainForResults" -ForegroundColor Cyan
        
        # Send web request and get content
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers $headers
          # Look for all form IDs in the page using multiple patterns
        $formIds = @()
        
        # Ninja Forms pattern
        $nfMatches = [regex]::Matches($response.Content, 'id="nf-form-(\d+)-cont"')
        $formIds += $nfMatches | ForEach-Object { $_.Groups[1].Value }
        
        # Generic form patterns
        $formMatches = [regex]::Matches($response.Content, '<form[^>]*id="([^"]*form[^"]*)"')
        $formIds += $formMatches | ForEach-Object { $_.Groups[1].Value }
        
        # Additional Ninja Forms patterns
        $nfMatches2 = [regex]::Matches($response.Content, 'data-form-id="(\d+)"')
        $formIds += $nfMatches2 | ForEach-Object { $_.Groups[1].Value }
        
        # Filter out any empty or null values and get unique IDs
        $formIds = $formIds | Where-Object { $_ } | Select-Object -Unique
            
        # Initialize domain set if not exists
        if (-not $domainFormIds.ContainsKey($domainForResults)) {
            $domainFormIds[$domainForResults] = [System.Collections.Generic.HashSet[string]]::new()
        }
          # Process each form ID found
        foreach ($formId in $formIds) {            Write-Host "Checking if form $formId exists for domain: $domainForResults" -ForegroundColor Yellow
            if ($domainFormIds[$domainForResults].Add($formId)) {
                # Only add to results if this is a new form ID for this domain                Write-Host "Creating result with domain: $domainForResults" -ForegroundColor Magenta
                $result = [PSCustomObject]@{
                    URL = $url
                    RootDomain = $domainForResults
                    HasForm = $true
                    FormID = $formId
                    Status = 'Success'
                }
                $results += $result
                Write-Host "Found new form ID $formId on $url" -ForegroundColor Green
            } else {
                Write-Host "Form ID $formId already found for domain $domainForResults" -ForegroundColor Yellow
            }}
        
        if ($formIds.Count -eq 0) {
            Write-Host "No forms found on $url" -ForegroundColor Gray
        }
        
        # Add small delay to prevent overwhelming the server
        Start-Sleep -Milliseconds 500
        
    } catch {
        Write-Warning "Error processing $url : $($_.Exception.Message)"
    }
}

# Export results to CSV file
if ($results.Count -gt 0) {
    $results | Export-Csv -Path $outputPath -NoTypeInformation
    Write-Host "`nScan complete! Found $($results.Count) unique forms. Results saved to: $outputPath" -ForegroundColor Green
} else {
    Write-Warning "No forms were found during the scan"
}
