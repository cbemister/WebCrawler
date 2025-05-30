param(
    [Parameter(Mandatory=$false)]
    [string]$dealerName,
    [switch]$test
)

# Define paths
$scriptPath = $PSScriptRoot
$rootPath = Split-Path $scriptPath -Parent
$auditPath = Join-Path $rootPath "input\phone_numbers_audit.txt"
$urlsPath = Join-Path $rootPath "input\gm_site_urls_excl_brc.txt"
$outputPath = Join-Path $rootPath "output\number_address_check_results.csv"

# Define dealer domain mappings
$dealerDomains = @{
    "MAPLERIDGE_GM" = "mapleridgegm.com"
    "ISLAND_GM" = "islandgm.com"
    "PREMIER_CHEVROLET_BUICK_GMC" = "premierchevroletbuickgmc.kinsta.cloud"
    "SMP_CHEV" = "smpchev.ca"
    "MCNAUGHT_BUICK_GMC" = "mcnaughtbuickgmc.kinsta.cloud"
    "MCNAUGHT_CADILLAC" = "mcnaughtcadillac.kinsta.cloud"
    "PREMIER_CADILLAC" = "premiercadillac.kinsta.cloud"
    "MANN_NORTHWAY" = "mannnorthway.ca"
    "MARY_NURSE" = "marynurse.com"
    "NURSE_CADILLAC" = "nursecadillac.com"
}

