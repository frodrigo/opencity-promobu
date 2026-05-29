#!/usr/bin/env node
import { resolve, basename } from 'node:path';
import { existsSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const scriptDir = resolve(fileURLToPath(new URL('.', import.meta.url)));

const rawArgs = process.argv.slice(2).filter((a) => a !== '--');
const arg = rawArgs.find((a) => !a.startsWith('-'));

if (!arg) {
  console.error('Usage: node viewer/view-model.mjs <path-to-model.glb|.gltf>');
  console.error('Example: npm run view -- ../out.glb');
  process.exit(1);
}

const absModel = resolve(arg);
if (!existsSync(absModel)) {
  console.error(`Model not found: ${absModel}`);
  process.exit(1);
}

const modelName = basename(absModel);
const modelUrl = `/__model__/${encodeURIComponent(modelName)}`;
console.log(`Serving model directly from source: ${absModel}`);

const viteBin = resolve(scriptDir, 'node_modules', 'vite', 'bin', 'vite.js');
if (!existsSync(viteBin)) {
  console.error('Missing local dependencies. Run:');
  console.error('  cd viewer && npm install');
  process.exit(1);
}

const vite = spawn(process.execPath, [viteBin, '--host', '--open', '/index.html'], {
  cwd: scriptDir,
  env: {
    ...process.env,
    PROMOBU_MODEL_PATH: absModel,
    PROMOBU_MODEL_URL: modelUrl
  },
  stdio: 'inherit',
  shell: false
});

vite.on('exit', (code) => process.exit(code ?? 0));
