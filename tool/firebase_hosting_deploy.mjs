#!/usr/bin/env node
// Firebase Hosting deploy wrapper for CI.
// Treats Firebase's "current active version" response as an idempotent success.

import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const MAX_CAPTURED_OUTPUT = 1024 * 1024;

const inputArgs = process.argv.slice(2);
const env = { ...process.env };
let tempCredentialsDir = null;

const exitCode = await main();
process.exitCode = exitCode;

async function main() {
  try {
    if (!env.GOOGLE_APPLICATION_CREDENTIALS && env.FIREBASE_SERVICE_ACCOUNT) {
      tempCredentialsDir = mkdtempSync(join(tmpdir(), 'firebase-hosting-'));
      const credentialsPath = join(tempCredentialsDir, 'service-account.json');
      writeFileSync(credentialsPath, env.FIREBASE_SERVICE_ACCOUNT, { mode: 0o600 });
      env.GOOGLE_APPLICATION_CREDENTIALS = credentialsPath;
    }

    const firebaseArgs = buildFirebaseArgs(inputArgs, env);
    const result = await runFirebase(firebaseArgs, env);

    if (result.exitCode === 0) return 0;

    if (isCurrentActiveVersionError(result.output)) {
      const message =
        'Firebase Hosting version is already live; treating deploy as successful.';
      if (env.GITHUB_ACTIONS === 'true') {
        console.log(`::notice::${message}`);
      } else {
        console.log(message);
      }
      return 0;
    }

    return result.exitCode || 1;
  } finally {
    if (tempCredentialsDir) {
      rmSync(tempCredentialsDir, { recursive: true, force: true });
    }
  }
}

function buildFirebaseArgs(args, childEnv) {
  const deployArgs =
    args.length > 0 && !args[0].startsWith('-')
      ? [...args]
      : ['deploy', '--only', 'hosting', ...args];

  const hasTokenArg = deployArgs.some(
    (arg) => arg === '--token' || arg.startsWith('--token='),
  );
  if (!childEnv.GOOGLE_APPLICATION_CREDENTIALS && childEnv.FIREBASE_TOKEN && !hasTokenArg) {
    deployArgs.push('--token', childEnv.FIREBASE_TOKEN);
  }

  return deployArgs;
}

function isCurrentActiveVersionError(output) {
  return (
    /can't release to/i.test(output) &&
    /supplied version/i.test(output) &&
    /current active version/i.test(output) &&
    /channels\/live/i.test(output)
  );
}

async function runFirebase(firebaseArgs, childEnv) {
  const configuredBin = childEnv.FIREBASE_CLI_BIN;
  if (configuredBin) {
    return run(configuredBin, firebaseArgs, childEnv);
  }

  const firebaseBin = process.platform === 'win32' ? 'firebase.cmd' : 'firebase';
  const first = await run(firebaseBin, firebaseArgs, childEnv, { quietEnoent: true });
  if (!first.spawnError || first.spawnError.code !== 'ENOENT') return first;

  const npxBin = process.platform === 'win32' ? 'npx.cmd' : 'npx';
  console.warn('firebase CLI was not found on PATH; retrying with npx firebase-tools.');
  return run(npxBin, ['firebase-tools', ...firebaseArgs], childEnv);
}

function run(command, args, childEnv, options = {}) {
  return new Promise((resolve) => {
    let output = '';
    const append = (chunk, stream) => {
      stream.write(chunk);
      output += chunk.toString('utf8');
      if (output.length > MAX_CAPTURED_OUTPUT) {
        output = output.slice(-MAX_CAPTURED_OUTPUT);
      }
    };

    let child;
    try {
      child = spawn(command, args, {
        env: childEnv,
        shell: needsWindowsShell(command),
        windowsHide: true,
      });
    } catch (error) {
      if (!options.quietEnoent || error.code !== 'ENOENT') {
        console.error(error.message);
      }
      resolve({
        exitCode: 127,
        output,
        spawnError: error,
      });
      return;
    }

    child.stdout?.on('data', (chunk) => append(chunk, process.stdout));
    child.stderr?.on('data', (chunk) => append(chunk, process.stderr));
    child.on('error', (error) => {
      if (!options.quietEnoent || error.code !== 'ENOENT') {
        console.error(error.message);
      }
      resolve({
        exitCode: 127,
        output,
        spawnError: error,
      });
    });
    child.on('close', (code, signal) => {
      resolve({
        exitCode: signal ? 1 : code ?? 1,
        output,
        signal,
      });
    });
  });
}

function needsWindowsShell(command) {
  return process.platform === 'win32' && /\.(?:cmd|bat)$/i.test(command);
}
