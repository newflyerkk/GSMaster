export function parseScales(values, custom='') {
  const all = [...values, ...custom.split(/[,，\s]+/).filter(Boolean).map(v => Number(v.replace(/x$/i,'')))].map(Number);
  if (!all.length || all.some(v => !Number.isFinite(v) || v <= 0 || v > 16)) throw new Error('倍率须大于 0 且不超过 16。');
  return [...new Set(all)].sort((a,b)=>a-b);
}
export function safeName(name) { return (name.normalize('NFC').replace(/[\\/:*?"<>|\x00-\x1f]/g,'_').replace(/[. ]+$/g,'').slice(0,100) || '未命名'); }
export function outputPath(asset, named, used) {
  const base = named ? safeName(asset.name) : `${asset.format}_${String(asset.index+1).padStart(3,'0')}`;
  const suffix = asset.scale === 1 ? '' : `@${asset.scale}x`;
  const prefix = `${asset.format}/${asset.scale}x/`;
  let path = `${prefix}${base}${suffix}.${asset.format}`, i=2;
  while(used.has(path.toLowerCase())) path=`${prefix}${base}_${i++}${suffix}.${asset.format}`;
  used.add(path.toLowerCase()); return path;
}
export function features(image) {
  let alpha=false, edges=0, samples=0; const colors=new Set();
  const stride=Math.max(1,Math.floor(image.width*image.height/12000));
  for(let p=0;p<image.width*image.height;p+=stride) {
    const i=p*4,d=image.data; alpha ||= d[i+3]!==255;
    colors.add((d[i]>>3)*1024+(d[i+1]>>3)*32+(d[i+2]>>3));
    if(p%image.width) edges += Math.abs(d[i]-d[i-4])+Math.abs(d[i+1]-d[i-3])+Math.abs(d[i+2]-d[i-2]);
    samples++;
  }
  return {alpha,kind:colors.size<128?'graphic':edges/samples>65?'texture':'photo',colors:colors.size};
}
export function equalPixels(a,b) {return a.width===b.width && a.height===b.height && a.data.length===b.data.length && a.data.every((v,i)=>v===b.data[i]);}
export function smaller(a,b) {return a.byteLength<=b.byteLength?a:b;}
