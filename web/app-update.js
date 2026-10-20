'use strict';

// Keep updates explicit: reloading automatically could interrupt a live workout.
if ('serviceWorker' in navigator) {
  const hadController = Boolean(navigator.serviceWorker.controller);
  let shown = false;
  let registration;
  let checkedAt = 0;

  function showUpdate() {
    if (shown || !hadController) return;
    shown = true;
    const banner = document.createElement('div');
    banner.setAttribute('role', 'status');
    banner.style.cssText = 'position:fixed;z-index:2147483647;left:12px;right:12px;' +
      'top:max(12px,env(safe-area-inset-top));padding:14px 16px;background:#252525;' +
      'color:#fff;border:1px solid #666;border-radius:14px;font:15px system-ui;' +
      'display:flex;align-items:center;gap:16px;box-shadow:0 4px 20px #0008;';
    const label = document.createElement('span');
    label.textContent = 'GymMane update ready. Reload when you’re ready.';
    label.style.flex = '1';
    const button = document.createElement('button');
    button.textContent = 'Reload';
    button.style.cssText = 'min-height:44px;padding:8px 18px;border:0;border-radius:10px;' +
      'background:#dca27f;color:#171717;font:600 15px system-ui;cursor:pointer;';
    button.addEventListener('click', () => location.reload());
    banner.append(label, button);
    document.body.append(banner);
  }

  navigator.serviceWorker.addEventListener('controllerchange', showUpdate);

  async function checkUpdate() {
    if (!registration || document.visibilityState !== 'visible' || !navigator.onLine) return;
    if (Date.now() - checkedAt < 60000) return;
    checkedAt = Date.now();
    try {
      await registration.update();
    } catch (_) {
      // Continue using the cached application while offline or unreachable.
    }
  }

  navigator.serviceWorker.register('gymmane-worker.js', { updateViaCache: 'none' })
    .then(value => {
      registration = value;
      return checkUpdate();
    })
    .catch(error => console.warn('GymMane offline cache registration failed.', error));
  document.addEventListener('visibilitychange', checkUpdate);
  window.addEventListener('online', () => {
    checkedAt = 0;
    checkUpdate();
  });
}
