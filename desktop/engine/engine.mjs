import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import {spawn} from 'node:child_process';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const require=createRequire(import.meta.url),here=path.dirname(fileURLToPath(import.meta.url));
globalThis.self=globalThis;globalThis.ImageData=class{constructor(data,width,height){Object.assign(this,{data,width,height});}};
const imageExt=new Set(['png','jpg','jpeg','webp','heic','heif','tif','tiff','gif','bmp']);
const videoExt=new Set(['mp4','mov','mkv','webm','m4v','avi','mpeg','mpg','ts','mts','m2ts']);
const ext=p=>path.extname(p).slice(1).toLowerCase();
export const kind=p=>imageExt.has(ext(p))?'image':videoExt.has(ext(p))?'video':null;
let cancelled=false,active=new Set();
process.on('SIGTERM',()=>{cancelled=true;for(const p of active)p.kill('SIGTERM');});
function check(){if(cancelled)throw Error('已取消');}
function emit(v){process.stdout.write(JSON.stringify(v)+'\n');}
function binary(name){return process.env.DC_TOOLS?path.join(process.env.DC_TOOLS,name):path.resolve(here,'../tools',name);}
function helper(){return process.env.DC_HELPER||path.resolve(here,'../../MacOS/GSMaster');}
export async function run(exe,args){
 check();return new Promise((resolve,reject)=>{
  const p=spawn(exe,args,{stdio:['ignore','pipe','pipe'],env:{...process.env,AV_LOG_FORCE_NOCOLOR:'1'}});active.add(p);let out='',err='';
  p.stdout.on('data',b=>{out+=b;if(out.length>16*1024*1024){p.kill();reject(Error('输出数据超限'));}});
  p.stderr.on('data',b=>{err=(err+b).slice(-8000);});
  p.on('error',e=>{active.delete(p);reject(e);});p.on('close',code=>{active.delete(p);code===0&&!cancelled?resolve(out):reject(Error(cancelled?'已取消':err.trim()||`进程退出 ${code}`));});
 });
}
async function ff(args){return run(binary('ffmpeg'),['-hide_banner','-loglevel','error','-nostdin','-y',...args]);}
async function probe(p){return JSON.parse(await run(binary('ffprobe'),['-v','error','-show_streams','-show_format','-of','json',p]));}
async function stat(p){const s=await fs.stat(p);return {size:s.size,mtime:s.mtimeMs,ino:s.ino};}
async function digest(p){const h=crypto.createHash('sha256');const f=await fs.open(p);try{for await(const b of f.createReadStream())h.update(b);}finally{await f.close();}return h.digest('hex');}
async function exists(p){return fs.stat(p).then(()=>true,()=>false);}
const copy=(a,b)=>fs.copyFile(a,b,1);
export async function scan(roots,archiveCache=path.join(os.tmpdir(),'GS-Master-archives')){
 const rows=[],seen=new Set(),labels=new Map();let skipped=0;
 for(const raw of roots){
  const root=path.resolve(raw),s=await fs.lstat(root);if(s.isSymbolicLink()){skipped++;continue;}
  const label=s.isDirectory()?path.basename(root):'';
  let prefix=label;if(label){let n=1;while(labels.has(prefix)&&labels.get(prefix)!==root)prefix=label+' ('+(++n)+')';labels.set(prefix,root);}
  async function visit(p,rel,archive=null){
   check();const v=await fs.lstat(p);if(v.isSymbolicLink()){skipped++;return;}
   if(v.isDirectory()){
    if(p!==root&&(path.basename(p).startsWith('.')||p.endsWith('.app'))){skipped++;return;}
    for(const name of (await fs.readdir(p)).sort())await visit(path.join(p,name),path.join(rel,name));
   }else if(v.isFile()){
    if(/\.(zip|rar|7z)$/i.test(p)){
     if(v.size>1024*1024*1024)throw Error('压缩包超过 1 GB，请分批导入。');
     const bytes=await fs.readFile(p),hash=crypto.createHash('sha256').update(p).update(bytes).digest('hex');
     if(seen.has('archive:'+hash))return;seen.add('archive:'+hash);
     const destination=path.join(archiveCache,hash);const codecs=await loadCodecs();
     const files=await codecs.unpackArchive(new Uint8Array(bytes),name=>!!kind(name),1024*1024*1024);
     await fs.mkdir(destination,{recursive:true});
     const archiveName=path.basename(p,path.extname(p));
     for(const file of files){check();const target=path.join(destination,file.path);await fs.mkdir(path.dirname(target),{recursive:true});await fs.writeFile(target,file.bytes);await visit(target,path.join(rel?path.dirname(rel):'',archiveName,file.path),{archivePath:p,archiveEntry:file.path,archiveHash:crypto.createHash('sha256').update(bytes).digest('hex')});}
     return;
    }
    const k=kind(p);if(!k){skipped++;return;}const real=await fs.realpath(p);if(seen.has(real))return;seen.add(real);
    rows.push({id:crypto.createHash('sha256').update(real).digest('hex'),path:p,relative:rel||path.basename(p),name:path.basename(p),kind:k,size:v.size,selected:true,status:'待预估',...(archive||{})});
   }
  }
  await visit(root,prefix);
 }
 return {rows,skipped};
}
function normalized(raw){
 const s={preset:'balanced',videoFormat:'same',overwrite:false,backup:true,maxDimension:0,fps:0,mute:false,...raw};
 if(!['lossless','quality','balanced','small'].includes(s.preset)||!['same','mp4','webm'].includes(s.videoFormat))throw Error('无效压缩设置');
 if(![0,1280,1920,2560,3840].includes(s.maxDimension)||![0,24,30,60].includes(s.fps))throw Error('无效尺寸或帧率');
 if(s.preset==='lossless'&&(s.maxDimension||s.fps||s.mute||s.videoFormat!=='same'))throw Error('无损优化只保留原格式、尺寸、帧率和音轨；转格式请选择其他档位');
 return s;
}
function outputExt(row,s){return row.kind==='video'&&s.videoFormat!=='same'?s.videoFormat:ext(row.path);}
function outputRelative(row,s){const e=outputExt(row,s);return e===ext(row.path)?row.relative:row.relative.slice(0,-path.extname(row.relative).length)+'.'+e;}
async function imageInfo(p){return JSON.parse(await run(helper(),['--inspect',p]));}
async function loadCodecs(){if(!globalThis.DCCodecs)require('./codecs.cjs');return globalThis.DCCodecs;}
async function imageCompress(row,s,target,work){
 const e=ext(row.path),lossless=s.preset==='lossless',info=await imageInfo(row.path);
 const preserving=async reason=>{if(s.maxDimension&&Math.max(info.width,info.height)>s.maxDimension)throw Error(reason+'；暂不支持调整该文件尺寸');await copy(row.path,target);return reason;};
 if(info.width*info.height>64000000)throw Error('图片超过 6400 万像素，请先缩小后再压缩');
 if(info.frames>1){
  if(e==='gif'&&!lossless){
   const colors={quality:256,balanced:128,small:64}[s.preset];
   await ff(['-i',row.path,'-filter_complex',`[0:v]${s.maxDimension?`scale=w='min(iw,${s.maxDimension})':h='min(ih,${s.maxDimension})':force_original_aspect_ratio=decrease,`:''}split[a][b];[a]palettegen=max_colors=${colors}:reserve_transparent=1[p];[b][p]paletteuse=dither=sierra2_4a`,'-loop','-1',target]);
   // Keep the original GIF loop policy; ffmpeg writes no loop extension with -loop -1.
   const original=await fs.readFile(row.path),encoded=await fs.readFile(target);
   const pos=original.indexOf(Buffer.from('21ff0b4e45545343415045322e300301','hex'));
   if(pos>=0&&pos+19<=original.length){const table=(encoded[10]&128)?3*(1<<((encoded[10]&7)+1)):0;await fs.writeFile(target,Buffer.concat([encoded.subarray(0,13+table),original.subarray(pos,pos+19),encoded.subarray(13+table)]));}
   const out=await imageInfo(target);if(out.frames!==info.frames)throw Error('动图帧数校验失败');
   if(Math.abs(out.duration-info.duration)>0.05)throw Error('动图时长校验失败');
   return 'GIF 动画保留 · 调色板优化';
  }
  return preserving('保留动画/多页原文件，当前格式暂无安全优化');
 }
 if(info.depth>8){return preserving('高位深图片保留原文件，避免精度损失');}
 if(lossless&&!['png','webp'].includes(e)){await copy(row.path,target);return '此格式无损档保留原文件';}
 if(lossless&&e==='png'&&info.colorManaged){await copy(row.path,target);return '带色彩描述文件的 PNG 保留原文件，确保严格无损';}
 if(e==='gif'||e==='bmp'){return preserving('保留原文件，此格式通常适合转 PNG/WebP');}
 if(e==='tif'||e==='tiff'||e==='heic'||e==='heif'){
  await run(helper(),['--encode',row.path,target,String({quality:0.9,balanced:0.75,small:0.5}[s.preset]||1),String(s.maxDimension)]);
  return e.startsWith('tif')?'TIFF LZW 无损编码':'HEIC 质量优化';
 }
 let png;
 const codecs=await loadCodecs();
 if(e==='webp')png=await codecs.decodeWebP(new Uint8Array(await fs.readFile(row.path)));
 else if(lossless&&e==='png')png=new Uint8Array(await fs.readFile(row.path));
 else {const tmp=path.join(work,'decoded.png');await run(helper(),['--decode',row.path,tmp,String(s.maxDimension)]);png=new Uint8Array(await fs.readFile(tmp));}
 // WebP resizing uses the native sRGB renderer as for other still images.
 if(e==='webp'&&s.maxDimension){const tmp=path.join(work,'webp.png'),scaled=path.join(work,'scaled.png');await fs.writeFile(tmp,png);await run(helper(),['--decode',tmp,scaled,String(s.maxDimension)]);png=new Uint8Array(await fs.readFile(scaled));}
 const result=await codecs.encode(png,e==='jpeg'?'jpg':e,s.preset);await fs.writeFile(target,result.bytes);return result.note;
}
function videoPlan(info,s,e){
 const streams=info.streams||[],v=streams.filter(t=>t.codec_type==='video'&&!t.disposition?.attached_pic);
 if(v.length!==1)throw Error('暂只处理单画面视频，已保留原文件');
 const other=streams.filter(t=>!['video','audio'].includes(t.codec_type));
 if(s.preset!=='lossless'&&other.length)throw Error('含字幕/数据轨道，暂不自动重编码以免丢失内容');
 if(s.preset!=='lossless'&&streams.some(t=>t.disposition?.attached_pic))throw Error('含封面轨道，暂保留原文件');
 if(s.preset!=='lossless'&&(/^(yuva|rgba|bgra|argb|abgr|gbrap)/.test(v[0].pix_fmt||'')||['smpte2084','arib-std-b67'].includes(v[0].color_transfer)))throw Error('透明或 HDR 视频暂仅支持无损优化，避免改变画面');
 const d=Number(info.format?.duration);if(!Number.isFinite(d)||d<=0)throw Error('无法读取完整视频时长');
 if(s.preset==='lossless')return {args:['-map','0','-c','copy',...(['mp4','mov','m4v'].includes(e)?['-movflags','+faststart']:[])],duration:d,video:v[0]};
 if(!['mp4','mov','m4v','mkv','webm','avi'].includes(e))throw Error('该容器暂只支持无损优化，或请选择转 MP4/WebM');
 const crf={quality:19,balanced:24,small:30}[s.preset];
 let filters=[];
 if(s.maxDimension)filters.push(`scale=w='min(iw,${s.maxDimension})':h='min(ih,${s.maxDimension})':force_original_aspect_ratio=decrease:force_divisible_by=2`);
 else filters.push('pad=ceil(iw/2)*2:ceil(ih/2)*2');
 if(s.fps)filters.push(`fps=${s.fps}`);
 let args=['-map','0:v:0'];if(!s.mute)args.push('-map','0:a?');
 args.push('-map_metadata','0','-map_chapters','0','-vf',filters.join(','));
 if(e==='webm')args.push('-c:v','libvpx-vp9','-crf',String(crf+8),'-b:v','0','-row-mt','1','-cpu-used','3','-pix_fmt','yuv420p');
 else args.push('-c:v','libx264','-preset','slow','-crf',String(crf),'-pix_fmt','yuv420p');
 if(!s.mute){const aud=streams.filter(t=>t.codec_type==='audio');const compatible=aud.every(t=>e==='webm'?t.codec_name==='opus':e==='mkv'||t.codec_name==='aac');args.push('-c:a',compatible?'copy':e==='webm'?'libopus':'aac');if(!compatible)args.push('-b:a',s.preset==='small'?'96k':'160k');}
 if(['mp4','mov','m4v'].includes(e))args.push('-movflags','+faststart');
 return {args,duration:d,video:v[0]};
}
async function validateVideo(file,before,s,expected){
 const after=await probe(file),d=Number(after.format?.duration);
 if(!Number.isFinite(d)||Math.abs(d-expected)>Math.max(0.3,expected*0.01))throw Error('视频时长校验失败，未替换原文件');
 const count=(i,t)=>i.streams.filter(v=>v.codec_type===t).length;
 if(count(after,'video')!==count(before,'video')||(!s.mute&&count(after,'audio')!==count(before,'audio')))throw Error('音视频轨道校验失败');
 await ff(['-xerror','-i',file,'-map','0:v','-map','0:a?','-f','null','-']);
}
export async function prepare(row,raw,cache,preview=false){
 const s=normalized(raw);await fs.mkdir(cache,{recursive:true});check();
 const initial=await stat(row.path);if(initial.size>32*1024**3)throw Error('单文件超过 32 GB，请拆分后处理');
 const hash=await digest(row.path),key=crypto.createHash('sha256').update(hash+JSON.stringify(s)+row.path).digest('hex');
 const target=path.join(cache,key+'.'+outputExt(row,s)),meta=target+'.json';
 if(await exists(meta)){const saved=JSON.parse(await fs.readFile(meta));if(await exists(saved.file))return saved;}
 const work=await fs.mkdtemp(path.join(cache,'work-'));
 let note='',duration=0;
 try{
  if(row.kind==='image'){
   note=await imageCompress(row,s,target,work);
   const out=await imageInfo(target);if(!out.width||!out.height)throw Error('图片解码校验失败');
  }else{
   const info=await probe(row.path),plan=videoPlan(info,s,outputExt(row,s));duration=plan.duration;
   if(preview&&s.preset!=='lossless'&&duration>12){
    let size=0,total=0,previewFile=null;const len=Math.min(3,duration/10);
    for(const fraction of [0.1,0.5,0.85]){
     check();const f=path.join(work,'sample'+fraction+'.'+outputExt(row,s));
     await ff(['-ss',String(Math.min(duration-len,fraction*duration)),'-i',row.path,'-t',String(len),...plan.args,f]);
     if(!previewFile){previewFile=path.join(cache,key+'-preview.'+outputExt(row,s));await fs.copyFile(f,previewFile);}
     const p=await probe(f),actual=Number(p.format.duration);size+=(await stat(f)).size;total+=actual;
    }
    const estimate=Math.round(size/total*duration),same=outputExt(row,s)===ext(row.path),bounded=same&&!s.maxDimension&&!s.fps&&!s.mute?Math.min(initial.size,estimate):estimate;
    return {estimate:true,previewFile,size:bounded,low:Math.round(bounded*0.65),high:Math.round(bounded*1.4),original:initial.size,note:'三段抽样估算，实际大小受内容变化影响',hash};
   }
   await ff(['-i',row.path,...plan.args,target]);
   await validateVideo(target,info,s,duration);note=s.preset==='lossless'?'无损封装优化 · 保留轨道':'完整编码与解码校验通过';
  }
  check();
  if(hash!==await digest(row.path))throw Error('处理期间原文件发生变化，请重新预估');
  let size=(await stat(target)).size;
  const keepOriginal=outputExt(row,s)===ext(row.path)&&!s.maxDimension&&!s.fps&&!s.mute&&size>=initial.size;
  if(keepOriginal){await fs.unlink(target);await copy(row.path,target);size=initial.size;note='无需压缩 · '+note;}
  const result={file:target,size,original:initial.size,note,estimate:false,hash,sourceStat:initial};
  await fs.writeFile(meta,JSON.stringify(result));return result;
 }catch(e){await fs.rm(target,{force:true});throw e;}finally{await fs.rm(work,{recursive:true,force:true});}
}
async function uniqueFolder(base,label){await fs.mkdir(base,{recursive:true});for(let n=0;;n++){const p=path.join(base,label+(n?' ('+n+')':''));try{await fs.mkdir(p);return p;}catch(e){if(e.code!=='EEXIST')throw e;}}}
function safeRelative(p){if(path.isAbsolute(p)||p.split(path.sep).includes('..'))throw Error('无效输出路径');return p;}
export async function batch(request,report=emit){
 const s=normalized(request.stageOnly?{...request.settings,overwrite:false}:request.settings),rows=request.rows.filter(r=>r.selected!==false),cache=request.cache;
 const archiveRow=row=>path.resolve(row.path).startsWith(path.resolve(cache,'archives')+path.sep);
 if(!rows.length)throw Error('请先选择文件');
 let outputRoot=null,backupRoot=null,done=0,failed=0,log=[];
 const stamp=new Date().toISOString().replace(/[:.]/g,'-').slice(0,19);
 if(request.action==='compress'&&(!s.overwrite||rows.some(r=>archiveRow(r)||outputExt(r,s)!==ext(r.path)))){
  if(!s.output)throw Error('请选择输出位置');outputRoot=await uniqueFolder(s.output,'GSMaster-'+stamp);
 }
 const used=new Set();
 for(const row of rows){
  if(cancelled)break;report({type:'status',id:row.id,status:request.action==='estimate'?'试压预估中…':'压缩与校验中…'});
  try{
   const result=await prepare(row,s,cache,request.action==='estimate');check();let dest=null;
   if(request.action==='compress'){
    if(s.overwrite&&!archiveRow(row)&&outputExt(row,s)===ext(row.path)){
     if(await digest(row.path)!==result.hash)throw Error('原文件已变化，已停止覆盖');
     if(result.size===result.original&&result.note.startsWith('无需压缩')){dest=row.path;}
     else{
      // Stage on the source volume. Only rename after complete copy and validation.
      const staged=path.join(path.dirname(row.path),'.dcmaster-'+crypto.randomUUID()+'.tmp');
      try{
       await copy(result.file,staged);await fs.chmod(staged,(await fs.stat(row.path)).mode);
       const handle=await fs.open(staged,'r+');await handle.sync();await handle.close();check();
       if(s.backup){
        backupRoot??=await uniqueFolder(s.output||path.dirname(row.path),'backup_GSMaster-备份-'+stamp);
        let backup=path.join(backupRoot,safeRelative(row.relative));
        if(await exists(backup))backup=path.join(backupRoot,row.id.slice(0,10),safeRelative(row.relative));
        await fs.mkdir(path.dirname(backup),{recursive:true});await copy(row.path,backup);
        if(await digest(backup)!==result.hash)throw Error('备份校验失败，未覆盖原文件');
       }
       if(await digest(row.path)!==result.hash)throw Error('原文件已变化，未覆盖');check();
       await fs.rename(staged,row.path);dest=row.path;
      }finally{await fs.rm(staged,{force:true});}
     }
    }else{
     let relative=safeRelative(outputRelative(row,s));
     // Preserve the exact filename; separate same-name sources into subdirectories.
     let target=path.join(outputRoot,relative);
     if(used.has(target.toLocaleLowerCase())||await exists(target))target=path.join(outputRoot,'来源-'+row.id.slice(0,10),relative);
     used.add(target.toLocaleLowerCase());await fs.mkdir(path.dirname(target),{recursive:true});
     try{check();await copy(result.file,target);check();dest=target;}catch(e){await fs.rm(target,{force:true});throw e;}
    }
   }
   done++;const item={type:'result',id:row.id,...result,destination:dest};report(item);log.push({name:row.name,source:row.path,destination:dest,size:result.size,note:result.note});
  }catch(e){failed++;report({type:'error',id:row.id,error:e.message.slice(-1200)});log.push({name:row.name,error:e.message});if(cancelled)break;}
 }

 report({type:'done',done,failed,cancelled,output:outputRoot,backup:backupRoot});
}
export async function saveBatch(request,report=emit){
 const s=normalized(request.settings),rows=request.rows,codecs=await loadCodecs();
 if(s.overwrite&&rows.some(row=>row.archivePath&&ext(row.archivePath)!=='zip'))throw Error('RAR / 7z 暂不支持原地重打包，请取消原地覆盖后另存。');
 if(!s.output)throw Error('请选择保存位置');
 const archives=new Map(),backupFolders=new Map();let done=0,failed=0,latestBackup=null;
 async function backup(source,label,relative=path.basename(source)){if(!s.backup)return;let folder=backupFolders.get(label);if(!folder){folder=await uniqueFolder(s.output,'backup_'+label);backupFolders.set(label,folder);}latestBackup=folder;const target=path.join(folder,safeRelative(relative));await fs.mkdir(path.dirname(target),{recursive:true});await copy(source,target);}
 async function replace(source,file,hash,label,relative){
  if(await digest(source)!==hash)throw Error('原文件已变化，未覆盖');await backup(source,label,relative);
  const staged=path.join(path.dirname(source),'.gsmaster-'+crypto.randomUUID()+'.tmp');
  try{await copy(file,staged);check();if(await digest(source)!==hash)throw Error('原文件已变化，未覆盖');await fs.rename(staged,source);}finally{await fs.rm(staged,{force:true});}
 }
 for(const row of rows){
  if(cancelled)break;
  if(s.overwrite&&row.archivePath){if(ext(row.archivePath)!=='zip')throw Error('RAR / 7z 暂不支持原地重打包，请取消原地覆盖后另存。');const group=archives.get(row.archivePath)||[];group.push(row);archives.set(row.archivePath,group);continue;}
  try{
   check();let dest;
   if(s.overwrite&&!row.archivePath&&ext(row.path)===ext(row.file)){const label=row.relative.includes(path.sep)?row.relative.split(path.sep)[0]:path.basename(path.dirname(row.path));await replace(row.path,row.file,row.hash,label,row.relative.includes(path.sep)?row.relative.split(path.sep).slice(1).join(path.sep):path.basename(row.path));dest=row.path;}
   else{dest=path.join(s.output,safeRelative(row.relative));if(ext(dest)!==ext(row.file))dest=dest.slice(0,-path.extname(dest).length)+path.extname(row.file);await fs.mkdir(path.dirname(dest),{recursive:true});if(await exists(dest))throw Error('目标已存在，未覆盖：'+dest);await copy(row.file,dest);}
   done++;report({...row,type:'result',destination:dest,previewFile:dest});
  }catch(error){failed++;report({type:'error',id:row.id,error:error.message});}
 }
 for(const [archive,group] of archives){
  if(cancelled)break;
  try{
   check();const input=new Uint8Array(await fs.readFile(archive)),hash=crypto.createHash('sha256').update(input).digest('hex');if(group.some(row=>row.archiveHash!==hash))throw Error('原压缩包已变化，未覆盖');
   const entries=codecs.readZIPEntries(input);for(const row of group)entries[row.archiveEntry]=new Uint8Array(await fs.readFile(row.file));
   const bytes=codecs.rewriteZIP(entries),verified=codecs.readZIPEntries(bytes);
   for(const [name,data] of Object.entries(entries))if(!verified[name]||!Buffer.from(data).equals(Buffer.from(verified[name])))throw Error('ZIP 重打包校验失败');
   const staged=path.join(request.cache,'archive-'+crypto.randomUUID()+'.zip');await fs.writeFile(staged,bytes);await replace(archive,staged,hash,path.basename(archive,path.extname(archive)));await fs.rm(staged,{force:true});
   for(const row of group){const preview=path.join(request.cache,'saved-preview-'+crypto.randomUUID()+path.extname(row.file));await fs.copyFile(row.file,preview);done++;report({...row,type:'result',destination:archive,previewFile:preview});}
  }catch(error){failed+=group.length;for(const row of group)report({type:'error',id:row.id,error:error.message});}
 }
 report({type:'done',done,failed,cancelled,output:s.output,backup:latestBackup});
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
 try{const request=JSON.parse(await fs.readFile(process.argv[2],'utf8'));if(request.action==='scan')emit({type:'scan',...await scan(request.roots,request.cache)});else if(request.action==='save')await saveBatch(request);else await batch(request);}catch(e){emit({type:'fatal',error:e.message});process.exitCode=1;}
}
