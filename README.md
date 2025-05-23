# SitemapCrawler

A PowerShell script for crawling website sitemaps and downloading HTML content while maintaining the site's folder structure.

## Features

- Download entire websites based on their sitemap.xml
- Maintain original URL path structure in downloaded files
- Exclude inventory/vehicle pages by default
- Handle multiple sites with custom folder names
- Smart file handling for existing files
- Batch processing support

## Prerequisites

- PowerShell 5.1 or higher
- Internet connection
- Permission to create folders and files in the output directory

## Installation

1. Clone or download this repository
2. Ensure you have the required site configuration files in the `sites` folder

## Usage

### Basic Usage

```powershell
.\SitemapCrawler.ps1 -test
```

### Parameters

- `-test`: Use test configuration from test-site.txt
- `-all`: Include inventory and vehicle pages (disabled by default)
- `-OutputDirectory`: Specify custom output directory (default: "./downloaded_pages")
- `-DelayBetweenRequests`: Set delay between requests in milliseconds (default: 1)

### Site Configuration Files

The script uses configuration files in the `sites` folder:
- `test-site.txt`: Single site configuration for testing
- `stellantis.txt`: Full list of sites to process

Format: `https://www.example.com|FOLDER_NAME`

Example:
```
https://www.ddodge.com|DAR
```

### File Handling Options

When encountering existing files, the script provides four options:

1. Skip (S) - Skip the current file
2. Skip All (A) - Skip all existing files
3. Override (O) - Override the current file
4. Override All (L) - Override all existing files

## Output Structure

Files are saved maintaining the URL path structure:

```
downloaded_pages/
    SITE_FOLDER/
        about-us/
            index.html
        products/
            item1.html
            item2.html
        index.html
```

## Examples

1. Test with a single site:
```powershell
.\SitemapCrawler.ps1 -test
```

2. Process all sites including inventory pages:
```powershell
.\SitemapCrawler.ps1 -all
```

3. Custom output directory:
```powershell
.\SitemapCrawler.ps1 -OutputDirectory "C:\WebsiteBackups"
```

## Notes

- By default, pages containing "-vehicles" or "inventory" in their URLs are skipped
- Use the `-all` flag to include vehicle and inventory pages
- The script adds a 500ms delay between requests to avoid overwhelming servers
