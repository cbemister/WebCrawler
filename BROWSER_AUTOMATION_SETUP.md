# Browser Automation Setup Guide

This guide shows how to set up browser automation for the VDP crawler using both PowerShell/Selenium and Node.js/Playwright approaches.

## 🚀 Quick Start Options

### Option 1: Node.js + Playwright (Recommended)

**Why Playwright?**
- Better anti-bot evasion capabilities
- More reliable with modern websites
- Easier setup with portable versions
- Built-in stealth features

#### Setup Steps:

1. **Install Node.js** (if not already installed)
   ```bash
   # Download portable Node.js from: https://nodejs.org/
   # Or use existing Node.js installation
   ```

2. **Install dependencies**
   ```bash
   npm install
   npm run install-browsers
   ```

3. **Run the crawler**
   ```bash
   # Test with single site
   npm test

   # Run full crawl (headless)
   npm run crawl

   # Run with visible browser (for debugging)
   npm run crawl-visible

   # Custom options
   node utils/vdp-crawler-playwright.js --test --verbose --delay=5
   ```

### Option 2: PowerShell + Selenium WebDriver

#### Setup Steps:

1. **Download ChromeDriver**
   ```powershell
   # Create drivers directory
   New-Item -ItemType Directory -Path ".\drivers" -Force

   # Download ChromeDriver from: https://chromedriver.chromium.org/
   # Place chromedriver.exe in .\drivers\ folder
   ```

2. **Install Selenium PowerShell Module**
   ```powershell
   Install-Module -Name Selenium -Force -Scope CurrentUser
   ```

3. **Run the crawler**
   ```powershell
   # Test with single site
   .\utils\Get-FirstVDP-Selenium.ps1 -test -Verbose

   # Run full crawl
   .\utils\Get-FirstVDP-Selenium.ps1

   # Use portable Chrome
   .\utils\Get-FirstVDP-Selenium.ps1 -ChromeBinaryPath "C:\Path\To\Portable\Chrome\chrome.exe"

   # Run with visible browser
   .\utils\Get-FirstVDP-Selenium.ps1 -Headless:$false
   ```

## 📁 Portable Setup

### For Portable Node.js:

1. **Download portable Node.js**
   - Get from: https://nodejs.org/en/download/
   - Extract to your project folder

2. **Set up environment**
   ```bash
   # Windows
   set PATH=%CD%\node-portable;%PATH%
   
   # Then run normal npm commands
   npm install
   npm run setup
   ```

### For Portable Chrome/Chromium:

1. **Download portable Chrome**
   - Chromium: https://download-chromium.appspot.com/
   - Chrome Portable: https://portableapps.com/apps/internet/google_chrome_portable

2. **Use with scripts**
   ```powershell
   # PowerShell
   .\utils\Get-FirstVDP-Selenium.ps1 -ChromeBinaryPath ".\chrome-portable\chrome.exe"
   ```
   
   ```bash
   # Node.js - modify the script to set browserPath option
   ```

## 🛠️ Configuration Options

### PowerShell Selenium Options:
```powershell
-test              # Use test site instead of full list
-DelaySeconds 5    # Delay between requests (default: 3)
-ChromeDriverPath  # Path to chromedriver.exe
-ChromeBinaryPath  # Path to portable Chrome
-Headless:$false   # Show browser window
-Verbose           # Detailed logging
```

### Node.js Playwright Options:
```bash
--test             # Use test site
--verbose          # Detailed logging
--no-headless      # Show browser window
--delay=5          # Delay between sites in seconds
```

## 🔧 Troubleshooting

### Common Issues:

1. **ChromeDriver version mismatch**
   ```
   Solution: Download ChromeDriver version matching your Chrome version
   Check Chrome version: chrome://version/
   Download from: https://chromedriver.chromium.org/
   ```

2. **Selenium module not found**
   ```powershell
   Install-Module -Name Selenium -Force -Scope CurrentUser
   ```

3. **Playwright browser not found**
   ```bash
   npx playwright install chromium
   ```

4. **Still getting 403 errors**
   - Try running with visible browser (`--no-headless`)
   - Increase delays between requests
   - Check if manual browser access works
   - Some sites may require additional techniques

### Advanced Anti-Detection:

1. **Use residential proxies** (if available)
2. **Rotate user agents** (already implemented)
3. **Add random mouse movements** (for visible browser mode)
4. **Use different browser profiles**

## 📊 Expected Results

### Success Indicators:
- ✅ Browser launches successfully
- ✅ Main page loads without 403 errors
- ✅ Sitemap URLs are accessible
- ✅ VDP URLs are extracted and saved

### If Still Blocked:
- The sites may use advanced protection (Cloudflare, etc.)
- Consider alternative data sources
- Manual verification may be needed
- Contact site administrators for API access

## 🎯 Usage Examples

### Test Single Site:
```bash
# Node.js
npm test

# PowerShell
.\utils\Get-FirstVDP-Selenium.ps1 -test -Verbose
```

### Full Production Run:
```bash
# Node.js (recommended)
npm run crawl

# PowerShell
.\utils\Get-FirstVDP-Selenium.ps1
```

### Debug Mode (Visible Browser):
```bash
# Node.js
npm run crawl-visible

# PowerShell
.\utils\Get-FirstVDP-Selenium.ps1 -Headless:$false
```

Both approaches should be significantly more effective than the HTTP-only method for bypassing anti-bot protection!
