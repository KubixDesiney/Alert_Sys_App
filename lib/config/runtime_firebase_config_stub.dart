// Non-web implementation: there is no `window.__SIAS_CONFIG__` off the browser,
// so runtime config is always absent and the app uses DefaultFirebaseOptions +
// dart-defines. Used on Android / iOS / desktop and in VM widget tests.
Map<Object?, Object?>? readRuntimeConfigRaw() => null;
