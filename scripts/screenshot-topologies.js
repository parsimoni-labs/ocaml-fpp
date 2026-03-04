// Screenshot topologies from fprime-visual using Playwright.
//
// Usage: node scripts/screenshot-topologies.js <port> <folder> <outdir> [topology ...]
//
// <folder> is the fprime-visual folder name (e.g. "images").
// When no topology names are given, screenshots all available topologies.

const { chromium } = require("playwright");

const port = process.argv[2];
const folder = process.argv[3];
const outdir = process.argv[4];
const requestedTopos = process.argv.slice(5);

if (!port || !folder || !outdir) {
  console.error(
    "Usage: node scripts/screenshot-topologies.js <port> <folder> <outdir> [topology ...]"
  );
  process.exit(1);
}

const url = `http://localhost:${port}/`;

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({
    viewport: { width: 1920, height: 1080 },
  });
  await page.goto(url, { waitUntil: "networkidle" });

  // Wait for the folder dropdown to be populated.
  await page.waitForFunction(() => {
    const sel = document.getElementById("select-folder");
    return sel && sel.options.length > 0;
  });

  // Select the target folder.
  await page.evaluate((f) => {
    const sel = document.getElementById("select-folder");
    sel.value = f;
    sel.dispatchEvent(new Event("change"));
  }, folder);

  // Wait for the file dropdown to be populated after folder selection.
  await page.waitForFunction(
    () => {
      const sel = document.getElementById("select-file");
      return sel && sel.options.length > 0;
    },
    { timeout: 10000 }
  );

  // Small delay for initial render to complete.
  await page.waitForTimeout(1000);

  // Get list of available topology files.
  const allFiles = await page.evaluate(() => {
    const sel = document.getElementById("select-file");
    return [...sel.options].map((o) => o.value);
  });

  const topos =
    requestedTopos.length > 0
      ? requestedTopos.map((t) => (t.endsWith(".json") ? t : t + ".json"))
      : allFiles;

  for (const file of topos) {
    if (!allFiles.includes(file)) {
      console.error(`  WARNING: ${file} not found, skipping`);
      continue;
    }
    const name = file.replace(/\.json$/, "");
    console.log(`  ${name}`);

    // Select the topology in the dropdown and trigger a change event.
    await page.evaluate((f) => {
      const sel = document.getElementById("select-file");
      sel.value = f;
      sel.dispatchEvent(new Event("change"));
    }, file);

    // Wait for the canvas to be rendered (non-zero pixel data).
    await page.waitForFunction(
      () => {
        const canvas = document.getElementById("fprime-graph");
        if (!canvas || canvas.width === 0 || canvas.height === 0) return false;
        const ctx = canvas.getContext("2d");
        const data = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
        for (let i = 3; i < data.length; i += 4) {
          if (data[i] !== 0) return true;
        }
        return false;
      },
      { timeout: 15000 }
    );

    // Extra delay for ELK layout to settle.
    await page.waitForTimeout(500);

    // Screenshot the canvas element.
    const canvas = page.locator("#fprime-graph");
    await canvas.screenshot({ path: `${outdir}/${name}.png` });
  }

  await browser.close();
})();
