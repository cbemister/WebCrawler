# Quick test script to verify HTTP headers are working
param(
    [string]$TestUrl = "https://httpbin.org/headers"
)

# Test the enhanced web request function
function Test-EnhancedWebRequest {
    param (
        [string]$Uri
    )
    
    # Randomize User-Agent to avoid pattern detection
    $userAgents = @(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0'
    )
    $selectedUserAgent = $userAgents | Get-Random
    
    $headers = @{
        'User-Agent' = $selectedUserAgent
        'Accept' = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8'
        'Accept-Language' = 'en-US,en;q=0.9'
        'Cache-Control' = 'no-cache'
        'Pragma' = 'no-cache'
        'Upgrade-Insecure-Requests' = '1'
        'Sec-Fetch-Dest' = 'document'
        'Sec-Fetch-Mode' = 'navigate'
        'Sec-Fetch-Site' = 'none'
        'Sec-Fetch-User' = '?1'
    }
    
    try {
        Write-Host "Testing enhanced headers with: $Uri" -ForegroundColor Cyan
        Write-Host "Selected User-Agent: $selectedUserAgent" -ForegroundColor Yellow
        
        # Create a session to maintain cookies and state
        $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        
        # Add referer header
        $domain = ([System.Uri]$Uri).Host
        $headers['Referer'] = "https://$domain/"
        
        $response = Invoke-WebRequest -Uri $Uri -Headers $headers -UseBasicParsing -TimeoutSec 30 -WebSession $session
        
        Write-Host "SUCCESS: HTTP $($response.StatusCode)" -ForegroundColor Green
        Write-Host "Response Content:" -ForegroundColor White
        Write-Host $response.Content
        
        return $true
        
    } catch {
        Write-Error "FAILED: $($_.Exception.Message)"
        return $false
    }
}

# Test with httpbin.org to see our headers
Write-Host "=== Testing Enhanced HTTP Headers ===" -ForegroundColor Magenta
$success = Test-EnhancedWebRequest -Uri $TestUrl

if ($success) {
    Write-Host "`n=== Headers are working correctly! ===" -ForegroundColor Green
} else {
    Write-Host "`n=== Headers test failed ===" -ForegroundColor Red
}
