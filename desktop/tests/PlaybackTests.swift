import AppKit
import SwiftUI
import AVKit
@main struct PlaybackTests {
 static func main() throws {
  NSApplication.shared.setActivationPolicy(.prohibited)
  let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("desktop/build")
  let host=NSHostingView(rootView:VideoPreview(url:root.appendingPathComponent("playback.mp4")))
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:300),styleMask:.borderless,backing:.buffered,defer:false)
  window.contentView=host;host.layoutSubtreeIfNeeded()
  func playerView(_ view:NSView)->AVPlayerView?{if let p=view as? AVPlayerView{return p};return view.subviews.compactMap{playerView($0)}.first}
  RunLoop.main.run(until:Date().addingTimeInterval(1))
  guard let player=playerView(host)?.player else{fatalError("No embedded player")}
  precondition(player.status == .readyToPlay && player.isMuted)
  let before=player.currentTime().seconds
  RunLoop.main.run(until:Date().addingTimeInterval(0.3))
  precondition(player.currentTime().seconds>before,"Video must advance in embedded preview")
  player.pause()
  let gifHost=NSHostingView(rootView:GIFImageView(url:root.appendingPathComponent("playback.gif"),playing:true))
  window.contentView=gifHost;gifHost.layoutSubtreeIfNeeded()
  RunLoop.main.run(until:Date().addingTimeInterval(0.1))
  func imageView(_ view:NSView)->NSImageView?{if let p=view as? NSImageView{return p};return view.subviews.compactMap{imageView($0)}.first}
  guard let image=imageView(gifHost) else{fatalError("No embedded GIF")}
  precondition(image.animates && image.image != nil)
  let frames=image.image!.representations.compactMap{($0 as? NSBitmapImageRep)?.value(forProperty:.frameCount) as? Int}.max() ?? 0
  precondition(frames>1,"GIF must preserve animation frames")
  print("PASS: embedded video advances, muted by default; GIF animation enabled with multiple frames")
 }
}
