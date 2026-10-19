{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load();
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('gymmane-worker.js').catch(console.error);
}
