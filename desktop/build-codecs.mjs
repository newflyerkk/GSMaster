import {build} from 'esbuild';
await build({entryPoints:['desktop/engine/codecs-entry.js'],outfile:'desktop/engine/codecs.cjs',bundle:true,format:'iife',target:'es2022',platform:'browser',define:{process:'undefined'},loader:{'.wasm':'base64'},minify:true});
