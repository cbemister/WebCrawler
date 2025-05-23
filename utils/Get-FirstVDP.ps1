# Script to extract first VDP URL from inventory sitemaps
param(
    [switch]$test
)

function Get-InventorySitemap {
    param (
        [string]$baseUrl
    )
    
    # Direct path to inventory sitemap for Stellantis dealers
    $inventorySitemapUrl = "$($baseUrl.TrimEnd('/'))/dealer-inspire-inventory/inventory_sitemap.xml"
    Write-Host "Checking inventory sitemap: $inventorySitemapUrl"
      try {
        # Try to download inventory sitemap directly
        $response = Invoke-WebRequest -Uri $inventorySitemapUrl -UseBasicParsing
        Write-Host "Successfully found inventory sitemap" -ForegroundColor Green
        return $inventorySitemapUrl
    } catch {
        Write-Warning "Failed to process sitemap for $baseUrl : $_"
    }
    return $null
}

function Get-FirstVDPUrl {
    param (
        [string]$sitemapUrl
    )
    
    try {
        $response = Invoke-WebRequest -Uri $sitemapUrl -UseBasicParsing
        [xml]$sitemap = $response.Content
        
        $ns = New-Object Xml.XmlNamespaceManager($sitemap.NameTable)
        $ns.AddNamespace("ns", "http://www.sitemaps.org/schemas/sitemap/0.9")
        
        # Get first VDP URL
        $firstUrl = $sitemap.SelectNodes("//ns:url/ns:loc", $ns) | 
            Select-Object -First 1
        
        if ($firstUrl) {
            return $firstUrl.InnerText
        }
    } catch {
        Write-Warning "Failed to get VDP URL from $sitemapUrl : $_"
    }
    return $null
}

function Process-SiteList {
    param (
        [string]$inputFile,
        [string]$outputFile
    )
    
    Write-Host "Processing sites from $inputFile"
    Write-Host "Results will be saved to $outputFile"
    
    $results = @()
    
    Get-Content $inputFile | Where-Object { $_ -match '^https?:\/\/' } | ForEach-Object {
        $parts = $_.Split('|').Trim()
        $baseUrl = $parts[0]
        $folder = $parts[1]
        
        Write-Host "`nProcessing $baseUrl"
        
        # Get inventory sitemap URL
        $inventorySitemapUrl = Get-InventorySitemap -baseUrl $baseUrl
        if ($inventorySitemapUrl) {
            Write-Host "Found inventory sitemap: $inventorySitemapUrl"
            
            # Get first VDP URL
            $vdpUrl = Get-FirstVDPUrl -sitemapUrl $inventorySitemapUrl
            if ($vdpUrl) {
                Write-Host "Found VDP URL: $vdpUrl"
                $results += "$vdpUrl|$folder"
            }
        }
    }
    
    # Save results
    if ($results.Count -gt 0) {
        $results | Out-File -FilePath $outputFile -Encoding UTF8
        Write-Host "`nSaved $($results.Count) VDP URLs to $outputFile"
    } else {
        Write-Warning "No VDP URLs found"
    }
}

# Main execution
$scriptDir = Split-Path -Parent $PSScriptRoot
$inputDir = Join-Path $scriptDir "input"
$outputDir = Join-Path $scriptDir "output"

if ($test) {
    $inputFile = Join-Path $inputDir "test-site.txt"
    $outputFile = Join-Path $outputDir "test-vdp.txt"
} else {
    $inputFile = Join-Path $inputDir "stellantis.txt"
    $outputFile = Join-Path $outputDir "stellantis-vdp.txt"
}

Process-SiteList -inputFile $inputFile -outputFile $outputFile
