import ApplicationServices
import AppKit

// usage: ax dump <pid> | ax press <pid> <label> [nth] [action] | ax winid <pid>
setvbuf(stdout, nil, _IONBF, 0)
let a = CommandLine.arguments
guard a.count >= 3, let pidInt = Int32(a[2]) else { print("usage"); exit(2) }
let app = AXUIElementCreateApplication(pidInt)

func str(_ el: AXUIElement, _ name: String) -> String {
    guard let raw = attr(el, name), CFGetTypeID(raw) == CFStringGetTypeID() else { return "" }
    return raw as! String
}
func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}
func frame(_ el: AXUIElement) -> String {
    var p = CGPoint.zero, s = CGSize.zero
    if let v = attr(el, kAXPositionAttribute) { if CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgPoint, &p) } }
    if let v = attr(el, kAXSizeAttribute) { if CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgSize, &s) } }
    func n(_ d: CGFloat) -> String { d.isFinite && abs(d) < 1e9 ? String(Int(d)) : "?" }
    return "\(n(p.x + off.x)),\(n(p.y + off.y)) \(n(s.width))x\(n(s.height))"
}
// Coordinates are normalised as if the window sat at (0,100), matching the first capture pass.
var off = CGPoint.zero
func label(_ el: AXUIElement) -> (String, String, String, String) {
    let t = str(el, kAXTitleAttribute)
    let d = str(el, kAXDescriptionAttribute)
    let i = str(el, kAXIdentifierAttribute)
    var v = ""
    if let raw = attr(el, kAXValueAttribute) {
        let tid = CFGetTypeID(raw)
        if tid == CFStringGetTypeID() { v = raw as! String }
        else if tid == CFNumberGetTypeID() || tid == CFBooleanGetTypeID() { v = (raw as! NSNumber).stringValue }
    }
    return (t, d, i, v)
}
func clean(_ s: String) -> String { s.replacingOccurrences(of: "\n", with: " ⏎ ") }

guard let windows = attr(app, kAXWindowsAttribute) as? [AXUIElement], !windows.isEmpty else {
    print("NO_WINDOWS"); exit(1)
}

if let v = attr(windows[0], kAXPositionAttribute) {
    var wp = CGPoint.zero
    if CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgPoint, &wp) }
    off = CGPoint(x: -wp.x, y: 100 - wp.y)
}
var matches: [AXUIElement] = []
func walk(_ el: AXUIElement, _ depth: Int, _ visit: (AXUIElement, Int) -> Void) {
    if depth > 40 { return }
    visit(el, depth)
    if let raw = attr(el, kAXChildrenAttribute), CFGetTypeID(raw) == CFArrayGetTypeID() {
        for k in (raw as! [AnyObject]) where CFGetTypeID(k) == AXUIElementGetTypeID() {
            walk(k as! AXUIElement, depth + 1, visit)
        }
    }
}

switch a[1] {
case "dump":
    for w in windows {
        walk(w, 0) { el, depth in
            let role = str(el, kAXRoleAttribute)
            let (t, d, i, v) = label(el)
            var parts: [String] = []
            if !t.isEmpty { parts.append("t='\(clean(t))'") }
            if !d.isEmpty { parts.append("d='\(clean(d))'") }
            if !i.isEmpty { parts.append("id='\(i)'") }
            if !v.isEmpty { parts.append("v='\(clean(String(v.prefix(200))))'") }
            print("\(String(repeating: " ", count: depth))\(role) \(parts.joined(separator: " ")) | \(frame(el))")
        }
    }
case "press":
    guard a.count >= 4 else { print("need label"); exit(2) }
    let want = a[3]
    let nth = a.count > 4 ? Int(a[4]) ?? 0 : 0
    let action = a.count > 5 ? a[5] : (kAXPressAction as String)
    for w in windows {
        walk(w, 0) { el, _ in
            let (t, d, i, v) = label(el)
            if [t, d, i, v].contains(where: { $0 == want || clean($0) == want }) { matches.append(el) }
        }
    }
    if matches.isEmpty {
        for w in windows {
            walk(w, 0) { el, _ in
                let (t, d, i, v) = label(el)
                if [t, d, i, v].contains(where: { !$0.isEmpty && clean($0).hasPrefix(want) }) { matches.append(el) }
            }
        }
    }
    // Never dismiss tip cards by accident: their close button shares the "Close" label.
    if want != "xmark.circle.fill" { matches.removeAll { str($0, kAXIdentifierAttribute) == "xmark.circle.fill" } }
    guard nth < matches.count else { print("NOT_FOUND '\(want)' (matches=\(matches.count))"); exit(1) }
    let err = AXUIElementPerformAction(matches[nth], action as CFString)
    print("press '\(want)'[\(nth)/\(matches.count)] @ \(frame(matches[nth])) -> \(err.rawValue)")
case "scroll":
    // ax scroll <pid> down|up — page-scroll via the last element that supports the AX scroll action
    let act = (a.count > 3 && a[3] == "up") ? "AXScrollUpByPage" : "AXScrollDownByPage"
    var last: AXUIElement?
    for w in windows { walk(w, 0) { el, _ in
        var names: CFArray?
        if AXUIElementCopyActionNames(el, &names) == .success, let n = names as? [String], n.contains(act) { last = el }
    } }
    guard let target = last else { print("NO_SCROLLABLE"); exit(1) }
    print("scroll \(act) -> \(AXUIElementPerformAction(target, act as CFString).rawValue)")
case "cancelmenu":
    var n = 0
    for w in windows { walk(w, 0) { el, _ in
        if n == 0, str(el, kAXRoleAttribute) == "AXMenu" {
            AXUIElementPerformAction(el, kAXCancelAction as CFString); n += 1
        }
    } }
    print("cancelmenu \(n)")
case "pick":
    // ax pick <pid> <popupLabel> <menuItemTitle> [nth]
    guard a.count >= 5 else { print("need popup + item"); exit(2) }
    let nth = a.count > 5 ? Int(a[5]) ?? 0 : 0
    var pops: [AXUIElement] = []
    for w in windows { walk(w, 0) { el, _ in
        let (t, d, i, v) = label(el)
        if [t, d, i, v].contains(where: { !$0.isEmpty && clean($0).hasPrefix(a[3]) }) { pops.append(el) }
    } }
    guard nth < pops.count else { print("NOT_FOUND popup '\(a[3])'"); exit(1) }
    AXUIElementPerformAction(pops[nth], kAXPressAction as CFString)
    var done = false
    for _ in 0..<20 where !done {
        usleep(150_000)
        let ws = attr(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        for w in ws { walk(w, 0) { el, _ in
            if done { return }
            let role = str(el, kAXRoleAttribute)
            let (t, _, i, _) = label(el)
            if role == "AXMenuItem" && (t == a[4] || i == a[4]) {
                let err = AXUIElementPerformAction(el, kAXPressAction as CFString)
                print("pick '\(a[3])' -> '\(a[4])' -> \(err.rawValue)"); done = true
            }
        } }
    }
    if !done { print("NOT_FOUND item '\(a[4])'"); exit(1) }
default:
    print("unknown"); exit(2)
}
