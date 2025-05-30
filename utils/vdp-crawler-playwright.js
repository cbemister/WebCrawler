#!/usr/bin/env node

/**
 * VDP Crawler using Playwright for advanced anti-bot evasion
 * Works with portable Node.js and browsers
 */

const fs = require('fs').promises;
const path = require('path');

// Check if playwright is available, if not provide installation instructions
let playwright;
try {
 playwright = require('playwright');
} catch (error) {
 console.error('❌ Playwright not found. Please install it:');
 console.error('npm install playwright');
 console.error('npx playwright install chromium');
 process.exit(1);
}

class VDPCrawler {
 constructor(options = {}) {
  this.options = {
   headless: options.headless !== false, // Default to headless
   delaySeconds: options.delaySeconds || 3,
   maxRetries: options.maxRetries || 3,
   verbose: options.verbose || false,
   browserPath: options.browserPath || null, // Path to portable browser
   ...options
  };
  this.browser = null;
  this.context = null;
 }

 async initialize() {
  try {
   console.log('🚀 Initializing Playwright browser...');

   const browserOptions = {
    headless: this.options.headless,
    args: [
     '--no-sandbox',
     '--disable-blink-features=AutomationControlled',
     '--disable-extensions',
     '--disable-plugins',
     '--disable-images', // Faster loading
     '--disable-javascript', // We don't need JS for sitemaps
     '--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    ]
   };

   // Use portable browser if specified
   if (this.options.browserPath) {
    browserOptions.executablePath = this.options.browserPath;
   }

   this.browser = await playwright.chromium.launch(browserOptions);

   // Create context with realistic settings
   this.context = await this.browser.newContext({
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    viewport: {
     width: 1920,
     height: 1080
    },
    locale: 'en-US',
    timezoneId: 'America/New_York',
    extraHTTPHeaders: {
     'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
     'Accept-Language': 'en-US,en;q=0.5',
     'Accept-Encoding': 'gzip, deflate, br',
     'DNT': '1',
     'Connection': 'keep-alive',
     'Upgrade-Insecure-Requests': '1',
    }
   });

   console.log('✅ Browser initialized successfully');
   return true;
  } catch (error) {
   console.error('❌ Failed to initialize browser:', error.message);
   return false;
  }
 }

 async randomDelay(min = 1, max = 3) {
  const delay = Math.random() * (max - min) + min;
  await new Promise(resolve => setTimeout(resolve, delay * 1000));
 }

 async getInventorySitemap(baseUrl) {
  const page = await this.context.newPage();

  try {
   console.log(`🌐 Processing: ${baseUrl}`);

   // First visit main page to establish session
   console.log('📄 Visiting main page...');
   await page.goto(baseUrl, {
    waitUntil: 'domcontentloaded',
    timeout: 30000
   });
   await this.randomDelay(2, 4); // Human-like delay

   // Check if main page is accessible
   const title = await page.title();
   if (title.includes('403') || title.includes('Forbidden')) {
    throw new Error('Main page blocked with 403 error');
   }

   console.log(`✅ Main page loaded: ${title}`);

   // Look for sitemap references in the main page
   const mainPageContent = await page.content();
   const sitemapMatches = mainPageContent.match(/href=['"](.*?sitemap.*?\.xml)['"]/gi);
   if (sitemapMatches && this.options.verbose) {
    console.log(`🔍 Found sitemap references in main page: ${sitemapMatches.slice(0, 3).join(', ')}`);
   }

   // Check robots.txt for sitemap references
   try {
    const robotsResponse = await page.goto(`${baseUrl.replace(/\/$/, '')}/robots.txt`, {
     waitUntil: 'domcontentloaded',
     timeout: 15000
    });
    if (robotsResponse.status() === 200) {
     const robotsContent = await page.content();
     const robotsSitemaps = robotsContent.match(/Sitemap:\s*(.*)/gi);
     if (robotsSitemaps && this.options.verbose) {
      console.log(`🤖 Found sitemaps in robots.txt: ${robotsSitemaps.join(', ')}`);
     }
    }
   } catch (error) {
    if (this.options.verbose) {
     console.log(`⚠️  Could not access robots.txt: ${error.message}`);
    }
   }

   // Try inventory sitemap
   const inventorySitemapUrl = `${baseUrl.replace(/\/$/, '')}/dealer-inspire-inventory/inventory_sitemap.xml`;
   console.log(`🗺️  Checking inventory sitemap: ${inventorySitemapUrl}`);

   const response = await page.goto(inventorySitemapUrl, {
    waitUntil: 'domcontentloaded',
    timeout: 30000
   });

   if (this.options.verbose) {
    console.log(`📊 Sitemap response status: ${response.status()}`);
   }

   if (response.status() === 200) {
    const content = await page.content();
    if (this.options.verbose) {
     console.log(`📄 Content preview: ${content.substring(0, 200)}...`);
    }

    if (content.includes('<urlset') || content.includes('<sitemapindex')) {
     console.log('✅ Successfully accessed inventory sitemap');
     return {
      url: inventorySitemapUrl,
      content: content
     };
    } else {
     console.log('⚠️  Sitemap URL accessible but no XML sitemap content found');
    }
   } else {
    console.log(`❌ Sitemap returned status: ${response.status()}`);
   }

   // Try alternative sitemap paths
   const alternativePaths = ['/sitemap.xml', '/sitemaps/inventory.xml', '/inventory-sitemap.xml', '/sitemap_index.xml'];

   for (const path of alternativePaths) {
    const altUrl = `${baseUrl.replace(/\/$/, '')}${path}`;
    console.log(`🔍 Trying alternative sitemap: ${altUrl}`);

    try {
     const altResponse = await page.goto(altUrl, {
      waitUntil: 'domcontentloaded',
      timeout: 15000
     });

     if (altResponse.status() === 200) {
      const content = await page.content();
      if ((content.includes('<urlset') || content.includes('<sitemapindex')) &&
       (content.includes('inventory') || content.includes('vehicle') || content.includes('vdp'))) {
       console.log('✅ Found alternative sitemap with inventory content');
       return {
        url: altUrl,
        content: content
       };
      }
     }
    } catch (error) {
     if (this.options.verbose) {
      console.log(`⚠️  Alternative path ${path} failed: ${error.message}`);
     }
    }
   }

   throw new Error('No accessible sitemap found');

  } catch (error) {
   console.warn(`⚠️  Browser automation failed for ${baseUrl}: ${error.message}`);
   return null;
  } finally {
   await page.close();
  }
 }

 parseFirstVDPFromSitemap(sitemapContent) {
  try {
   // Simple XML parsing to extract first URL
   const urlMatches = sitemapContent.match(/<loc>(.*?)<\/loc>/g);
   if (urlMatches && urlMatches.length > 0) {
    const firstUrl = urlMatches[0].replace(/<\/?loc>/g, '');
    return firstUrl;
   }
  } catch (error) {
   console.warn(`⚠️  Failed to parse sitemap XML: ${error.message}`);
  }
  return null;
 }

 async processSiteList(inputFile, outputFile) {
  console.log('🎯 Browser-based VDP Crawler Starting...');
  console.log(`📁 Input: ${inputFile}`);
  console.log(`📁 Output: ${outputFile}`);
  console.log(`👁️  Headless mode: ${this.options.headless}`);
  console.log(`⏱️  Delay between sites: ${this.options.delaySeconds}s`);

  if (!await this.initialize()) {
   console.error('❌ Cannot proceed without browser initialization');
   return;
  }

  try {
   const fileContent = await fs.readFile(inputFile, 'utf8');
   const sites = fileContent.split('\n')
    .filter(line => line.trim() && line.match(/^https?:\/\//))
    .map(line => {
     const parts = line.trim().split('|');
     return {
      url: parts[0],
      folder: parts[1] || 'UNK'
     };
    });

   const results = [];
   let successfulSites = 0;

   console.log(`\n🔄 Processing ${sites.length} sites with browser automation...\n`);

   for (const site of sites) {
    console.log('='.repeat(60));
    console.log(`🎯 Processing: ${site.url}`);
    console.log('='.repeat(60));

    try {
     const sitemapResult = await this.getInventorySitemap(site.url);

     if (sitemapResult) {
      console.log(`✅ Found sitemap: ${sitemapResult.url}`);

      const vdpUrl = this.parseFirstVDPFromSitemap(sitemapResult.content);
      if (vdpUrl) {
       console.log(`🎉 SUCCESS: Found VDP URL: ${vdpUrl}`);
       results.push(`${vdpUrl}|${site.folder}`);
       successfulSites++;
      } else {
       console.warn('⚠️  No VDP URLs found in sitemap');
      }
     } else {
      console.warn(`⚠️  Could not access any sitemap for ${site.url}`);
     }
    } catch (error) {
     console.error(`❌ Error processing ${site.url}: ${error.message}`);
    }

    // Delay between sites
    if (this.options.delaySeconds > 0) {
     console.log(`⏳ Waiting ${this.options.delaySeconds} seconds before next site...`);
     await new Promise(resolve => setTimeout(resolve, this.options.delaySeconds * 1000));
    }
   }

   // Save results
   console.log('\n' + '='.repeat(60));
   console.log('🏁 PROCESSING COMPLETE');
   console.log('='.repeat(60));

   if (results.length > 0) {
    await fs.writeFile(outputFile, results.join('\n'), 'utf8');
    console.log(`🎉 SUCCESS: Saved ${results.length} VDP URLs to ${outputFile}`);
   } else {
    console.warn('⚠️  No VDP URLs found from any sites');
   }

   console.log(`📊 Summary: ${successfulSites}/${sites.length} sites processed successfully`);

  } finally {
   await this.cleanup();
  }
 }

 async cleanup() {
  if (this.browser) {
   console.log('🧹 Closing browser...');
   await this.browser.close();
  }
 }
}

// CLI interface
async function main() {
 const args = process.argv.slice(2);
 const delayArg = args.find(arg => arg.startsWith('--delay='));
 const delayValue = delayArg ? delayArg.split('=')[1] : '3';

 const options = {
  test: args.includes('--test'),
  headless: !args.includes('--no-headless'),
  verbose: args.includes('--verbose'),
  delaySeconds: parseInt(delayValue) || 3
 };

 const scriptDir = path.dirname(__dirname);
 const inputDir = path.join(scriptDir, 'input');
 const outputDir = path.join(scriptDir, 'output');

 // Ensure output directory exists
 try {
  await fs.mkdir(outputDir, {
   recursive: true
  });
 } catch (error) {
  // Directory might already exist
 }

 const inputFile = options.test ?
  path.join(inputDir, 'test-site.txt') :
  path.join(inputDir, 'stellantis.txt');

 const outputFile = options.test ?
  path.join(outputDir, 'test-vdp-playwright.txt') :
  path.join(outputDir, 'stellantis-vdp-playwright.txt');

 const crawler = new VDPCrawler(options);
 await crawler.processSiteList(inputFile, outputFile);
}

// Run if called directly
if (require.main === module) {
 main().catch(console.error);
}

module.exports = VDPCrawler;