# Initialize arrays to store results
$successfulUrls = @()
$failedUrls = @()
$allExtractedUrls = @()

# Define paths relative to script location
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
$inputPath = Join-Path $rootDir "input\stellantis_pagemap_urls.txt"
$resultsPath = Join-Path $rootDir "results"

# Verify input file exists
if (-not (Test-Path $inputPath)) {
    Write-Host "Error: Input file not found at: $inputPath"
    exit 1
}

# Read sitemap URLs from input file
$sitemapUrls = Get-Content -Path $inputPath

# Create results directory if it doesn't exist
if (-not (Test-Path $resultsPath)) {
    New-Item -ItemType Directory -Path $resultsPath | Out-Null
}

# Define headers with more browser-like characteristics
$headers = @{
    'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/113.0.0.0 Safari/537.36'
    'Accept' = 'text/html,application/xhtml+xml,application/xml;q=0.9'
    'Accept-Language' = 'en-US,en;q=0.9'
    'Accept-Encoding' = 'gzip, deflate, br'
    'Sec-Fetch-Site' = 'none'
    'Sec-Fetch-Mode' = 'navigate'
    'Sec-Fetch-User' = '?1'
    'Sec-Fetch-Dest' = 'document'
    'Upgrade-Insecure-Requests' = '1'
}

# Create a web session
$webSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession

function Get-RandomDelay {
    return Get-Random -Minimum 3 -Maximum 8
}

function Invoke-RequestWithRetry {
    param(
        [string]$url,
        [int]$maxRetries = 3
    )
    
    for ($i = 0; $i -lt $maxRetries; $i++) {
        try {
            Start-Sleep -Seconds (Get-RandomDelay)
            return Invoke-WebRequest -Uri $url -Headers $headers -WebSession $webSession -UseBasicParsing -TimeoutSec 30
        }
        catch {
            Write-Host "Attempt $($i + 1) failed: $_"
            if ($i -eq $maxRetries - 1) { throw }
        }
    }
}

foreach ($sitemapUrl in $sitemapUrls) {
    try {
        Write-Host "Processing: $sitemapUrl"
        
        # Fetch XML content with retry logic
        $response = Invoke-RequestWithRetry -url $sitemapUrl
        
        # Parse XML
        $xml = [xml]$response.Content
        
        # Extract URLs from sitemap
        $extractedUrls = $xml.SelectNodes("//url/loc") | ForEach-Object { $_.InnerText }
        
        # Add to successful URLs
        $successfulUrls += @{
            SitemapUrl = $sitemapUrl
            Status = "Success"
            UrlCount = $extractedUrls.Count
        }
        
        # Add to all extracted URLs
        $allExtractedUrls += $extractedUrls
        
    } catch {
        Write-Host "Failed to process: $sitemapUrl"
        Write-Host "Error: $_"
        
        # Add to failed URLs
        $failedUrls += @{
            SitemapUrl = $sitemapUrl
            Status = "Failed"
            Error = $_.Exception.Message
        }
    }
}

# Export successful URLs report
$successfulUrls | ForEach-Object {
    [PSCustomObject]$_
} | Export-Csv -Path (Join-Path $resultsPath "successful_sitemaps.csv") -NoTypeInformation

# Export failed URLs report
$failedUrls | ForEach-Object {
    [PSCustomObject]$_
} | Export-Csv -Path (Join-Path $resultsPath "failed_sitemaps.csv") -NoTypeInformation

# Export all unique URLs
$allExtractedUrls | Select-Object -Unique | Out-File (Join-Path $resultsPath "all_unique_urls.txt")

# Generate summary report
$summary = @{
    TotalSitemaps = $sitemapUrls.Count
    SuccessfulSitemaps = $successfulUrls.Count
    FailedSitemaps = $failedUrls.Count
    TotalUniqueUrls = ($allExtractedUrls | Select-Object -Unique).Count
}

[PSCustomObject]$summary | Export-Csv -Path (Join-Path $resultsPath "summary_report.csv") -NoTypeInformation

Write-Host "Processing complete. Check the 'results' directory for reports."
