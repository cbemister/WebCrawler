# SitemapCrawler.ps1
# A PowerShell script to crawl sitemaps and download HTML content

param(
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ".\downloaded_pages",
    
    [Parameter(Mandatory=$false)]
    [int]$DelayBetweenRequests = 1,
    
    [switch]$test
)

# Create output directory if it doesn't exist
if (-not (Test-Path -Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
    Write-Host "Created output directory: $OutputDirectory"
}

function Get-SafeFilename {
    param([string]$Url)
    $filename = [System.Web.HttpUtility]::UrlDecode($Url)
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $filename = $invalid | ForEach-Object { $filename = $filename.Replace($_, '_') }
    return $filename + ".html"
}

function Download-Page {
    param(
        [string]$Url,
        [string]$OutputPath
    )
    
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing
        $response.Content | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Host "Successfully downloaded: $Url"
        return $true
    }
    catch {
        Write-Warning "Failed to download $Url. Error: $($_.Exception.Message)"
        return $false
    }
}

# Add assembly for URL decoding
Add-Type -AssemblyName System.Web

function Read-SiteList {
    param (
        [bool]$isTest
    )
    
    $sitesFile = if ($isTest) {
        ".\sites\test-site.txt"
    } else {
        ".\sites\stellantis.txt"
    }
    
    Write-Host "Reading from file: $sitesFile"
    
    if (-not (Test-Path $sitesFile)) {
        throw "Sites file not found: $sitesFile"
    }
    
    $sites = @()
    $content = Get-Content $sitesFile -Raw
    $lines = $content -split '\r?\n' | Where-Object { $_ -match '^https?:\/\/' }
    
    foreach ($line in $lines) {
        Write-Host "Processing line: $line"
        $parts = $line.Split('|')
        if ($parts.Count -eq 2) {
            $site = @{
                Url = $parts[0].Trim()
                Folder = $parts[1].Trim()
            }
            Write-Host "Found site: $($site.Url) -> $($site.Folder)"
            $sites += $site
        } else {
            Write-Warning "Invalid line format: $line"
        }
    }
    
    if ($sites.Count -eq 0) {
        throw "No valid sites found in $sitesFile"
    }
    
    return $sites
}

function Create-FolderStructure {
    param (
        [string]$Url,
        [string]$BaseDir,
        [string]$SiteFolder
    )
    
    # Remove protocol and domain from URL
    $uri = [System.Uri]$Url
    $path = $uri.AbsolutePath.TrimStart('/')
    
    # Split the path into segments
    $segments = $path.TrimEnd('/').Split('/')
    
    # Last segment will be the filename, rest is the directory path
    $filename = if ($segments.Length -gt 0) { $segments[-1] } else { "index" }
    if ([string]::IsNullOrEmpty($filename)) { $filename = "index" }
    
    # Join all segments except the last one for the directory path
    $dirPath = if ($segments.Length -gt 1) {
        [string]::Join([IO.Path]::DirectorySeparatorChar, $segments[0..($segments.Length-2)])
    } else { "" }
    
    # Create the full directory path including the site folder
    $sitePath = Join-Path $BaseDir $SiteFolder
    $folderPath = Join-Path $sitePath $dirPath
    if (-not (Test-Path $folderPath)) {
        New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
    }
    
    # Return the full path where the HTML file should be saved
    return (Join-Path $folderPath "$filename.html")
}

function Process-Sitemap {
    param (
        [string]$SiteUrl,
        [string]$SiteFolder,
        [string]$OutputDir
    )
    
    $sitemapUrl = "$($SiteUrl.TrimEnd('/'))/page-sitemap.xml"
    Write-Host "Processing sitemap for $SiteFolder : $sitemapUrl"
    
    try {
        # Download sitemap
        $response = Invoke-WebRequest -Uri $sitemapUrl -UseBasicParsing
        Write-Host "Sitemap downloaded successfully. Content length: $($response.Content.Length)"
        
        # Parse the XML content
        [xml]$sitemap = $response.Content
        Write-Host "Sitemap XML parsed successfully"
        
        # Define namespace manager for XPath
        $ns = New-Object Xml.XmlNamespaceManager($sitemap.NameTable)
        $ns.AddNamespace("ns", "http://www.sitemaps.org/schemas/sitemap/0.9")
        
        # First check if this is a sitemap index
        $sitemapNodes = $sitemap.SelectNodes("//ns:sitemap/ns:loc", $ns)
        if ($sitemapNodes.Count -gt 0) {
            Write-Host "This is a sitemap index with $($sitemapNodes.Count) sitemaps"
            foreach ($sitemapNode in $sitemapNodes) {
                $subSitemapUrl = $sitemapNode.InnerText
                Write-Host "Processing sub-sitemap: $subSitemapUrl"
                try {
                    $subResponse = Invoke-WebRequest -Uri $subSitemapUrl -UseBasicParsing
                    [xml]$subSitemap = $subResponse.Content
                    $subSitemap.SelectNodes("//ns:url/ns:loc", $ns) | ForEach-Object {
                        ProcessUrl $_.InnerText $OutputDir $SiteFolder
                    }
                } catch {
                    Write-Error "Failed to process sub-sitemap $subSitemapUrl : $_"
                }
            }
        } else {
            # Process URLs from the main sitemap
            $urlNodes = $sitemap.SelectNodes("//ns:url/ns:loc", $ns)
            Write-Host "Found $($urlNodes.Count) URLs in sitemap"
            $urlNodes | ForEach-Object {
                ProcessUrl $_.InnerText $OutputDir $SiteFolder
            }
        }
    } catch {
        Write-Error "Failed to process sitemap for $SiteFolder : $_"
        Write-Error $_.Exception.Message
        Write-Error $_.ScriptStackTrace
    }
}

function ProcessUrl {
    param (
        [string]$url,
        [string]$OutputDir,
        [string]$SiteFolder
    )
    
    Write-Host "Processing URL: $url"
    
    # Create folder structure and get file path
    $outputPath = Create-FolderStructure -Url $url -BaseDir $OutputDir -SiteFolder $SiteFolder
    
    try {
        # Download page content with increased timeout
        $content = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
        
        # Save content
        $content.Content | Out-File -FilePath $outputPath -Encoding UTF8
        Write-Host "Saved to: $outputPath"
        
        # Add delay to prevent overwhelming the server
        Start-Sleep -Milliseconds 500
    } catch {
        Write-Warning "Failed to download $url : $_"
    }
}

# Main execution
try {
    Write-Host "Starting sitemap crawler..."
    Write-Host "Test mode: $test"
    
    $sites = Read-SiteList -isTest $test
    Write-Host "Found $($sites.Count) site(s) to process"
    
    foreach ($site in $sites) {
        Write-Host "`nProcessing site: $($site.Url)"
        Write-Host "Using folder: $($site.Folder)"
        Write-Host "Output directory: $OutputDirectory"
        
        try {
            Process-Sitemap -SiteUrl $site.Url -SiteFolder $site.Folder -OutputDir $OutputDirectory
        } catch {
            Write-Error "Failed to process site $($site.Url): $_"
            continue
        }
    }
    
    Write-Host "`nScript completed successfully"
} catch {
    Write-Error "Script execution failed: $_"
    Write-Error $_.ScriptStackTrace
}
