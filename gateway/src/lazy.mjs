// Lazy loader for OPTIONAL protocol libraries. The gateway core has zero
// required dependencies; each protocol names exactly what it needs and how to
// install it, so a missing peer fails helpfully instead of at import time.
export async function lazyImport(pkg, { protocol }) {
  try {
    return await import(pkg);
  } catch (e) {
    if (e?.code === 'ERR_MODULE_NOT_FOUND' || /Cannot find (module|package)/.test(String(e?.message))) {
      throw new Error(
        `The "${protocol}" source needs the optional dependency "${pkg}".\n` +
        `  Install it next to the gateway:  npm install ${pkg}\n` +
        `  (Only the protocols you actually use need their library — the gateway core has none.)`,
      );
    }
    throw e;
  }
}
