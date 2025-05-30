param(
    [Parameter(Mandatory=$false)]
    [string]$dealerName,
    [switch]$test
)

# Fix paths to correctly reference WebCrawler directory
$scriptPath = $PSScriptRoot
$rootPath = Split-Path $scriptPath -Parent
$auditPath = Join-Path $rootPath "input\phone_numbers_audit.txt"
$outputPath = Join-Path $rootPath "output\dealer_content_check_results.csv"

# Add path verification
if (-not (Test-Path $auditPath)) {
    Write-Error "Audit file not found at: $auditPath"
    Write-Host "Current paths:" -ForegroundColor Yellow
    Write-Host "Script path: $scriptPath" -ForegroundColor Yellow
    Write-Host "Root path: $rootPath" -ForegroundColor Yellow
    Write-Host "Audit path: $auditPath" -ForegroundColor Yellow
    exit 1
}

# Function to parse the audit file
function Parse-AuditFile {
    param ([string]$filePath)
    
    $dealers = @{}
    $content = Get-Content $filePath
    $currentDealer = $null
    
    foreach ($line in $content) {
        if ($line -match '^\[DEALERSHIP:(.+)\]$') {
            $currentDealer = $matches[1]
            $dealers[$currentDealer] = @{}
        }
        elseif ($line -match '^(.+)=(.+)$' -and $currentDealer) {
            $dealers[$currentDealer][$matches[1]] = $matches[2]
        }
    }
    return $dealers
}

# Function to get and parse sitemap
function Get-SitemapUrls {
    param ([string]$sitemapUrl)
    
    try {
        Write-Host "Fetching sitemap from: $sitemapUrl" -ForegroundColor Yellow
        $response = Invoke-WebRequest -Uri $sitemapUrl -UseBasicParsing
        
        Write-Host "Converting content to XML..." -ForegroundColor Yellow
        $xml = [xml]$response.Content
        
        # Handle XML namespace properly
        $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $ns.AddNamespace("sm", "http://www.sitemaps.org/schemas/sitemap/0.9")
        
        Write-Host "Extracting URLs from sitemap..." -ForegroundColor Yellow
        $urls = $xml.SelectNodes("//sm:url/sm:loc", $ns) | 
            ForEach-Object { $_.InnerText } |
            Where-Object { $_ -notmatch '/new/' }
        
        Write-Host "Found $($urls.Count) URLs in sitemap" -ForegroundColor Green
        return $urls
    }
    catch {
        Write-Error "Failed to get sitemap: $_"
        Write-Host "Response content: $($response.Content)" -ForegroundColor Red
        return @()
    }
}

# Function to extract phone numbers from content
function Get-PhoneNumbers {
    param ([string]$content)
    
    # Enhanced phone pattern to match more formats
    $phonePatterns = @(
        '(\d{3}[-.]?\d{3}[-.]?\d{4})',                     # Standard format
        '1[-.]?(\d{3}[-.]?\d{3}[-.]?\d{4})',              # With leading 1
        '[(]?\d{3}[)]?[-\s.]?\d{3}[-\s.]?\d{4}'          # With parentheses
    )
    
    $allMatches = @()
    foreach ($pattern in $phonePatterns) {
        $matches = [regex]::Matches($content, $pattern)
        $allMatches += $matches | ForEach-Object { 
            $_.Value -replace '[^\d]','' # Strip non-digits
        }
    }
    
    return $allMatches | Select-Object -Unique
}

# Function to extract addresses from content
function Get-Addresses {
    param ([string]$content)
    
    # Enhanced address pattern
    $addressPatterns = @(
        '(\d+[^,\n]{0,50}(?:Street|St|Road|Rd|Avenue|Ave|Highway|Hwy|Way)[^,\n]{0,30})',
        '(\d+[^,\n]{0,50}(?:Unit|#)[^,\n]{0,50}(?:Street|St|Road|Rd|Avenue|Ave|Highway|Hwy|Way)[^,\n]{0,30})'
    )
    
    $allMatches = @()
    foreach ($pattern in $addressPatterns) {
        $matches = [regex]::Matches($content, $pattern)
        $allMatches += $matches | ForEach-Object { 
            $_.Value.Trim()
        }
    }
    
    return $allMatches | Select-Object -Unique
}

