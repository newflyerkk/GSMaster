import {unzipSync,zipSync} from 'fflate';
function decodeName(raw,flags){
 try{return new TextDecoder('utf-8',{fatal:true}).decode(raw);}catch{}
 if(!(flags&2048)){try{return new TextDecoder('gb18030',{fatal:true}).decode(raw);}catch{}}
 throw Error('ZIP 文件名编码无法识别，请重新压缩为 UTF-8 ZIP。');
}
export function zipNames(input,rejectLinks=false){
 const view=new DataView(input.buffer,input.byteOffset,input.byteLength),map=new Map();let end=-1;
 for(let i=input.length-22;i>=Math.max(0,input.length-65557);i--)if(view.getUint32(i,true)===0x06054b50){end=i;break;}
 if(end<0)throw Error('ZIP 目录损坏。');let offset=view.getUint32(end+16,true),count=view.getUint16(end+10,true);
 if(count===65535||offset===0xffffffff)throw Error('暂不支持 ZIP64 压缩包。');
 for(let i=0;i<count;i++){
  if(offset+46>input.length||view.getUint32(offset,true)!==0x02014b50)throw Error('ZIP 目录损坏。');
  const flags=view.getUint16(offset+8,true),n=view.getUint16(offset+28,true),extra=view.getUint16(offset+30,true),comment=view.getUint16(offset+32,true),raw=input.subarray(offset+46,offset+46+n);
  if(rejectLinks&&((view.getUint32(offset+38,true)>>>16)&0xf000)===0xa000)throw Error('含符号链接的 ZIP 暂不支持原地重打包');
  if(flags&1)throw Error('暂不支持加密 ZIP。');
  const key=flags&2048?new TextDecoder().decode(raw):Array.from(raw,c=>String.fromCharCode(c)).join('');
  map.set(key,decodeName(raw,flags));offset+=46+n+extra+comment;
 }
 return map;
}
export function readZIPEntries(input,maxBytes=1024*1024*1024){
 const names=zipNames(input,true);let total=0;const raw=unzipSync(input,{filter:f=>{if((total+=f.originalSize)>maxBytes)throw Error('解压后内容超过容量限制。');return true;}}),result={};
 for(const [key,bytes] of Object.entries(raw)){const name=names.get(key)||key;if(name.startsWith('/')||/^[a-z]:/i.test(name)||name.replaceAll('\\','/').split('/').includes('..'))throw Error('压缩包包含不安全路径');if(Object.hasOwn(result,name))throw Error('ZIP 中包含重复名称。');result[name]=bytes;}
 return result;
}
export function rewriteZIP(entries){return zipSync(entries,{level:6});}
