{{flutter_js}}
{{flutter_build_config}}

// Run the app inside #app (see index.html) so its size follows the
// visible screen when the iPhone keyboard opens.
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({
      hostElement: document.querySelector('#app'),
    });
    await appRunner.runApp();
  },
});
