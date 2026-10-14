import SwiftUI
import AppKit
import UniformTypeIdentifiers

class AppDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
    let model=CompressorModel();var window:NSWindow!
    func applicationDidFinishLaunching(_ notification:Notification){
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:880,height:660),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.titlebarAppearsTransparent=true;window.title="GS Master · 本地压缩 1.5.0";window.delegate=self;window.contentView=NSHostingView(rootView:MainView(model:model));window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        let menu=NSMenu(),appItem=NSMenuItem(),appMenu=NSMenu();appMenu.addItem(withTitle:"关于 GS Master",action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"");appMenu.addItem(NSMenuItem.separator());appMenu.addItem(withTitle:"退出 GS Master",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");appItem.submenu=appMenu;menu.addItem(appItem);NSApp.mainMenu=menu
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply{
        if model.busy{model.cancel();DispatchQueue.main.asyncAfter(deadline:.now()+0.3){self.waitForExit()};return .terminateLater}
        try? FileManager.default.removeItem(at:model.cache);return .terminateNow
    }
    func waitForExit(){if model.busy{DispatchQueue.main.asyncAfter(deadline:.now()+0.3){self.waitForExit()}}else{try? FileManager.default.removeItem(at:model.cache);NSApp.reply(toApplicationShouldTerminate:true)}}
}
