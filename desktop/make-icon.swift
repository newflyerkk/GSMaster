import AppKit
let dir=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {for factor in [1,2]{let n=size*factor
 let img=NSImage(size:NSSize(width:n,height:n));img.lockFocus();let scale=CGFloat(n)/1024
 let ctx=NSGraphicsContext.current!.cgContext;ctx.scaleBy(x:scale,y:scale)
 let tile=NSBezierPath(roundedRect:NSRect(x:64,y:64,width:896,height:896),xRadius:210,yRadius:210)
 NSGradient(starting:NSColor(red:0,green:0.36,blue:0.82,alpha:1),ending:NSColor(red:0.086,green:0.53,blue:1,alpha:1))!.draw(in:tile,angle:90)
 NSColor.white.withAlphaComponent(0.38).setStroke();tile.lineWidth=6;tile.stroke()
 let p=NSBezierPath();p.lineWidth=60;p.lineCapStyle = .round;p.lineJoinStyle = .round
 p.move(to:NSPoint(x:280,y:744));p.line(to:NSPoint(x:450,y:574));p.move(to:NSPoint(x:290,y:574));p.line(to:NSPoint(x:450,y:574));p.line(to:NSPoint(x:450,y:734))
 p.move(to:NSPoint(x:744,y:280));p.line(to:NSPoint(x:574,y:450));p.move(to:NSPoint(x:734,y:450));p.line(to:NSPoint(x:574,y:450));p.line(to:NSPoint(x:574,y:290));NSColor.white.setStroke();p.stroke();img.unlockFocus()
 let rep=NSBitmapImageRep(data:img.tiffRepresentation!)!;let data=rep.representation(using:.png,properties:[:])!;try data.write(to:dir.appendingPathComponent("icon_\(size)x\(size)\(factor==2 ? "@2x" : "").png"))
}}
