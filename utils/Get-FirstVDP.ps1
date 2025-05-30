# Script to extract first VDP URL from inventory sitemaps
param(
    [switch]$test,
    [int]$DelaySeconds = 2,
    [int]$MaxRetries = 3,
    [switch]$Verbose
)

# Enhanced web request function with browser-like headers and retry logic
function Invoke-EnhancedWebRequest {
    param (
        [string]$Uri,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 2
    )

    # Realistic browser headers to avoid detection
    # Note: PowerShell's Invoke-WebRequest manages certain headers automatically
    # Removed 'Connection' and 'Accept-Encoding' as they conflict with PowerShell's implementation

    # Randomize User-Agent to avoid pattern detection
    $userAgents = @(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Edge/120.0.0.0 Safari/537.36'
    )
    $selectedUserAgent = $userAgents | Get-Random

    $headers = @{
        'User-Agent' = $selectedUserAgent
        'Accept' = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7'
        'Accept-Language' = 'en-US,en;q=0.9'
        'Cache-Control' = 'no-cache'
        'Pragma' = 'no-cache'
        'Upgrade-Insecure-Requests' = '1'
        'Sec-Fetch-Dest' = 'document'
        'Sec-Fetch-Mode' = 'navigate'
        'Sec-Fetch-Site' = 'none'
        'Sec-Fetch-User' = '?1'
    }

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            if ($Verbose) {
                Write-Host "Attempt $attempt/$MaxRetries for $Uri" -ForegroundColor Yellow
            }

            # Create a session to maintain cookies and state
            $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

            # Add referer header if this is not the first request to the domain
            $domain = ([System.Uri]$Uri).Host
            if (-not $headers.ContainsKey('Referer')) {
                $headers['Referer'] = "https://$domain/"
            }

            $response = Invoke-WebRequest -Uri $Uri -Headers $headers -UseBasicParsing -TimeoutSec 30 -WebSession $session

            if ($Verbose) {
                Write-Host "Success: HTTP $($response.StatusCode)" -ForegroundColor Green
            }

            return $response

        } catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            Write-Warning "Attempt $attempt failed for $Uri - Status: $statusCode - Error: $($_.Exception.Message)"

            if ($attempt -lt $MaxRetries) {
                $waitTime = $DelaySeconds * [Math]::Pow(2, $attempt - 1)  # Exponential backoff
                # Add some randomness to avoid pattern detection
                $randomDelay = Get-Random -Minimum 1 -Maximum 3
                $totalWait = $waitTime + $randomDelay
                Write-Host "Waiting $totalWait seconds before retry (base: $waitTime + random: $randomDelay)..." -ForegroundColor Yellow
                Start-Sleep -Seconds $totalWait
            }
        }
    }

    throw "Failed to retrieve $Uri after $MaxRetries attempts"
}

function Get-InventorySitemap {
    param (
        [string]$baseUrl
    )

    # First, try to access the main page to establish a session and appear more natural
    Write-Host "Establishing session with main page: $baseUrl"
    try {
        $mainPageResponse = Invoke-EnhancedWebRequest -Uri $baseUrl -MaxRetries 1 -DelaySeconds 1
        Write-Host "Successfully accessed main page" -ForegroundColor Green
        Start-Sleep -Seconds 1  # Brief pause to mimic human behavior
    } catch {
        Write-Warning "Could not access main page, proceeding anyway: $($_.Exception.Message)"
    }

    # Primary: Direct path to inventory sitemap for Stellantis dealers
    $inventorySitemapUrl = "$($baseUrl.TrimEnd('/'))/dealer-inspire-inventory/inventory_sitemap.xml"
    Write-Host "Checking inventory sitemap: $inventorySitemapUrl"

    try {
        # Try to download inventory sitemap directly with enhanced request
        $response = Invoke-EnhancedWebRequest -Uri $inventorySitemapUrl -MaxRetries $MaxRetries -DelaySeconds $DelaySeconds
        Write-Host "Successfully found inventory sitemap" -ForegroundColor Green
        return $inventorySitemapUrl
    } catch {
        Write-Warning "Primary sitemap failed for $baseUrl : $($_.Exception.Message)"
    }

    # Fallback 1: Try alternative sitemap paths
    $alternativePaths = @(
        "/sitemap.xml",
        "/sitemaps/inventory.xml",
        "/inventory-sitemap.xml",
        "/sitemap_index.xml"
    )

    foreach ($path in $alternativePaths) {
        $altUrl = "$($baseUrl.TrimEnd('/'))" + $path
        Write-Host "Trying alternative sitemap: $altUrl"

        try {
            $response = Invoke-EnhancedWebRequest -Uri $altUrl -MaxRetries 1 -DelaySeconds 1

            # Check if this sitemap contains inventory URLs
            if ($response.Content -match "inventory|vehicle|vdp" -or $response.Content -match "dealer-inspire") {
                Write-Host "Found alternative sitemap with inventory content" -ForegroundColor Green
                return $altUrl
            }
        } catch {
            if ($Verbose) {
                Write-Host "Alternative path $path failed: $($_.Exception.Message)" -ForegroundColor Gray
            }
        }
    }

    Write-Warning "No accessible sitemap found for $baseUrl"
    return $null
}

