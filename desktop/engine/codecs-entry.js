// Browser-target codecs in an isolated Node-compatible runtime; no network requests.
import {unpackArchive} from '../../src/archive.mjs';
import UPNG from 'upng-js';
import initOxi,{optimise as oxi} from '@jsquash/oxipng/codec/pkg/squoosh_oxipng.js';
import pngDecode,{init as initPNG} from '@jsquash/png/decode.js';
import webpEncode,{init as initWebP} from '@jsquash/webp/encode.js';
import webpDecode,{init as initWebPDec} from '@jsquash/webp/decode.js';
import jpegEncode,{init as initJPEG} from '@jsquash/jpeg/encode.js';
import oxiWasm from '@jsquash/oxipng/codec/pkg/squoosh_oxipng_bg.wasm';
import pngWasm from '@jsquash/png/codec/pkg/squoosh_png_bg.wasm';
import webpWasm from '@jsquash/webp/codec/enc/webp_enc.wasm';
import webpDecWasm from '@jsquash/webp/codec/dec/webp_dec.wasm';
import jpegWasm from '@jsquash/jpeg/codec/enc/mozjpeg_enc.wasm';
import {features,equalPixels} from '../../src/core.mjs';
import {visualError,pngProfiles} from '../../src/png-quality.mjs';
const bytes=b=>Uint8Array.from(atob(b),c=>c.charCodeAt(0));
let ready;
async function init(){ready??=Promise.all([initOxi(bytes(oxiWasm)),initPNG(bytes(pngWasm)),initWebP({locateFile:p=>p,wasmBinary:bytes(webpWasm)}),initWebPDec({locateFile:p=>p,wasmBinary:bytes(webpDecWasm)}),initJPEG({locateFile:p=>p,wasmBinary:bytes(jpegWasm)})]);await ready;}
globalThis.DCCodecs={unpackArchive,async encode(input,format,mode){
 await init();if(mode==='small')mode='size';const image=await pngDecode(input.slice().buffer), f=features(image);let out,note='';
 if(format==='png'){
  out=oxi(input,3,false,false);
  if(!equalPixels(image,await pngDecode(out.slice().buffer)))throw Error('PNG 无损校验失败');
  const exact=oxi(new Uint8Array(UPNG.encode([image.data.slice().buffer],image.width,image.height,0)),3,false,false);
  if(exact.length<out.length&&equalPixels(image,await pngDecode(exact.slice().buffer)))out=exact;
  note='OxiPNG · 无损';
  if(mode!=='lossless')for(const colors of pngProfiles[mode].colors){const c=oxi(new Uint8Array(UPNG.encode([image.data.slice().buffer],image.width,image.height,colors)),3,false,true);if(c.length<out.length){const e=visualError(image,await pngDecode(c.slice().buffer));if(e.rms<=pngProfiles[mode].rms&&e.max<=pngProfiles[mode].max){out=c;note=`自适应减色 ≤${colors} 色`;}}}
 }else if(format==='webp'){
  const lossless=mode==='lossless';const q=mode==='quality'?90:mode==='balanced'?80:65;
  out=new Uint8Array(await webpEncode(image,{lossless:lossless?1:0,quality:lossless?90:q+(f.kind==='graphic'?5:0),method:6,exact:1,alpha_quality:100,near_lossless:100}));
  if(lossless&&!equalPixels(image,await webpDecode(out.slice().buffer)))throw Error('WebP 无损校验失败');
  note=lossless?'WebP 无损':'WebP 自适应质量';
 }else{
  const q=mode==='quality'?90:mode==='balanced'?80:65;
  out=new Uint8Array(await jpegEncode(image,{quality:q+(f.kind==='graphic'?5:0),progressive:true,optimize_coding:true,trellis_multipass:true,auto_subsample:false,chroma_subsample:f.kind==='graphic'?1:2}));note='MozJPEG 自适应质量';
 }
 return {bytes:out,note};
},async decodeWebP(input){await init();const i=await webpDecode(input.slice().buffer);return new Uint8Array(UPNG.encode([i.data.buffer],i.width,i.height,0));}};
