import { defineConfig, mergeConfig } from 'vite';
import upstreamConfig from './vite.upstream.config.js';

// Extend the pinned upstream Vite configuration without modifying it in place.
export default defineConfig((env) => {
	const base = typeof upstreamConfig === 'function' ? upstreamConfig(env) : upstreamConfig;
	return mergeConfig(base, {
		server: {
			allowedHosts: true,
			proxy: {
				'/remote/': {
					target: 'http://remote:8080',
					changeOrigin: true,
				},
			},
		},
	});
});
