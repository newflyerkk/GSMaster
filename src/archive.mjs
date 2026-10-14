import {unzipSync} from 'fflate';
import {ArchiveReader,libarchiveWasm} from 'libarchive-wasm';
import wasm from 'libarchive-wasm/dist/libarchive.wasm';
let ready;
export function safeArchivePath(raw){const name=raw.replaceAll('\\','/');if(!name||name.startsWith('/')||/^[a-z]:/i.test(name)||name.includes('\0')||name.split('/').some(p=>p==='..'))throw Error('压缩包包含不安全路径');return name.split('/').filter(p=>p&&p!=='.').join('/');}
export async function unpackArchive(input,accept,maxBytes=128*1024*1024){
 if(input.length>maxBytes)throw Error('压缩包过大，请分批导入。');
 if(input[0]===0x50&&input[1]===0x4b){
  let total=0,count=0;const entries=unzipSync(input,{filter:entry=>{if(++count>10000)throw Error('压缩包文件数量过多');const name=safeArchivePath(entry.name);if(name.split('/').some(p=>p.startsWith('.')||p==='__MACOSX')||!accept(name)||entry.name.endsWith('/'))return false;if((total+=entry.originalSize)>maxBytes)throw Error('解压后素材过大，请分批导入。');return true;}});
  return Object.entries(entries).map(([path,bytes])=>({path:safeArchivePath(path),name:safeArchivePath(path).split('/').pop(),bytes}));
 }
 ready??=libarchiveWasm({wasmBinary:Uint8Array.from(atob(wasm),c=>c.charCodeAt(0))});
 const reader=new ArchiveReader(await ready,new Int8Array(input));const files=[];let total=0,count=0;
 try{for(const entry of reader.entries()){
  if(++count>10000)throw Error('压缩包文件数量超过 10000。');
  const pathname=safeArchivePath(entry.getPathname());
  if(entry.isEncrypted())throw Error('暂不支持加密压缩包，请解密后导入。');
  if(entry.getFiletype()!=='File'||entry.getSymlinkTarget()||entry.getHardlinkTarget()||pathname.split('/').some(p=>p.startsWith('.')||p==='__MACOSX')||!accept(pathname))continue;
  const size=entry.getSize();if(!Number.isSafeInteger(size)||size<0||(total+=size)>maxBytes)throw Error('解压后素材过大，请分批导入。');
  const data=entry.readData();if(!data||data.length!==size)throw Error('压缩包数据不完整。');
  files.push({path:pathname,name:pathname.split('/').pop(),bytes:new Uint8Array(data)});
 }return files;}finally{reader.free();}
}
