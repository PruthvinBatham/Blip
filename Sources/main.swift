import AppKit

let args = CommandLine.arguments

if args.count >= 3, args[1] == "--sheet" {
    DevRender.contactSheet(to: args[2])
    exit(0)
}
if args.count >= 3, args[1] == "--pixels" {
    DevRender.pixelCheck(to: args[2])
    exit(0)
}
if args.count >= 3, args[1] == "--gif" {
    DevRender.gif(to: args[2], dark: args.count > 3 && args[3] == "dark")
    exit(0)
}
if args.count >= 3, args[1] == "--menubar" {
    DevRender.menuBarMock(to: args[2], dark: args.count > 3 && args[3] == "dark")
    exit(0)
}
if args.count >= 3, args[1] == "--iconset" {
    DevRender.iconSet(to: args[2])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