# Helper function to convert filtered data to hashtable
function Convert-ToHashtable {
    param (
        [Parameter(ValueFromPipeline = $true)]
        $InputObject
    )
    
    $result = @{}
    foreach ($item in $InputObject) {
        $result[$item.Key] = $item.Value
    }
    return $result
}

# Import HTML parser functions
. (Join-Path $PSScriptRoot "html_parser.ps1")

# Parse the audit file
$dealerData = Parse-AuditFile -filePath $auditPath

# If dealer name specified, filter to just that dealer
if ($dealerName) {
    $filteredDealer = $dealerData.GetEnumerator() | 
        Where-Object { $_.Key -eq $dealerName }
    if ($filteredDealer) {
        $dealerData = @{ $filteredDealer.Key = $filteredDealer.Value }
    } else {
        Write-Error "Dealer '$dealerName' not found in audit file"
        exit 1
    }
}

$results = @()

foreach ($dealer in $dealerData.GetEnumerator()) {
    Write-Host "`nProcessing dealer: $($dealer.Key)" -ForegroundColor Cyan
    Write-Host "Sitemap URL: $($dealer.Value.SITEMAP)" -ForegroundColor Cyan
    
    # Get sitemap URLs
    $urls = Get-SitemapUrls -sitemapUrl $dealer.Value.SITEMAP
    
    if (-not $urls -or $urls.Count -eq 0) {
        Write-Warning "No URLs found for dealer $($dealer.Key)"
        continue
    }
    
    # If test mode, only check first 5 URLs
    if ($test) {
        $urls = $urls | Select-Object -First 5
        Write-Host "Test mode: checking only first 5 URLs" -ForegroundColor Yellow
    }
    
    foreach ($url in $urls) {
        Write-Host "Checking $url" -ForegroundColor Yellow
        
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing
            $content = $response.Content
            
            $pageTitle = ""
            if ($content -match '<title>(.+?)</title>') {
                $pageTitle = $matches[1]
            }

            # Extract phone numbers and addresses
            $foundPhones = Get-PhoneNumbersFromContent -content $content
            Write-Host "Found phones: $($foundPhones -join ', ')" -ForegroundColor Gray
            
            $foundAddresses = Get-AddressFromContent -content $content
            Write-Host "Found addresses: $($foundAddresses -join ', ')" -ForegroundColor Gray

            # Compare with reference data (only store mismatches)
            $refPhones = $dealer.Value.Keys | 
                Where-Object { $_ -like "PHONE_*" } | 
                ForEach-Object { $dealer.Value[$_] -replace '[^\d]','' }
            
            $wrongPhones = $foundPhones | Where-Object { 
                $phone = $_ -replace '[^\d]',''
                $phone -notin $refPhones -and $phone.Length -eq 10  # Validate length
            }
            
            $wrongAddresses = $foundAddresses | Where-Object { 
                $addr = $_ -replace '\s+', ' '
                -not ($dealer.Value.ADDRESS -replace '\s+', ' ').Contains($addr)
            }
            
            # Only add to results if actual mismatches found
            if ($wrongPhones -or $wrongAddresses) {
                $elementType = if ($wrongPhones) { 'Phone Number' } else { 'Address' }
                
                $results += [PSCustomObject]@{
                    Dealer = $dealer.Key
                    URL = $url
                    PageTitle = $pageTitle
                    IncorrectPhones = ($wrongPhones -join "; ")
                    IncorrectAddresses = ($wrongAddresses -join "; ")
                    ExpectedPhones = ($refPhones -join "; ")
                    ExpectedAddress = $dealer.Value.ADDRESS
                    ElementType = $elementType
                    Status = 'Mismatch Found'
                }
            }
        }
        catch {
            Write-Warning "Error processing $url : $_"
            # Only log errors that aren't 404s
            if (-not ($_.Exception.Response.StatusCode -eq 404)) {
                $results += [PSCustomObject]@{
                    Dealer = $dealer.Key
                    URL = $url
                    PageTitle = ''
                    Error = $_.Exception.Message
                    Status = 'Error'
                }
            }
        }
        
        # Be nice to the server
        Start-Sleep -Milliseconds 500
    }
}

# Export results
$results | Export-Csv -Path $outputPath -NoTypeInformation

Write-Host "`nProcessing complete!" -ForegroundColor Green
Write-Host "Results saved to: $outputPath" -ForegroundColor Green
Write-Host "Total URLs processed: $($results.Count)" -ForegroundColor Green

