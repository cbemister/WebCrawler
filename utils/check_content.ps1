# Get command line parameters
param(
    [switch]$test
)

# Define paths relative to script location
$scriptPath = $PSScriptRoot
$rootPath = Split-Path $scriptPath -Parent
$inputPath = Join-Path $rootPath "input\gm_site_urls_excl_brc.txt"
$outputPath = Join-Path $rootPath "output\content_check_results.csv"

# Define the content to search for
$searchContent = @(
    "Bridges",
    "North Battleford",
    "306-445-3300"
)

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

# Create array to store results
$results = @()

# Function to find content location in HTML
function Get-ContentLocation {
    param (
        [string]$html,
        [string]$searchTerm
    )
    
    $locations = @()
    
    try {
        # 1. Check Meta tags
        if ($html -match "<meta[^>]*content=`"[^`"]*$([regex]::Escape($searchTerm))[^`"]*`"") {
            $locations += "META tag"
        }
        
        # 2. Check Links
        if ($html -match "<a[^>]*>[^<]*$([regex]::Escape($searchTerm))[^<]*</a>") {
            $locations += "Link text"
        }
        
        # 3. Check class attributes
        if ($html -match "class=`"[^`"]*$([regex]::Escape($searchTerm))[^`"]*`"") {
            $locations += "HTML class"
        }
        
        # 4. Check plain text between tags (excluding script and style tags)
        if ($html -match "(?<!<script[^>]*>)(?<!<style[^>]*>)>[^<]*$([regex]::Escape($searchTerm))[^<]*<") {
            $locations += "Page text"
        }
        
        # 5. Check header content
        if ($html -match "<h[1-6][^>]*>[^<]*$([regex]::Escape($searchTerm))[^<]*</h[1-6]>") {
            $locations += "Heading"
        }
        
        # 6. If none of the above but content exists somewhere in HTML
        if ($locations.Count -eq 0 -and $html -match [regex]::Escape($searchTerm)) {
            $locations += "Other HTML content"
        }
        
    } catch {
        Write-Warning "Error checking locations: $_"
        if ($html -match "class=`"[^`"]*$([regex]::Escape($searchTerm))[^`"]*`"") {
            $locations += "HTML class"
        } elseif ($html -match [regex]::Escape($searchTerm)) {
            $locations += "Other HTML content"
        }
    }
    
    # Return unique locations joined by comma
    return ($locations | Select-Object -Unique) -join ", "
}

# Progress counter
$total = $urls.Count
$current = 0

foreach ($url in $urls) {
    $current++
    Write-Progress -Activity "Checking URLs" -Status "$current of $total" -PercentComplete (($current / $total) * 100)
    
    try {
        Write-Host "Processing $url" -ForegroundColor Cyan
        
        # Send web request and get content
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing
        
        # Check for each search term
        foreach ($term in $searchContent) {
            if ($response.Content -match [regex]::Escape($term)) {
                Write-Host "Found '$term' on $url" -ForegroundColor Yellow
                
                # Get location of the content
                $location = Get-ContentLocation -html $response.Content -searchTerm $term
                
                # Add to results
                $result = [PSCustomObject]@{
                    URL = $url
                    FoundContent = $term
                    Location = $location
                }
                $results += $result
            }
        }
        
    } catch {
        Write-Warning "Error processing $url : $_"
        # Add error to results
        $result = [PSCustomObject]@{
            URL = $url
            FoundContent = "ERROR: $_"
            Location = "Error processing page"
        }
        $results += $result
    }
    
    # Add a small delay to be nice to servers
    Start-Sleep -Milliseconds 500
}

# Export results to CSV
$results | Export-Csv -Path $outputPath -NoTypeInformation

Write-Host "`nProcessing complete!" -ForegroundColor Green
Write-Host "Results saved to: $outputPath" -ForegroundColor Green
Write-Host "Total URLs processed: $total" -ForegroundColor Green
Write-Host "Total matches found: $($results.Count)" -ForegroundColor Green