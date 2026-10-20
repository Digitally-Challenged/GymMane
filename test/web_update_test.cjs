// Run: PLAYWRIGHT_MODULE=/path/to/playwright node --test test/web_update_test.cjs
// Uses a tiny catalogue fixture to exercise the actual worker/update lifecycle.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const playwright = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
const worker = fs.readFileSync(path.join(root, 'web/gymmane-worker.js'), 'utf8');
const updater = fs.readFileSync(path.join(root, 'web/app-update.js'), 'utf8');

for (const engine of ['chromium', 'webkit']) {
  for (const explicitRefresh of [true, false]) {
    test(`${engine}: ${explicitRefresh ? 'refresh link upgrades legacy shell' : 'update waits for Reload'}`, async () => {
      let version = 'old';
      let offline = false;
      const server = http.createServer((request, response) => {
        if (offline) return request.socket.destroy();
        response.setHeader('Cache-Control', 'no-store');
        const url = new URL(request.url, 'http://localhost');
        if (url.pathname === '/gymmane-worker.js') {
          response.setHeader('Content-Type', 'application/javascript');
          response.end(worker
            .replace("const CACHE = 'gymmane-trial';", `const CACHE = 'gymmane-trial-${version}';`)
            .replace('const PRECACHE = [];', "const PRECACHE = ['index.html','main.js','app-update.js'];"));
        } else if (url.pathname === '/app-update.js') {
          response.setHeader('Content-Type', 'application/javascript');
          response.end(updater);
        } else if (url.pathname === '/main.js') {
          response.setHeader('Content-Type', 'application/javascript');
          const art = version === 'old' ? [] : ['leg-extension', 'pendulum-squat'];
          response.end(`window.artwork=${JSON.stringify(art)};`);
        } else {
          response.setHeader('Content-Type', 'text/html');
          const bootstrap = explicitRefresh && version === 'old'
            ? "<script>navigator.serviceWorker.register('gymmane-worker.js')</script>"
            : '<script src="app-update.js" defer></script>';
          response.end(`<html><body><script src="main.js"></script>${bootstrap}</body></html>`);
        }
      });
      await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
      const base = `http://127.0.0.1:${server.address().port}`;
      const browser = await playwright[engine].launch();
      try {
        const context = await browser.newContext();
        const page = await context.newPage();
        await page.goto(base);
        await page.evaluate(() => navigator.serviceWorker.ready);
        await page.waitForFunction(() => Boolean(navigator.serviceWorker.controller));
        await page.evaluate(() => localStorage.setItem('flutter.gymmane_v1', 'workout-sentinel'));
        await page.reload();
        assert.deepEqual(await page.evaluate(() => window.artwork), []);
        version = 'new';
        if (explicitRefresh) await page.goto(`${base}/?update=1`);
        await page.evaluate(async () => {
          const registration = await navigator.serviceWorker.getRegistration();
          await registration.update();
        });
        if (!explicitRefresh) {
          await page.getByRole('button', { name: 'Reload', exact: true }).waitFor();
          assert.deepEqual(await page.evaluate(() => window.artwork), [],
            'Do not interrupt a running workout by reloading automatically');
          await page.getByRole('button', { name: 'Reload', exact: true }).click();
        }
        await page.waitForFunction(() => window.artwork?.length === 2, {}, { timeout: 5000 });
        assert.equal(await page.evaluate(() => localStorage.getItem('flutter.gymmane_v1')), 'workout-sentinel');
        offline = true;
        await page.reload();
        await page.waitForFunction(() => window.artwork?.length === 2);
        assert.equal(await page.evaluate(() => localStorage.getItem('flutter.gymmane_v1')), 'workout-sentinel');
      } finally {
        await browser.close();
        await new Promise(resolve => server.close(resolve));
      }
    });
  }
}
