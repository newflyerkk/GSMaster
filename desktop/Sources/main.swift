import AppKit
if CommandLine.arguments.count>1,CommandLine.arguments[1].hasPrefix("--") {
    do{try imageCommand(CommandLine.arguments)}catch{fputs(error.localizedDescription+"\n",stderr);exit(1)}
}else{
    let app=NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate=AppDelegate();app.delegate=delegate;app.run()
}