function Get-FirstVDPUrl {
    param (
        [string]$sitemapUrl,
        [string]$baseUrl
    )

    try {
        $response = Invoke-EnhancedWebRequest -Uri $sitemapUrl -MaxRetries $MaxRetries -DelaySeconds $DelaySeconds
        [xml]$sitemap = $response.Content

        $ns = New-Object Xml.XmlNamespaceManager($sitemap.NameTable)
        $ns.AddNamespace("ns", "http://www.sitemaps.org/schemas/sitemap/0.9")

        # Get first VDP URL
        $firstUrl = $sitemap.SelectNodes("//ns:url/ns:loc", $ns) |
            Select-Object -First 1

        if ($firstUrl) {
            return $firstUrl.InnerText
        }

        # If no URLs found in sitemap, try fallback method
        Write-Warning "No VDP URLs found in sitemap, trying fallback method"
        return Get-VDPUrlFallback -baseUrl $baseUrl

    } catch {
        Write-Warning "Failed to get VDP URL from $sitemapUrl : $($_.Exception.Message)"

        # Try fallback method if sitemap parsing fails
        Write-Host "Attempting fallback VDP discovery method..." -ForegroundColor Yellow
        return Get-VDPUrlFallback -baseUrl $baseUrl
    }
}

function Get-VDPUrlFallback {
    param (
        [string]$baseUrl
    )

    # Fallback: Try to find VDP URLs by parsing common inventory pages
    $inventoryPaths = @(
        "/inventory",
        "/vehicles",
        "/new-inventory",
        "/used-inventory",
        "/search-inventory"
    )

    foreach ($path in $inventoryPaths) {
        $inventoryUrl = "$($baseUrl.TrimEnd('/'))" + $path
        Write-Host "Trying inventory page: $inventoryUrl"

        try {
            $response = Invoke-EnhancedWebRequest -Uri $inventoryUrl -MaxRetries 1 -DelaySeconds 1

            # Look for VDP URLs in the page content using regex patterns
            $vdpPatterns = @(
                "href=[`"']([^`"']*(?:vehicle|vdp|detail)[^`"']*)[`"']",
                "href=[`"']([^`"']*\/\d+\/[^`"']*)[`"']",  # URLs with numeric IDs
                "href=[`"']([^`"']*inventory\/[^`"']*)[`"']"
            )

            foreach ($pattern in $vdpPatterns) {
                $regexMatches = [regex]::Matches($response.Content, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

                if ($regexMatches.Count -gt 0) {
                    $vdpUrl = $regexMatches[0].Groups[1].Value

                    # Convert relative URLs to absolute
                    if ($vdpUrl -notmatch "^https?://") {
                        if ($vdpUrl.StartsWith("/")) {
                            $vdpUrl = "$($baseUrl.TrimEnd('/'))" + $vdpUrl
                        } else {
                            $vdpUrl = "$($baseUrl.TrimEnd('/'))/" + $vdpUrl
                        }
                    }

                    Write-Host "Found VDP URL via fallback method: $vdpUrl" -ForegroundColor Green
                    return $vdpUrl
                }
            }

        } catch {
            if ($Verbose) {
                Write-Host "Fallback inventory page $path failed: $($_.Exception.Message)" -ForegroundColor Gray
            }
        }
    }

    Write-Warning "No VDP URLs found via fallback methods"
    return $null
}

function Invoke-SiteListProcessing {
    param (
        [string]$inputFile,
        [string]$outputFile
    )

    Write-Host "Processing sites from $inputFile" -ForegroundColor Cyan
    Write-Host "Results will be saved to $outputFile" -ForegroundColor Cyan
    Write-Host "Rate limiting: $DelaySeconds seconds between requests" -ForegroundColor Cyan
    Write-Host "Max retries: $MaxRetries per request" -ForegroundColor Cyan

    $results = @()
    $totalSites = 0
    $successfulSites = 0

    $sites = Get-Content $inputFile | Where-Object { $_ -match '^https?:\/\/' }
    $totalSites = $sites.Count

    Write-Host "`nProcessing $totalSites sites..." -ForegroundColor Cyan

    foreach ($site in $sites) {
        $parts = $site.Split('|').Trim()
        $baseUrl = $parts[0]
        $folder = $parts[1]

        Write-Host "`n" + "="*60 -ForegroundColor Blue
        Write-Host "Processing: $baseUrl" -ForegroundColor White
        Write-Host "="*60 -ForegroundColor Blue

        try {
            # Get inventory sitemap URL
            $inventorySitemapUrl = Get-InventorySitemap -baseUrl $baseUrl
            if ($inventorySitemapUrl) {
                Write-Host "Found inventory sitemap: $inventorySitemapUrl" -ForegroundColor Green

                # Get first VDP URL (now passing baseUrl for fallback)
                $vdpUrl = Get-FirstVDPUrl -sitemapUrl $inventorySitemapUrl -baseUrl $baseUrl
                if ($vdpUrl) {
                    Write-Host "SUCCESS: Found VDP URL: $vdpUrl" -ForegroundColor Green
                    $results += "$vdpUrl|$folder"
                    $successfulSites++
                } else {
                    Write-Warning "No VDP URL found for $baseUrl"
                }
            } else {
                Write-Warning "No accessible sitemap found for $baseUrl"

                # Try direct fallback method
                Write-Host "Attempting direct VDP discovery..." -ForegroundColor Yellow
                $vdpUrl = Get-VDPUrlFallback -baseUrl $baseUrl
                if ($vdpUrl) {
                    Write-Host "SUCCESS: Found VDP URL via fallback: $vdpUrl" -ForegroundColor Green
                    $results += "$vdpUrl|$folder"
                    $successfulSites++
                }
            }
        } catch {
            Write-Error "Error processing $baseUrl : $($_.Exception.Message)"
        }

        # Rate limiting between sites
        if ($DelaySeconds -gt 0) {
            Write-Host "Waiting $DelaySeconds seconds before next site..." -ForegroundColor Gray
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    # Save results and show summary
    Write-Host "`n" + "="*60 -ForegroundColor Green
    Write-Host "PROCESSING COMPLETE" -ForegroundColor Green
    Write-Host "="*60 -ForegroundColor Green

    if ($results.Count -gt 0) {
        $results | Out-File -FilePath $outputFile -Encoding UTF8
        Write-Host "SUCCESS: Saved $($results.Count) VDP URLs to $outputFile" -ForegroundColor Green
    } else {
        Write-Warning "No VDP URLs found from any sites"
    }

    Write-Host "Summary: $successfulSites/$totalSites sites processed successfully" -ForegroundColor Cyan
}

# Main execution
$scriptDir = Split-Path -Parent $PSScriptRoot
$inputDir = Join-Path $scriptDir "input"
$outputDir = Join-Path $scriptDir "output"

# Ensure output directory exists
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

if ($test) {
    $inputFile = Join-Path $inputDir "test-site.txt"
    $outputFile = Join-Path $outputDir "test-vdp.txt"
} else {
    $inputFile = Join-Path $inputDir "stellantis.txt"
    $outputFile = Join-Path $outputDir "stellantis-vdp.txt"
}

# Display configuration
Write-Host "Enhanced VDP Crawler Configuration:" -ForegroundColor Magenta
Write-Host "- Input file: $inputFile" -ForegroundColor White
Write-Host "- Output file: $outputFile" -ForegroundColor White
Write-Host "- Delay between requests: $DelaySeconds seconds" -ForegroundColor White
Write-Host "- Max retries per request: $MaxRetries" -ForegroundColor White
Write-Host "- Verbose logging: $Verbose" -ForegroundColor White
Write-Host ""

Invoke-SiteListProcessing -inputFile $inputFile -outputFile $outputFile
