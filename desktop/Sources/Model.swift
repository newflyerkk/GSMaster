import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MediaRow: Identifiable {
    var id:String, path:String, relative:String, name:String, kind:String
    var size:Int64
    var selected=true, status="待预估", preview="—", saving="—", note=""
    var resultSize:Int64?=nil
    var destination:String?=nil
    var previewPath:String?=nil
    var samplePreview=false
    var json:[String:Any] { ["id":id,"path":path,"relative":relative,"name":name,"kind":kind,"size":size,"selected":selected] }
}
func readable(_ n:Int64)->String {ByteCountFormatter.string(fromByteCount:n,countStyle:.file)}

class CompressorModel: ObservableObject {
    @Published var rows:[MediaRow]=[]
    @Published var history:[HistoryEntry]=[]
    @Published var showingHistory=false
    @Published var previewItem:PreviewItem?=nil
    @Published var historyWarning=""
    let preferences:UserDefaults
    var restoringPreferences=true
    let historyStore:HistoryStore
    init(historyURL:URL = HistoryStore.defaultURL, preferences:UserDefaults = .standard){
        self.preferences=preferences
        historyStore=HistoryStore(url:historyURL)
        if let saved=preferences.dictionary(forKey:"GS-Master-settings-v1") {
            preset=saved["preset"] as? String ?? preset;videoFormat=saved["videoFormat"] as? String ?? videoFormat
            overwrite=saved["overwrite"] as? Bool ?? overwrite;backup=saved["backup"] as? Bool ?? backup;mute=saved["mute"] as? Bool ?? mute
            maxDimension=saved["maxDimension"] as? Int ?? maxDimension;fps=saved["fps"] as? Int ?? fps
            output=saved["output"] as? String ?? output;advanced=saved["advanced"] as? Bool ?? advanced
        }
        restoringPreferences=false
        do{history=try historyStore.load()}catch{historyWarning="历史记录读取失败，原记录未修改。"}
    }
    func reveal(_ entry:HistoryEntry){
        let url=entry.resolvedURL()
        guard FileManager.default.fileExists(atPath:url.path) else{message="文件已移动或删除，无法定位："+entry.name;return}
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    func preview(_ row:MediaRow){
        guard let p=row.previewPath,FileManager.default.fileExists(atPath:p) else{message="请先预估压缩效果，再查看预览。";return}
        let original=row.destination==row.path ? nil : URL(fileURLWithPath:row.path)
        previewItem=PreviewItem(name:row.name,original:original,output:URL(fileURLWithPath:p),label:row.samplePreview ? "压缩抽样片段（非完整视频）" : "压缩后 · "+row.preview)
    }
    func saveHistory(){do{try historyStore.save(history);historyWarning=""}catch{historyWarning="历史记录保存失败："+error.localizedDescription}}
    func clearHistory(){history=[];saveHistory()}

    @Published var preset="balanced" {didSet{savePreferences()}}
    @Published var videoFormat="same" {didSet{savePreferences()}}
    @Published var output=FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask).first!.path {didSet{savePreferences()}}
    @Published var overwrite=false {didSet{savePreferences()}}
    @Published var backup=true {didSet{savePreferences()}}
    @Published var maxDimension=0 {didSet{savePreferences()}}
    @Published var fps=0 {didSet{savePreferences()}}
    @Published var mute=false {didSet{savePreferences()}}
    @Published var busy=false
    @Published var message="添加文件或文件夹，先预估，再开始压缩。"
    @Published var completed=0
    @Published var total=0
    @Published var cancelRequested=false
    @Published var latestOutput:String?=nil
    @Published var latestBackup:String?=nil
    @Published var advanced=false {didSet{savePreferences()}}
    let cache=FileManager.default.temporaryDirectory.appendingPathComponent("GSMaster-"+UUID().uuidString)
    var process:Process?
    var currentAction=""
    func savePreferences(){guard !restoringPreferences else{return};var saved=settings;saved["advanced"]=advanced;preferences.set(saved,forKey:"GS-Master-settings-v1")}
    var settings:[String:Any] {["preset":preset,"videoFormat":videoFormat,"overwrite":overwrite,"backup":backup,"output":output,"maxDimension":maxDimension,"fps":fps,"mute":mute]}
    var selectedCount:Int {rows.filter{$0.selected}.count}
    func invalidate(){for i in rows.indices {rows[i].preview="—";rows[i].saving="—";rows[i].status="待预估";rows[i].note="";rows[i].resultSize=nil;rows[i].previewPath=nil;rows[i].samplePreview=false};message="设置已更新，请重新预估。"}
    func addPanel(){let panel=NSOpenPanel();panel.title="选择图片、视频或文件夹";panel.canChooseFiles=true;panel.canChooseDirectories=true;panel.allowsMultipleSelection=true;if panel.runModal() == .OK{add(panel.urls)}}
    func chooseOutput(){let panel=NSOpenPanel();panel.title="选择结果文件夹的存放位置";panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.canCreateDirectories=true;if panel.runModal() == .OK,let url=panel.url{output=url.path}}
    func add(_ urls:[URL]){guard !busy else{return};showingHistory=false;cancelRequested=false;launch(["action":"scan","roots":urls.map{$0.path},"cache":cache.appendingPathComponent("archives").path])}
    func start(_ action:String){guard !busy,selectedCount>0 else{return};completed=0;total=selectedCount;cancelRequested=false;latestOutput=nil;latestBackup=nil
        launch(["action":action,"rows":rows.map{$0.json},"settings":settings,"cache":cache.path])
    }
    func cancel(){cancelRequested=true;message="正在取消；已完成的文件保留，当前文件不替换。";process?.terminate()}
    func launch(_ request:[String:Any]){
        busy=true;currentAction=request["action"] as? String ?? "";message=currentAction=="scan" ? "正在扫描文件夹…" : "开始处理 \(selectedCount) 个文件…"
        let action=currentAction
        DispatchQueue.global(qos:.userInitiated).async {
            let file=self.cache.appendingPathComponent(UUID().uuidString+".json")
            do {
                try FileManager.default.createDirectory(at:self.cache,withIntermediateDirectories:true)
                try JSONSerialization.data(withJSONObject:request).write(to:file)
                let resource=Bundle.main.resourceURL!
                let p=Process(),pipe=Pipe(),errors=Pipe()
                p.executableURL=resource.appendingPathComponent("tools/node")
                p.arguments=[resource.appendingPathComponent("engine/engine.mjs").path,file.path]
                p.standardOutput=pipe;p.standardError=errors
                var env=ProcessInfo.processInfo.environment;env["DC_HELPER"]=Bundle.main.executableURL!.path;env["DC_TOOLS"]=resource.appendingPathComponent("tools").path;p.environment=env
                // Drain stderr concurrently to avoid blocking a child on a full pipe.
                errors.fileHandleForReading.readabilityHandler={h in _=h.availableData}
                try p.run();DispatchQueue.main.async{self.process=p;if self.cancelRequested{p.terminate()}}
                var pending=Data()
                while true {
                    let chunk=pipe.fileHandleForReading.availableData;if chunk.isEmpty{break};pending.append(chunk)
                    while let end=pending.firstIndex(of:10){let line=pending[..<end];pending.removeSubrange(...end);if let obj=try? JSONSerialization.jsonObject(with:Data(line)) as? [String:Any]{DispatchQueue.main.async{self.receive(obj)}}}
                }
                p.waitUntilExit();errors.fileHandleForReading.readabilityHandler=nil
                try? FileManager.default.removeItem(at:file)
                DispatchQueue.main.async{self.busy=false;self.process=nil;if p.terminationStatus != 0 && !self.cancelRequested && !self.message.contains("失败"){self.message="处理失败，请查看文件状态。"};if action=="scan" {self.total=0}}
            }catch{DispatchQueue.main.async{self.busy=false;self.message="启动失败：\(error.localizedDescription)"}}
        }
    }
    func receive(_ obj:[String:Any]){
        let type=obj["type"] as? String ?? ""
        if type=="scan" {
            var additions:[MediaRow]=[]
            for r in obj["rows"] as? [[String:Any]] ?? [] {
                guard let id=r["id"] as? String,!rows.contains(where:{$0.id==id}) else{continue}
                additions.append(MediaRow(id:id,path:r["path"] as! String,relative:r["relative"] as! String,name:r["name"] as! String,kind:r["kind"] as! String,size:(r["size"] as? NSNumber)?.int64Value ?? 0))
            }
            rows.insert(contentsOf:additions,at:0)
            message="已添加 \(rows.count) 个文件；跳过 \(obj["skipped"] ?? 0) 个不支持/隐藏/链接项目。";return
        }
        if type=="done" {
            latestOutput=obj["output"] as? String;latestBackup=obj["backup"] as? String
            let cancelled=obj["cancelled"] as? Bool ?? false
            message="\(cancelled ? "已取消" : "已完成")：\(obj["done"] ?? 0) 个成功，\(obj["failed"] ?? 0) 个失败。"
            return
        }
        if type=="fatal" {message="处理失败：\(obj["error"] ?? "未知错误")";return}
        guard let id=obj["id"] as? String,let i=rows.firstIndex(where:{$0.id==id}) else{return}
        if type=="status"{rows[i].status=obj["status"] as? String ?? "处理中";message="\(completed+1)/\(total) · \(rows[i].name)"}
        if type=="error"{rows[i].status=cancelRequested ? "已取消" : "失败";rows[i].note=obj["error"] as? String ?? "";completed+=1}
        if type=="result" {
            let size=(obj["size"] as? NSNumber)?.int64Value ?? 0, original=(obj["original"] as? NSNumber)?.int64Value ?? rows[i].size
            let estimate=obj["estimate"] as? Bool ?? false
            rows[i].size=original;rows[i].resultSize=size
            rows[i].preview=estimate ? "约 "+readable(size) : readable(size)
            if estimate,let low=obj["low"] as? NSNumber,let high=obj["high"] as? NSNumber{rows[i].preview="\(readable(low.int64Value))–\(readable(high.int64Value))"}
            let ratio=original>0 ? (1-Double(size)/Double(original))*100 : 0
            rows[i].saving=String(format:ratio>=0 ? "%@−%.1f%%" : "%@+%.1f%%",estimate ? "约 " : "",abs(ratio))
            rows[i].note=obj["note"] as? String ?? "";rows[i].destination=obj["destination"] as? String
            rows[i].previewPath=(obj["previewFile"] as? String) ?? (obj["destination"] as? String) ?? (obj["file"] as? String)
            rows[i].samplePreview=estimate
            if currentAction=="compress",let dest=obj["destination"] as? String {
                rows[i].selected=false
                let url=URL(fileURLWithPath:dest)
                let entry=HistoryEntry(date:Date(),name:url.lastPathComponent,path:dest,original:original,size:size,note:rows[i].note,bookmark:try? url.bookmarkData(options:[],includingResourceValuesForKeys:nil,relativeTo:nil))
                history.insert(entry,at:0);history=Array(history.prefix(500));saveHistory()
            }
            rows[i].status=currentAction=="estimate" ? (estimate ? "抽样预估" : "试压完成") : "已完成"
            completed+=1
        }
    }
}

