// 앱 아이콘 다시 만들기: Resources/icon/AppIcon.svg → AppIcon.iconset(PNG) → Resources/AppIcon.icns
//   NODE_PATH=$(npm root -g) node app/scripts/make-icon.mjs   (playwright 필요 — 전역 설치 또는 npm i playwright)
// ICNS 는 macOS 면 iconutil, 아니면 python3 Pillow 로 묶는다.
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, rmSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// require 로 불러야 전역 설치(NODE_PATH)도 찾는다
const { chromium } = createRequire(import.meta.url)('playwright');

const appDir = join(dirname(fileURLToPath(import.meta.url)), '..');
const iconDir = join(appDir, 'Resources', 'icon');
const svg = readFileSync(join(iconDir, 'AppIcon.svg'), 'utf8');
const set = join(iconDir, 'AppIcon.iconset');
rmSync(set, { recursive: true, force: true });
mkdirSync(set, { recursive: true });

// iconutil 이 요구하는 이름 — 크기마다 SVG 에서 따로 그려 작은 크기도 또렷하게
const targets = [];
for (const base of [16, 32, 128, 256, 512]) {
  targets.push([`icon_${base}x${base}.png`, base]);
  targets.push([`icon_${base}x${base}@2x.png`, base * 2]);
}
const browser = await chromium.launch();
for (const [name, px] of targets) {
  const page = await browser.newPage({ viewport: { width: px, height: px }, deviceScaleFactor: 1 });
  await page.setContent(`<html><body style="margin:0;background:transparent">${svg.replace('width="1024" height="1024"', `width="${px}" height="${px}"`)}</body></html>`);
  await page.locator('svg').screenshot({ path: join(set, name), omitBackground: true });
  await page.close();
}
await browser.close();

const icns = join(appDir, 'Resources', 'AppIcon.icns');
if (process.platform === 'darwin') {
  execFileSync('iconutil', ['-c', 'icns', set, '-o', icns], { stdio: 'inherit' });
} else {
  execFileSync('python3', ['-c', `
import sys
from PIL import Image
d = sys.argv[1]
sizes = [16, 32, 64, 128, 256, 512, 1024]
name = {16:'icon_16x16.png',32:'icon_32x32.png',64:'icon_32x32@2x.png',128:'icon_128x128.png',256:'icon_256x256.png',512:'icon_512x512.png',1024:'icon_512x512@2x.png'}
imgs = [Image.open(d + '/' + name[s]).convert('RGBA') for s in sizes]
imgs[-1].save(sys.argv[2], append_images=imgs[:-1])
`, set, icns], { stdio: 'inherit' });
}
execFileSync('cp', [join(set, 'icon_512x512@2x.png'), join(iconDir, 'AppIcon-1024.png')]);
rmSync(set, { recursive: true, force: true });
console.log('✓', icns, existsSync(icns) ? '' : '(없음!)');
