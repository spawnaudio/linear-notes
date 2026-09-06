import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './tests',
  workers: 1,
  use: { headless: true, viewport: { width: 950, height: 900 }, launchOptions: { executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' } },
  reporter: 'list',
});
