const { chromium } = require('playwright');

(async () => {
  const url = process.argv[2];
  const output = process.argv[3] || 'screenshot.png';

  if (!url) {
    console.error('Usage: node screenshot.js <url> [output.png]');
    process.exit(1);
  }

  const browser = await chromium.launch({
    channel: 'msedge',
    headless: true,
  });

  const page = await browser.newPage();
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
  await page.screenshot({ path: output, fullPage: false });
  await browser.close();

  console.log(`Screenshot saved to: ${output}`);
})().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});
