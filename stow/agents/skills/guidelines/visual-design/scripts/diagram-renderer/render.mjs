import { readFile, writeFile, mkdtemp, rm, access } from 'node:fs/promises';
import { constants } from 'node:fs';
import { resolve, dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { spawn } from 'node:child_process';
import { chromium } from 'playwright';
import { createServer } from 'vite';

const root = dirname(fileURLToPath(import.meta.url));
const [source, destination, scaleArg = '2'] = process.argv.slice(2);
if (!source || !destination || !['.mmd', '.excalidraw'].includes(extname(source)) || extname(destination) !== '.png') {
  console.error('Usage: node render.mjs source.mmd|source.excalidraw output.png [scale=2]');
  process.exit(1);
}
const scale = Number(scaleArg);
if (!Number.isFinite(scale) || scale <= 0 || scale > 8) throw new Error('Scale must be greater than 0 and at most 8');
const input = resolve(source), output = resolve(destination);
await access(chromium.executablePath(), constants.X_OK);
const temp = await mkdtemp(join(tmpdir(), 'diagram-render-'));
let server, browser;
try {
  if (extname(input) === '.mmd') {
    const config = join(temp, 'puppeteer.json');
    await writeFile(config, JSON.stringify({ executablePath: chromium.executablePath() }));
    await new Promise((done, reject) => {
      const child = spawn(process.execPath, [join(root, 'node_modules/@mermaid-js/mermaid-cli/src/cli.js'),
        '-i', input, '-o', output, '-s', String(scale), '-b', 'white', '-p', config], { stdio: 'inherit' });
      child.on('error', reject);
      child.on('exit', code => code === 0 ? done() : reject(new Error(`Mermaid exited ${code}`)));
    });
  } else {
    const scene = JSON.parse(await readFile(input, 'utf8'));
    if (scene.type !== 'excalidraw' || !Array.isArray(scene.elements)) throw new Error('Expected standard .excalidraw JSON, not an Obsidian Markdown wrapper');
    // Serve package assets locally, including fonts, rather than fetching them from a CDN.
    server = await createServer({ root, configFile: false, server: { host: '127.0.0.1', port: 0 }, logLevel: 'error' });
    await server.listen();
    const url = server.resolvedUrls.local[0];
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.route('**/*', route => {
      const u = route.request().url();
      return u.startsWith(url) || u.startsWith('data:') || u.startsWith('blob:') ? route.continue() : route.abort();
    });
    await page.addInitScript(() => { window.EXCALIDRAW_ASSET_PATH = '/node_modules/@excalidraw/excalidraw/dist/prod/'; });
    await page.goto(url);
    await page.waitForFunction(() => typeof window.renderDiagram === 'function');
    const png = await page.evaluate(({ scene, scale }) => window.renderDiagram(scene, scale), { scene, scale });
    await writeFile(output, Buffer.from(png, 'base64'));
  }
  console.log(output);
} finally {
  await browser?.close();
  await server?.close();
  await rm(temp, { recursive: true, force: true });
}
