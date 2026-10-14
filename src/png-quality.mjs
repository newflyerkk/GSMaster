// Compare composited pixels on black and white; protects semi-transparent edges.
export function visualError(a,b) {
 if(a.width!==b.width||a.height!==b.height)return {rms:Infinity,max:Infinity};
 let sum=0,max=0,count=0;
 for(let i=0;i<a.data.length;i+=4){
  const aa=a.data[i+3]/255,ba=b.data[i+3]/255;
  for(let c=0;c<3;c++)for(const bg of [0,255]){
   const d=Math.abs(a.data[i+c]*aa+bg*(1-aa)-b.data[i+c]*ba-bg*(1-ba));
   sum+=d*d;max=Math.max(max,d);count++;
  }
 }
 return {rms:Math.sqrt(sum/count),max};
}
export const pngProfiles={quality:{colors:[256,128,64,32,16],rms:0.8,max:5},balanced:{colors:[256,128,64,32,16,8],rms:2,max:14},size:{colors:[256,128,64,32,16,8,4],rms:5,max:36}};
