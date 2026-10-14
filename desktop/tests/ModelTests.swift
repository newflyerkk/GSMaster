import Foundation
import AppKit
@main struct ModelTests {
 static func main() throws {
  let dir=FileManager.default.temporaryDirectory.appendingPathComponent("gsmaster-model-"+UUID().uuidString)
  try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
  defer{try? FileManager.default.removeItem(at:dir)}
  let history=dir.appendingPathComponent("history.json"),file=dir.appendingPathComponent("result.png")
  try Data([1,2,3]).write(to:file)
  let model=CompressorModel(historyURL:history)
  func row(_ id:String)->[String:Any]{["id":id,"path":dir.appendingPathComponent(id+".png").path,"relative":id+".png","name":id+".png","kind":"image","size":100]}
  model.receive(["type":"scan","rows":[row("old")],"skipped":0])
  model.receive(["type":"scan","rows":[row("new1"),row("new2"),row("old")],"skipped":0])
  precondition(model.rows.map{$0.id} == ["new1","new2","old"],"New batch should remain ordered at top")
  model.currentAction="estimate"
  model.receive(["type":"result","id":"new1","size":30,"original":100,"estimate":true,"previewFile":file.path,"note":"sample"])
  precondition(model.rows[0].selected && model.history.isEmpty)
  model.preview(model.rows[0]);precondition(model.previewItem?.output.path == file.path);precondition(model.previewItem!.label.contains("抽样"))
  model.currentAction="compress"
  model.receive(["type":"result","id":"new1","size":30,"original":100,"estimate":false,"file":file.path,"destination":file.path,"note":"done"])
  precondition(!model.rows[0].selected && model.rows[1].selected && model.history.count==1)
  model.receive(["type":"error","id":"new2","error":"failed"])
  precondition(model.rows[1].selected)
  let reopened=CompressorModel(historyURL:history)
  precondition(reopened.history.count==1 && reopened.history[0].resolvedURL().resolvingSymlinksInPath().path==file.resolvingSymlinksInPath().path)
  model.invalidate();precondition(model.rows[0].previewPath==nil)
  reopened.clearHistory();let cleared=try HistoryStore(url:history).load();precondition(cleared.isEmpty)
  precondition(FileManager.default.fileExists(atPath:file.path),"Clear history must not delete output")
  print("PASS: newest-first, dedupe, preview source, sample labeling, successful deselect, failure retained, history persistence, reveal path, clear without deleting files")
 }
}