# Verify input files exist
if (-not (Test-Path $auditPath)) {
    Write-Error "Audit file not found at: $auditPath"
    exit 1
}
if (-not (Test-Path $urlsPath)) {
    Write-Error "URLs file not found at: $urlsPath"
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

# Function to find content location in HTML
function Get-ContentLocation {
    param (
        [string]$html,
        [string]$searchPattern,
        [string]$content
    )
    
    $locations = @()
    
    try {
        if ($html -match "<script[^>]*>.*?$([regex]::Escape($content)).*?</script>") {
            $locations += "Script tag"
        }
        if ($html -match "<a[^>]*>.*?$([regex]::Escape($content)).*?</a>") {
            $locations += "Link text"
        }
        if ($html -match "content=`"[^`"]*$([regex]::Escape($content))[^`"]*`"") {
            $locations += "META tag"
        }
        if ($html -match "(?<!<[^>]*>)$([regex]::Escape($content))(?![^<]*>)") {
            $locations += "Page text"
        }
        
        if ($locations.Count -eq 0 -and $html -match [regex]::Escape($content)) {
            $locations += "Other HTML content"
        }
    }
    catch {
        Write-Warning "Error checking locations: $_"
        $locations += "Location check failed"
    }
    
    return ($locations | Select-Object -Unique) -join ", "
}

# Function to find phone numbers in content
function Get-PhoneNumbers {
    param (
        [string]$content,
        [string]$html
    )
    
    # More specific phone pattern requiring proper formatting
    $phonePattern = '(?x)
        (?:
            (?:\+?1[-\s.]?)?\(?[2-9]\d{2}\)?[-\s.]?[2-9]\d{2}[-\s.]?\d{4} |  # Standard format
            (?:1-)?[2-9]\d{2}[-\s.][2-9]\d{2}[-\s.]\d{4}                      # With optional 1-
        )
    '
    
    $matches = [regex]::Matches($content, $phonePattern)
    $results = @()
    
    foreach ($match in $matches) {
        $number = $match.Value -replace '[^\d]',''
        
        # Validate the number
        if ($number.Length -eq 10 -and
            # Exclude sequential numbers
            -not ($number -match '^0123456789|1234567890$') -and
            # First digit of area code should be 2-9
            $number[0] -match '[2-9]' -and
            # First digit of local number should be 2-9
            $number[3] -match '[2-9]' -and
            # Exclude repeated digits
            -not ($number -match '^(.)\1{9}$') -and
            # Exclude common false positives
            -not ($number -match '^(000|111|222|333|444|555|666|777|888|999)')) {
            
            # Get location
            $location = Get-ContentLocation -html $html -content $match.Value
            
            # Only include if found in meaningful locations
            if ($location -match "(Page text|Link text|META tag)") {
                $results += [PSCustomObject]@{
                    Number = $number
                    Location = $location
                }
            }
        }
    }
    
    return $results
}

# Function to find addresses in content
function Get-Addresses {
    param ([string]$content)
    
    # More specific address pattern that excludes common false positives
    $addressPattern = '\b(?<!(?:19|20)\d{2}\s)(?<!\d\s)\d+\s+[A-Za-z0-9\s\.-]+(?:Street|St|Road|Rd|Avenue|Ave|Highway|Hwy|Drive|Dr|Lane|Ln|Boulevard|Blvd|Way)\b(?!\s+(?:Custom|LT|4WD|RAV4|Series|[12][09]\d{2}))'
    
    try {
        $matches = [regex]::Matches($content, $addressPattern)
        return $matches | ForEach-Object { 
            $addr = $_.Value.Trim()
            $normalized = Normalize-Address $addr
            if ($normalized) { $addr }
        } | Select-Object -Unique
    }
    catch {
        Write-Warning "Error in address matching: $_"
        return @()
    }
}

# Function to normalize addresses for comparison
function Normalize-Address {
    param ([string]$address)
    
    # Remove common false positives first
    if ($address -match '(MPH|kW|BMW|Series|[12][09]\d{2}\s+(?!.*Street))' -or
        $address -match 'vehicle|graphic|center|Lane\s+Change|Auto\s+Lane') {
        return ''
    }
    
    $normalized = $address -replace '\s+', ' ' # Normalize spaces
    $normalized = $normalized -replace '(?i)Unit\s+#?\d+,?\s*', '' # Remove unit numbers for comparison
    $normalized = $normalized -replace '(?i)(?:Suite|Ste\.?)\s+#?\d+,?\s*', '' # Remove suite numbers
    $normalized = $normalized -replace '(?i)\bRd\b', 'Road'
    $normalized = $normalized -replace '(?i)\bSt\b', 'Street'
    $normalized = $normalized -replace '(?i)\bAve\b', 'Avenue'
    $normalized = $normalized -replace '(?i)\bBlvd\b', 'Boulevard'
    $normalized = $normalized -replace '(?i)\bDr\b', 'Drive'
    
    # Extract just the number and street portion if it matches a proper address pattern
    if ($normalized -match '^\d+\s+[A-Za-z0-9\s\.-]+(?:Road|Street|Avenue|Boulevard|Drive|Way|Highway|Lane)') {
        return $matches[0].Trim()
    }
    return ''
}

# Parse audit file
$dealerData = Parse-AuditFile -filePath $auditPath

# Filter dealer if specified
if ($dealerName) {
    if ($dealerData.ContainsKey($dealerName)) {
        $dealerData = @{ $dealerName = $dealerData[$dealerName] }
    } else {
        Write-Error "Dealer '$dealerName' not found in audit file"
        exit 1
    }
}

# Read URLs
$allUrls = Get-Content $urlsPath

$results = @()

foreach ($dealer in $dealerData.GetEnumerator()) {
    Write-Host "`nProcessing dealer: $($dealer.Key)" -ForegroundColor Cyan
    
    # Get domain for current dealer
    $dealerDomain = $dealerDomains[$dealer.Key]
    if (-not $dealerDomain) {
        Write-Warning "No domain mapping found for dealer $($dealer.Key)"
        continue
    }
    
    # Filter URLs for current dealer
    $urls = $allUrls | Where-Object { $_ -like "*$dealerDomain*" }
    
    if (-not $urls -or $urls.Count -eq 0) {
        Write-Warning "No URLs found for dealer $($dealer.Key) with domain $dealerDomain"
        continue
    }
    
    # If test mode, only check first 5 URLs
    if ($test) {
        $urls = $urls | Select-Object -First 5
        Write-Host "Test mode: checking only first 5 URLs" -ForegroundColor Yellow
    }
    
    # Get reference numbers and address
    $refPhones = $dealer.Value.Keys | 
        Where-Object { $_ -like "PHONE_*" } | 
        ForEach-Object { $dealer.Value[$_] -replace '[^\d]','' }
    $refAddress = $dealer.Value.ADDRESS
    
    foreach ($url in $urls) {
        Write-Host "Checking $url" -ForegroundColor Yellow
        
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing
            $content = $response.Content
            
            # Find phone numbers and addresses
            $foundPhones = Get-PhoneNumbers -content $content -html $content
            $foundAddresses = Get-Addresses -content $content
            
            # Compare addresses with better normalization
            $mismatchedAddresses = $foundAddresses | Where-Object {
                $foundAddr = Normalize-Address $_
                $refAddr = Normalize-Address $refAddress
                
                # Only include if both addresses are valid and don't match
                $foundAddr -and $refAddr -and 
                -not ($foundAddr -eq $refAddr -or 
                      $refAddr.StartsWith($foundAddr) -or 
                      $foundAddr.StartsWith($refAddr))
            }
            
            # Only add results if we found mismatches
            if ($wrongPhones -or $mismatchedAddresses) {
                $results += [PSCustomObject]@{
                    Dealer = $dealer.Key
                    URL = $url
                    FoundNumbers = ($wrongPhones | ForEach-Object { "$($_.Number) ($($_.Location))" }) -join "; "
                    FoundAddresses = ($mismatchedAddresses) -join "; "
                    ExpectedNumbers = ($refPhones -join "; ")
                    ExpectedAddress = $refAddress
                }
            }
        }
        catch {
            Write-Warning "Error processing $url : $_"
        }
        
        # Be nice to servers
        Start-Sleep -Milliseconds 500
    }
}

# Export results
$results | Export-Csv -Path $outputPath -NoTypeInformation

Write-Host "`nProcessing complete!" -ForegroundColor Green
Write-Host "Results saved to: $outputPath" -ForegroundColor Green
Write-Host "Total mismatches found: $($results.Count)" -ForegroundColor Green
