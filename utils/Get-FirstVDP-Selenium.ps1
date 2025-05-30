# PowerShell Selenium WebDriver VDP Crawler
param(
    [switch]$test,
    [int]$DelaySeconds = 3,
    [string]$ChromeDriverPath = ".\drivers\chromedriver.exe",
    [string]$ChromeBinaryPath = "",  # Optional: path to portable Chrome
    [switch]$Headless = $true,
    [switch]$Verbose
)

# Check if Selenium WebDriver module is available
if (-not (Get-Module -ListAvailable -Name Selenium)) {
    Write-Host "Installing Selenium WebDriver module..." -ForegroundColor Yellow
    try {
        Install-Module -Name Selenium -Force -Scope CurrentUser
        Write-Host "Selenium module installed successfully" -ForegroundColor Green
    } catch {
        Write-Error "Failed to install Selenium module. Please install manually: Install-Module -Name Selenium"
        exit 1
    }
}

Import-Module Selenium

function Initialize-WebDriver {
    param(
        [string]$ChromeDriverPath,
        [string]$ChromeBinaryPath,
        [bool]$Headless
    )
    
    try {
        # Chrome options for stealth browsing
        $chromeOptions = New-Object OpenQA.Selenium.Chrome.ChromeOptions
        
        if ($Headless) {
            $chromeOptions.AddArgument("--headless")
        }
        
        # Anti-detection arguments
        $chromeOptions.AddArgument("--no-sandbox")
        $chromeOptions.AddArgument("--disable-blink-features=AutomationControlled")
        $chromeOptions.AddArgument("--disable-extensions")
        $chromeOptions.AddArgument("--disable-plugins")
        $chromeOptions.AddArgument("--disable-images")
        $chromeOptions.AddArgument("--disable-javascript")  # We don't need JS for sitemaps
        $chromeOptions.AddArgument("--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
        
        # Use portable Chrome if specified
        if ($ChromeBinaryPath -and (Test-Path $ChromeBinaryPath)) {
            $chromeOptions.BinaryLocation = $ChromeBinaryPath
        }
        
        # Exclude automation switches
        $chromeOptions.AddExcludedArgument("enable-automation")
        $chromeOptions.AddAdditionalCapability("useAutomationExtension", $false)
        
        # Create ChromeDriver service
        $service = [OpenQA.Selenium.Chrome.ChromeDriverService]::CreateDefaultService($ChromeDriverPath)
        $service.HideCommandPromptWindow = $true
        
        # Initialize driver
        $driver = New-Object OpenQA.Selenium.Chrome.ChromeDriver($service, $chromeOptions)
        
        # Set timeouts
        $driver.Manage().Timeouts().ImplicitWait = [TimeSpan]::FromSeconds(10)
        $driver.Manage().Timeouts().PageLoad = [TimeSpan]::FromSeconds(30)
        
        Write-Host "WebDriver initialized successfully" -ForegroundColor Green
        return $driver
        
    } catch {
        Write-Error "Failed to initialize WebDriver: $($_.Exception.Message)"
        Write-Host "Make sure ChromeDriver is available at: $ChromeDriverPath" -ForegroundColor Yellow
        Write-Host "Download from: https://chromedriver.chromium.org/" -ForegroundColor Yellow
        return $null
    }
}

function Get-InventorySitemapWithBrowser {
    param (
        [string]$baseUrl,
        [object]$driver
    )
    
    Write-Host "Using browser automation for: $baseUrl" -ForegroundColor Cyan
    
    try {
        # First visit the main page to establish session
        Write-Host "Visiting main page: $baseUrl"
        $driver.Navigate().GoToUrl($baseUrl)
        Start-Sleep -Seconds (Get-Random -Minimum 2 -Maximum 5)  # Random human-like delay
        
        # Check if main page loaded successfully
        if ($driver.Title -match "403|Forbidden|Access Denied") {
            throw "Main page blocked with 403 error"
        }
        
        Write-Host "Main page loaded successfully: $($driver.Title)" -ForegroundColor Green
        
        # Try to access the inventory sitemap
        $inventorySitemapUrl = "$($baseUrl.TrimEnd('/'))/dealer-inspire-inventory/inventory_sitemap.xml"
        Write-Host "Accessing inventory sitemap: $inventorySitemapUrl"
        
        $driver.Navigate().GoToUrl($inventorySitemapUrl)
        Start-Sleep -Seconds 2
        
        # Check if sitemap loaded
        $pageSource = $driver.PageSource
        if ($pageSource -match "403|Forbidden|Access Denied") {
            throw "Sitemap blocked with 403 error"
        }
        
        if ($pageSource -match "<urlset" -or $pageSource -match "<sitemapindex") {
            Write-Host "Successfully accessed inventory sitemap" -ForegroundColor Green
            return @{
                Url = $inventorySitemapUrl
                Content = $pageSource
            }
        }
        
        # Try alternative sitemap paths
        $alternativePaths = @("/sitemap.xml", "/sitemaps/inventory.xml", "/inventory-sitemap.xml")
        
        foreach ($path in $alternativePaths) {
            $altUrl = "$($baseUrl.TrimEnd('/'))" + $path
            Write-Host "Trying alternative sitemap: $altUrl"
            
            try {
                $driver.Navigate().GoToUrl($altUrl)
                Start-Sleep -Seconds 1
                
                $pageSource = $driver.PageSource
                if ($pageSource -match "<urlset" -or $pageSource -match "<sitemapindex") {
                    if ($pageSource -match "inventory|vehicle|vdp") {
                        Write-Host "Found alternative sitemap with inventory content" -ForegroundColor Green
                        return @{
                            Url = $altUrl
                            Content = $pageSource
                        }
                    }
                }
            } catch {
                if ($Verbose) {
                    Write-Host "Alternative path $path failed: $($_.Exception.Message)" -ForegroundColor Gray
                }
            }
        }
        
        throw "No accessible sitemap found"
        
    } catch {
        Write-Warning "Browser automation failed for $baseUrl : $($_.Exception.Message)"
        return $null
    }
}

function Get-FirstVDPFromSitemap {
    param (
        [string]$sitemapContent
    )
    
    try {
        [xml]$sitemap = $sitemapContent
        
        $ns = New-Object Xml.XmlNamespaceManager($sitemap.NameTable)
        $ns.AddNamespace("ns", "http://www.sitemaps.org/schemas/sitemap/0.9")
        
        # Get first VDP URL
        $firstUrl = $sitemap.SelectNodes("//ns:url/ns:loc", $ns) | 
            Select-Object -First 1
        
        if ($firstUrl) {
            return $firstUrl.InnerText
        }
        
    } catch {
        Write-Warning "Failed to parse sitemap XML: $($_.Exception.Message)"
    }
    
    return $null
}

function Process-SiteListWithBrowser {
    param (
        [string]$inputFile,
        [string]$outputFile
    )
    
    Write-Host "Browser-based VDP Crawler Starting..." -ForegroundColor Magenta
    Write-Host "Input: $inputFile" -ForegroundColor White
    Write-Host "Output: $outputFile" -ForegroundColor White
    Write-Host "Headless mode: $Headless" -ForegroundColor White
    
    # Initialize WebDriver
    $driver = Initialize-WebDriver -ChromeDriverPath $ChromeDriverPath -ChromeBinaryPath $ChromeBinaryPath -Headless $Headless
    if (-not $driver) {
        Write-Error "Cannot proceed without WebDriver"
        return
    }
    
    try {
        $results = @()
        $sites = Get-Content $inputFile | Where-Object { $_ -match '^https?:\/\/' }
        $totalSites = $sites.Count
        $successfulSites = 0
        
        Write-Host "`nProcessing $totalSites sites with browser automation..." -ForegroundColor Cyan
        
        foreach ($site in $sites) {
            $parts = $site.Split('|').Trim()
            $baseUrl = $parts[0]
            $folder = $parts[1]
            
            Write-Host "`n" + "="*60 -ForegroundColor Blue
            Write-Host "Processing: $baseUrl" -ForegroundColor White
            Write-Host "="*60 -ForegroundColor Blue
            
            try {
                $sitemapResult = Get-InventorySitemapWithBrowser -baseUrl $baseUrl -driver $driver
                
                if ($sitemapResult) {
                    Write-Host "Found sitemap: $($sitemapResult.Url)" -ForegroundColor Green
                    
                    $vdpUrl = Get-FirstVDPFromSitemap -sitemapContent $sitemapResult.Content
                    if ($vdpUrl) {
                        Write-Host "SUCCESS: Found VDP URL: $vdpUrl" -ForegroundColor Green
                        $results += "$vdpUrl|$folder"
                        $successfulSites++
                    } else {
                        Write-Warning "No VDP URLs found in sitemap"
                    }
                } else {
                    Write-Warning "Could not access any sitemap for $baseUrl"
                }
                
            } catch {
                Write-Error "Error processing $baseUrl : $($_.Exception.Message)"
            }
            
            # Delay between sites
            if ($DelaySeconds -gt 0) {
                Write-Host "Waiting $DelaySeconds seconds before next site..." -ForegroundColor Gray
                Start-Sleep -Seconds $DelaySeconds
            }
        }
        
        # Save results
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
        
    } finally {
        # Always cleanup WebDriver
        if ($driver) {
            Write-Host "Closing browser..." -ForegroundColor Yellow
            $driver.Quit()
            $driver.Dispose()
        }
    }
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
    $outputFile = Join-Path $outputDir "test-vdp-selenium.txt"
} else {
    $inputFile = Join-Path $inputDir "stellantis.txt"
    $outputFile = Join-Path $outputDir "stellantis-vdp-selenium.txt"
}

Process-SiteListWithBrowser -inputFile $inputFile -outputFile $outputFile
