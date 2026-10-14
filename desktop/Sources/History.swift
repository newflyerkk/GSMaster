import Foundation

struct HistoryEntry:Identifiable,Codable {
    var id=UUID().uuidString
    let date:Date
    let name:String
    let path:String
    let original:Int64
    let size:Int64
    let note:String
    var bookmark:Data?
    func resolvedURL()->URL {
        if let data=bookmark {var stale=false;if let url=try? URL(resolvingBookmarkData:data,options:[.withoutUI,.withoutMounting],relativeTo:nil,bookmarkDataIsStale:&stale){return url}}
        return URL(fileURLWithPath:path)
    }
}
struct HistoryStore {
    let url:URL
    static var defaultURL:URL {FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!.appendingPathComponent("GSMaster-gpt/history.json")}
    func load() throws->[HistoryEntry] {
        guard FileManager.default.fileExists(atPath:url.path) else{return []}
        return try JSONDecoder().decode([HistoryEntry].self,from:Data(contentsOf:url))
    }
    func save(_ entries:[HistoryEntry]) throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(Array(entries.prefix(500))).write(to:url,options:.atomic)
    }
}
struct PreviewItem:Identifiable {
    let id=UUID()
    let name:String
    let original:URL?
    let output:URL
    let label:String
}
