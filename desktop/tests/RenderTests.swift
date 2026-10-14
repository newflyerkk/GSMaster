import AppKit
import SwiftUI
@main struct RenderTests {
 static func main() throws {
  let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
  let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
  let model=CompressorModel(historyURL:root.appendingPathComponent("desktop/build/render-history.json"))
  let sample=root.appendingPathComponent("desktop/tests/ui-input/子文件夹/界面.png").path
  model.rows=[MediaRow(id:"a",path:sample,relative:"素材/界面.png",name:"界面.png",kind:"image",size:50463,selected:false,status:"已完成",preview:"17 KB",saving:"−67.1%",note:"自适应减色 · 点击右侧查看",resultSize:16592,destination:sample,previewPath:sample),MediaRow(id:"b",path:sample,relative:"视频/产品演示.mp4",name:"产品演示.mp4",kind:"video",size:4050303,status:"抽样预估",preview:"1.8–3.6 MB",saving:"约 −38%",note:"三段抽样估算",previewPath:sample,samplePreview:true)]
  model.message="已完成：1 个成功，0 个失败。";model.history=[HistoryEntry(date:Date(),name:"界面.png",path:sample,original:50463,size:16592,note:"压缩完成")]
  let populatedRows=model.rows
  for dark in [false,true] {
   app.appearance=NSAppearance(named:dark ? .darkAqua:.aqua)
   for mode in ["queue","history","empty"] {
    model.rows=mode == "empty" ? []:populatedRows
    model.advanced=mode == "empty"
    model.showingHistory=mode == "history"
    let host=NSHostingView(rootView:MainView(model:model).environment(\.colorScheme,dark ? .dark:.light))
    let win=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:620),styleMask:[.borderless],backing:.buffered,defer:false)
    win.appearance=NSAppearance(named:dark ? .darkAqua:.aqua);win.contentView=host;host.frame=NSRect(x:0,y:0,width:800,height:620)
    host.layoutSubtreeIfNeeded();RunLoop.main.run(until:Date().addingTimeInterval(0.15))
    guard let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds) else{fatalError("No bitmap")};host.cacheDisplay(in:host.bounds,to:rep)
    let name="desktop/build/ui-\(mode)-\(dark ? "dark":"light").png"
    try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name))
   }
  }
  print("Rendered compact queue/history in light/dark")
 }
}
