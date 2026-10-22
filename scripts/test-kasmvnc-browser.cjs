const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({
    executablePath: '/usr/bin/google-chrome',
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  try {
    const contexts = [];
    for (let viewer = 0; viewer < 2; viewer++) {
      const context = await browser.newContext({
        ignoreHTTPSErrors: true,
        httpCredentials: { username: 'kasm_user', password: process.env.VNC_PW },
      });
      contexts.push(context);
      const page = await context.newPage();
      let socketOpened = false;
      page.on('websocket', () => { socketOpened = true; });
      await page.goto('https://127.0.0.1:6901/vnc.html?autoconnect=1&resize=remote&shared=1&video_rendering_mode=canvas2d', { timeout: 90000 });
      await page.waitForFunction(() => {
        const canvas = Array.from(document.querySelectorAll('#noVNC_container canvas')).find(c => c.width >= 100 && c.height >= 100 && c.getContext('2d'));
        if (!canvas || canvas.width < 100 || canvas.height < 100) return false;
        const data = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
        const colors = new Set();
        for (let i = 0; i < data.length; i += 400) {
          colors.add(data[i] + ',' + data[i + 1] + ',' + data[i + 2]);
          if (colors.size > 8) return true;
        }
        return false;
      }, undefined, { timeout: 90000 });
      if (!socketOpened) throw new Error('No WebSocket observed');
      await page.screenshot({ path: '/tmp/kasm-viewer-' + viewer + '.png' });
      console.log('PASS: viewer ' + (viewer + 1) + ' authenticated, WebSocket opened and desktop pixels received');
    }
    await Promise.all(contexts.map(context => context.close()));
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
