import { createReadStream, existsSync } from 'node:fs';
import { dirname, extname, resolve, sep } from 'node:path';
import { defineConfig } from 'vite';

const modelPath = process.env.PROMOBU_MODEL_PATH;
const modelUrl = process.env.PROMOBU_MODEL_URL;

const contentTypeFor = (path: string): string => {
	const ext = extname(path).toLowerCase();
	if (ext === '.glb') {
		return 'model/gltf-binary';
	}
	if (ext === '.gltf') {
		return 'model/gltf+json';
	}
	return 'application/octet-stream';
};

export default defineConfig({
	define: {
		__PROMOBU_MODEL_URL__: JSON.stringify(modelUrl ?? null)
	},
	plugins: [
		{
			name: 'runtime-model-source',
			configureServer(server: any) {
				if (!modelPath || !modelUrl) {
					return;
				}

				const absModel = resolve(modelPath);
				const modelDir = dirname(absModel);
				const routeBase = '/__model__/';
				const routeBaseLen = routeBase.length;

				server.watcher.add(absModel);
				server.watcher.on('change', (changedPath: string) => {
					if (resolve(changedPath) !== absModel) {
						return;
					}

					server.ws.send({
						type: 'custom',
						event: 'promobu:model-changed',
						data: { path: absModel, ts: Date.now() }
					});
				});

				server.middlewares.use((req: any, res: any, next: any) => {
					const reqUrl = (req.url ?? '').split('?')[0];
					if (!reqUrl.startsWith(routeBase)) {
						next();
						return;
					}

					const relPath = decodeURIComponent(reqUrl.slice(routeBaseLen));
					const requested = resolve(modelDir, relPath);
					const safePrefix = modelDir.endsWith(sep) ? modelDir : `${modelDir}${sep}`;
					if (requested !== modelDir && !requested.startsWith(safePrefix)) {
						res.statusCode = 403;
						res.end('Forbidden');
						return;
					}

					if (!existsSync(requested)) {
						res.statusCode = 404;
						res.end('Not found');
						return;
					}

					res.setHeader('Content-Type', contentTypeFor(requested));
					createReadStream(requested)
						.on('error', () => {
							res.statusCode = 500;
							res.end('Read error');
						})
						.pipe(res);
				});
			}
		}
	]
});
