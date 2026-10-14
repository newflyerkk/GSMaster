import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Quartz
import ImageIO

private let accent=Color(red:0,green:0.404,blue:0.859)
struct GlassPanel:ViewModifier {
    @Environment(\.accessibilityReduceTransparency) var reduce
    @Environment(\.colorScheme) var scheme
    func body(content:Content)->some View {
        content
            .background {
                if reduce {RoundedRectangle(cornerRadius:22).fill(Color(nsColor:.controlBackgroundColor))}
                else {RoundedRectangle(cornerRadius:22).fill(.regularMaterial)}
            }
            .overlay(RoundedRectangle(cornerRadius:22).strokeBorder(.white.opacity(scheme == .dark ? 0.12:0.85)))
            .shadow(color:Color.black.opacity(scheme == .dark ? 0.12:0.035),radius:12,y:5)
    }
}
struct ActionButtonStyle:ButtonStyle {
    var prominent=false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduce
    func makeBody(configuration:Configuration)->some View {
        configuration.label
            .padding(.horizontal,16).frame(minHeight:44)
            .background {
                if prominent && enabled {
                    Capsule().fill(LinearGradient(colors:[Color(red:0.086,green:0.49,blue:0.96),Color(red:0,green:0.36,blue:0.82)],startPoint:.top,endPoint:.bottom))
                } else if reduce {
                    Capsule().fill(Color(nsColor:.controlBackgroundColor))
                } else {
                    Capsule().fill(.regularMaterial)
                }
            }
            .overlay(Capsule().strokeBorder(.white.opacity(scheme == .dark ? 0.18:0.65)))
            .shadow(color:prominent && enabled ? accent.opacity(0.18):.black.opacity(0.035),radius:6,y:3)
            .opacity(enabled ? (configuration.isPressed ? 0.75:1):0.45)
            .contentShape(Capsule())
    }
}
struct Thumbnail:View {
    let path:String
    @State private var image:NSImage?
    var body:some View {
        ZStack{RoundedRectangle(cornerRadius:9).fill(.quaternary.opacity(0.5));if let image{Image(nsImage:image).resizable().scaledToFit().padding(3)}else{Image(systemName:"doc.richtext").foregroundStyle(.secondary)}}
            .frame(width:42,height:42).clipShape(RoundedRectangle(cornerRadius:9)).accessibilityHidden(true)
            .task(id:path){
                let p=path
                let result=await Task.detached(priority:.utility){()->NSImage? in
                    guard let src=CGImageSourceCreateWithURL(URL(fileURLWithPath:p) as CFURL,nil),let cg=CGImageSourceCreateThumbnailAtIndex(src,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:100] as CFDictionary) else{return nil}
                    return NSImage(cgImage:cg,size:.zero)
                }.value
                if !Task.isCancelled{image=result}
            }
    }
}
struct QuickPreview:NSViewRepresentable {
    let url:URL
    func makeNSView(context:Context)->QLPreviewView{let view=QLPreviewView(frame:.zero,style:.normal)!;view.autostarts=false;view.previewItem=url as NSURL;return view}
    func updateNSView(_ view:QLPreviewView,context:Context){if (view.previewItem as? NSURL) != url as NSURL{view.previewItem=url as NSURL}}
    static func dismantleNSView(_ view:QLPreviewView,coordinator:()){view.close()}
}
struct PreviewSheet:View {
    let item:PreviewItem
    @Environment(\.dismiss) var dismiss
    var body:some View {
        VStack(spacing:12){
            HStack{VStack(alignment:.leading){Text(item.name).font(.headline).lineLimit(1);Text("查看细节与透明边缘；视频可在各自播放器中播放。").font(.caption).foregroundStyle(.secondary)};Spacer();Button("完成"){dismiss()}.keyboardShortcut(.cancelAction)}
            HStack(spacing:12){if let original=item.original{pane(original,"原文件")};pane(item.output,item.label)}
            HStack{Text("系统预览不支持的媒体可使用外部播放器打开。").font(.caption).foregroundStyle(.secondary);Spacer();Button("打开压缩结果"){NSWorkspace.shared.open(item.output)}}
        }.padding(20).frame(width:800,height:540)
    }
    func pane(_ url:URL,_ title:String)->some View{
        VStack(spacing:8){Text(title).font(.subheadline).fontWeight(.medium);QuickPreview(url:url).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:12))}.frame(maxWidth:.infinity)
    }
}
struct MainView:View {
    @ObservedObject var model:CompressorModel
    @Environment(\.colorScheme) var scheme
    @State var targeted=false
    var controlInk:Color {scheme == .dark ? Color(red:0.40,green:0.72,blue:1):accent}
    var body:some View {
        ZStack{
            (scheme == .dark ? Color(red:0.065,green:0.085,blue:0.12):Color(red:0.949,green:0.957,blue:0.973))
            RadialGradient(colors:[accent.opacity(scheme == .dark ? 0.20:0.13),.clear],center:.topLeading,startRadius:0,endRadius:650).allowsHitTesting(false)
            RadialGradient(colors:[Color.cyan.opacity(0.07),.clear],center:.bottomTrailing,startRadius:0,endRadius:450).allowsHitTesting(false)
            VStack(spacing:12){header
                if model.showingHistory{historyPanel}else{settings;queue;selection}
                footer
            }.padding(18)
        }.tint(accent).frame(minWidth:800,minHeight:620)
            .sheet(item:$model.previewItem){PreviewSheet(item:$0)}
            .onChange(of:model.preset){_,v in if v=="lossless"{model.videoFormat="same";model.maxDimension=0;model.fps=0;model.mute=false};model.invalidate()}
            .onChange(of:model.videoFormat){_,_ in model.invalidate()}.onChange(of:model.maxDimension){_,_ in model.invalidate()}.onChange(of:model.fps){_,_ in model.invalidate()}.onChange(of:model.mute){_,_ in model.invalidate()}
    }
    var header:some View {
        HStack(spacing:12){
            Image(systemName:"arrow.down.right.and.arrow.up.left").font(.system(size:18,weight:.semibold)).foregroundStyle(accent).frame(width:36,height:36).background(accent.opacity(0.10),in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).strokeBorder(.white.opacity(0.6))).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:2){Text("GS Master").font(.system(size:20,weight:.bold,design:.rounded));Text("本地压缩 · 1.3.0").font(.caption).foregroundStyle(.secondary)}
            Spacer()
            Picker("导航",selection:$model.showingHistory){Text("压缩队列").tag(false);Text("历史 \(model.history.count)").tag(true)}.pickerStyle(.segmented).labelsHidden().frame(width:180)
            Button(action:model.addPanel){Label("添加",systemImage:"plus").font(.system(size:14,weight:.semibold)).foregroundStyle(.white).frame(minWidth:72,minHeight:28)}.buttonStyle(ActionButtonStyle(prominent:true)).disabled(model.busy).keyboardShortcut("o")
        }
    }
    var settings:some View {
        VStack(alignment:.leading,spacing:10){
            HStack(spacing:10){
                Text("压缩程度").fontWeight(.medium)
                Picker("压缩程度",selection:$model.preset){Text("无损").tag("lossless");Text("高清").tag("quality");Text("均衡").tag("balanced");Text("极小").tag("small")}.pickerStyle(.segmented).frame(maxWidth:260).labelsHidden()
                Button{model.advanced.toggle() }label:{Label("特殊选项",systemImage:model.advanced ? "chevron.up":"slider.horizontal.3").foregroundStyle(controlInk)}.buttonStyle(.plain).foregroundStyle(accent).padding(.horizontal,8).frame(minHeight:32).background(accent.opacity(0.07),in:RoundedRectangle(cornerRadius:16)).fixedSize(horizontal:true,vertical:false)
                Spacer(minLength:0)
                Picker("视频",selection:$model.videoFormat){Text("原格式").tag("same");Text("MP4").tag("mp4");Text("WebM").tag("webm")}.frame(width:155).disabled(model.preset=="lossless")
            }
            HStack(spacing:14){Toggle("原地覆盖",isOn:$model.overwrite);if model.overwrite{Toggle("覆盖前备份",isOn:$model.backup)};Spacer()}
            HStack(spacing:8){Image(systemName:"folder").foregroundStyle(.secondary).accessibilityHidden(true);Text(model.output).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary).help(model.output);Button(action:model.chooseOutput){Text("更改位置…").foregroundStyle(controlInk).padding(.horizontal,10).frame(minHeight:30).background(accent.opacity(0.07),in:RoundedRectangle(cornerRadius:16))}.buttonStyle(.plain).fixedSize();Spacer(minLength:0)}
            if model.advanced{
                Divider()
                HStack{Picker("最长边",selection:$model.maxDimension){Text("保留尺寸").tag(0);ForEach([1280,1920,2560,3840],id:\.self){Text("\($0) px").tag($0)}};Picker("帧率",selection:$model.fps){Text("保留").tag(0);ForEach([24,30,60],id:\.self){Text("\($0) fps").tag($0)}};Toggle("移除音轨",isOn:$model.mute)}.disabled(model.preset=="lossless")
                Text("图片重编码会移除部分 EXIF；保留透明度。HDR / 透明视频请选无损。转格式保留源文件。").font(.caption).foregroundStyle(.secondary)
            }
        }.font(.system(size:12)).padding(14).modifier(GlassPanel()).disabled(model.busy)
    }
    var queue:some View {
        VStack(spacing:0){
            HStack{Text("文件").frame(maxWidth:.infinity,alignment:.leading);Text("原大小").frame(width:65,alignment:.trailing);Text("压缩后 · 点击预览").frame(width:145,alignment:.trailing);Text("节省").frame(width:62,alignment:.trailing);Text("状态").frame(width:84,alignment:.leading)}.font(.system(size:11,weight:.medium)).foregroundStyle(.secondary).padding(.horizontal,14).padding(.vertical,10)
            Divider()
            if model.rows.isEmpty{
                VStack(spacing:10){Image(systemName:"square.and.arrow.down.on.square").font(.system(size:32,weight:.light)).foregroundStyle(accent);Text("拖入文件、文件夹或压缩包").font(.headline);Text("图片与视频 · ZIP / RAR / 7z").font(.callout).foregroundStyle(.secondary);Button(action:model.addPanel){Label("选择文件",systemImage:"folder.badge.plus").font(.system(size:14,weight:.semibold)).foregroundStyle(.white).frame(minWidth:128,minHeight:30)}.buttonStyle(ActionButtonStyle(prominent:true)).disabled(model.busy).padding(.top,6)}.frame(maxWidth:.infinity,maxHeight:.infinity)
            }else{
                ScrollView{LazyVStack(spacing:0){ForEach($model.rows){$row in
                    HStack(spacing:9){
                        Toggle("选择 \(row.name)",isOn:$row.selected).labelsHidden().disabled(model.busy)
                        Button{model.preview(row)}label:{Thumbnail(path:row.path)}.buttonStyle(.plain).disabled(row.previewPath==nil).accessibilityLabel("预览 \(row.name)")
                        VStack(alignment:.leading,spacing:4){Text(row.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle);Text(row.note.isEmpty ? row.relative : row.note).font(.system(size:11)).foregroundStyle(row.status=="失败" ? .red:.secondary).lineLimit(1)}.frame(maxWidth:.infinity,alignment:.leading).help(row.path+"\n"+row.note)
                        Text(readable(row.size)).monospacedDigit().frame(width:65,alignment:.trailing)
                        Button{model.preview(row)}label:{HStack(spacing:4){Text(row.preview).lineLimit(1).minimumScaleFactor(0.8);if row.previewPath != nil{Image(systemName:"eye").font(.caption)}}.frame(width:145,alignment:.trailing)}.buttonStyle(.plain).foregroundStyle(row.previewPath==nil ? Color.secondary:controlInk).disabled(row.previewPath==nil).help("查看原文件与压缩效果")
                        Text(row.saving).monospacedDigit().foregroundStyle(controlInk).frame(width:62,alignment:.trailing)
                        Text(row.status).foregroundStyle(row.status=="失败" ? .red:.secondary).frame(width:84,alignment:.leading)
                    }.font(.system(size:12)).padding(.horizontal,14).padding(.vertical,9)
                    Divider().padding(.leading,14)
                }}}
            }
        }.frame(minHeight:210,maxHeight:.infinity).background(.background.opacity(0.82),in:RoundedRectangle(cornerRadius:22)).overlay(RoundedRectangle(cornerRadius:22).stroke(targeted ? accent:Color.primary.opacity(0.08),lineWidth:targeted ? 2:1))
            .onDrop(of:[UTType.fileURL.identifier],isTargeted:$targeted){providers in
                guard !model.busy else{return false};let group=DispatchGroup(),lock=NSLock();var urls:[URL]=[]
                for p in providers{group.enter();p.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil){item,_ in
                    let url:URL?;if let data=item as? Data{url=URL(dataRepresentation:data,relativeTo:nil)}else{url=item as? URL};if let u=url{lock.lock();urls.append(u);lock.unlock()};group.leave()
                }}
                group.notify(queue:.main){model.add(urls)};return true
            }
    }
    var selection:some View {
        HStack(spacing:12){Text("已选 \(model.selectedCount) / \(model.rows.count)").foregroundStyle(.secondary);Button("全选"){for i in model.rows.indices{model.rows[i].selected=true}};Button("取消选择"){for i in model.rows.indices{model.rows[i].selected=false}};Button("移除所选"){model.rows.removeAll{$0.selected}};Spacer();if let p=model.latestOutput{Button("打开结果"){NSWorkspace.shared.open(URL(fileURLWithPath:p))}};if let p=model.latestBackup{Button("备份"){NSWorkspace.shared.open(URL(fileURLWithPath:p))}}}.font(.system(size:11)).buttonStyle(.plain).disabled(model.busy)
    }
    var historyPanel:some View {
        VStack(spacing:0){
            HStack{Text("压缩历史").font(.headline);Text("最近 500 条 · 点击在 Finder 中定位").font(.caption).foregroundStyle(.secondary);Spacer();Button("清空记录"){model.clearHistory()}.disabled(model.history.isEmpty || model.busy).help("仅清除历史记录，不删除文件")}.padding(14)
            if !model.historyWarning.isEmpty{Text(model.historyWarning).foregroundStyle(.red).font(.caption).padding(.horizontal)}
            Divider()
            if model.history.isEmpty{VStack(spacing:10){Image(systemName:"clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.secondary);Text("压缩完成后，文件会出现在这里").foregroundStyle(.secondary)}.frame(maxWidth:.infinity,maxHeight:.infinity)}else{
                ScrollView{LazyVStack(spacing:0){ForEach(model.history){entry in
                    Button{model.reveal(entry)}label:{HStack(spacing:12){Image(systemName:"doc.zipper").font(.title2).foregroundStyle(accent).frame(width:34);VStack(alignment:.leading,spacing:4){Text(entry.name).fontWeight(.medium).lineLimit(1);Text(entry.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)}.frame(maxWidth:.infinity,alignment:.leading);VStack(alignment:.trailing,spacing:4){Text(readable(entry.original)+" → "+readable(entry.size)).font(.callout).monospacedDigit();Text(entry.date,format:.dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)};Image(systemName:"arrow.up.forward").foregroundStyle(.secondary)}.padding(14).contentShape(Rectangle())}.buttonStyle(.plain).help("在 Finder 中显示 "+entry.name)
                    Divider().padding(.leading,14)
                }}}
            }
        }.frame(maxHeight:.infinity).background(.background.opacity(0.82),in:RoundedRectangle(cornerRadius:22))
    }
    var footer:some View {
        VStack(spacing:8){if model.busy{ProgressView(value:Double(model.completed),total:Double(max(1,model.total))).tint(accent)}
            HStack(spacing:10){VStack(alignment:.leading,spacing:4){Text(model.message).font(.system(size:12)).lineLimit(2);Text("图片实际试压 · 长视频抽样估算 · 全程离线").font(.system(size:11)).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading)
                if model.busy{Button(action:model.cancel){Text(model.cancelRequested ? "正在取消…":"取消").frame(minWidth:90,minHeight:30)}.controlSize(.large).disabled(model.cancelRequested).buttonStyle(.glass)}else if !model.showingHistory{
                    Button{model.start("estimate")}label:{Label("预估效果",systemImage:"eye").font(.system(size:14,weight:.semibold)).foregroundStyle(model.selectedCount==0 ? Color.secondary:controlInk).frame(minWidth:108,minHeight:30)}.buttonStyle(ActionButtonStyle()).disabled(model.selectedCount==0)
                    Button{model.start("compress")}label:{Label("开始压缩",systemImage:"arrow.down.right.and.arrow.up.left").font(.system(size:14,weight:.semibold)).foregroundStyle(model.selectedCount==0 ? Color.secondary:Color.white).frame(minWidth:108,minHeight:30)}.buttonStyle(ActionButtonStyle(prominent:true)).disabled(model.selectedCount==0)
                }
            }
        }.padding(12).modifier(GlassPanel())
    }
}
