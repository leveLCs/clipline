import AppKit

struct AnnotationEditorSettings: Codable {
    static let tools: [AnnotationKind] = [.rectangle, .ellipse, .line, .arrow, .text, .pen, .highlighter, .pixelate, .magnify, .step, .stamp, .spotlight, .note]
    var order = tools
    var hidden: Set<AnnotationKind> = []
    var styles: [AnnotationKind: AnnotationStyle] = [:]
    var lastTool: AnnotationKind = .rectangle
    var largeToolbar = false
    var clickCreatesShapes = true
    private static let key = "annotationEditorSettings"

    init(defaults: UserDefaults = .standard) {
        if let data = defaults.data(forKey: Self.key), let value = try? JSONDecoder().decode(Self.self, from: data) { self = value }
        var seen = Set<AnnotationKind>()
        order = (order + Self.tools).filter { Self.tools.contains($0) && seen.insert($0).inserted }
        hidden.formIntersection(Self.tools)
    }
    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
    func style(for kind: AnnotationKind) -> AnnotationStyle {
        if let style = styles[kind] { return style }
        var style = AnnotationStyle()
        switch kind {
        case .step, .note:
            style.backgroundColor = .red; style.textColor = .white; style.size = 28
        case .highlighter:
            style.color = AnnotationColor(.yellow); style.lineWidth = 24; style.opacity = 0.4
        case .pixelate: style.color = .black
        case .text: style.textColor = .red
        case .bubble: style.backgroundColor = .white; style.textColor = .black
        default: break
        }
        return style
    }
    static func crop(size: CGSize, in bounds: CGRect) -> CGRect {
        let scale = min(1, bounds.width / max(1, size.width), bounds.height / max(1, size.height))
        let width = floor(size.width * scale), height = floor(size.height * scale)
        return CGRect(x: floor(bounds.midX - width / 2), y: floor(bounds.midY - height / 2), width: width, height: height)
    }
    static func crop(ratio: CGFloat, in bounds: CGRect) -> CGRect {
        let width = min(bounds.width, bounds.height * ratio)
        return crop(size: CGSize(width: width, height: width / ratio), in: bounds)
    }
}

extension AnnotationKind {
    var title: String {
        switch self {
        case .hand: return L("Hand tool")
        case .rectangle: return L("Rectangle")
        case .ellipse: return L("Ellipse")
        case .line: return L("Line")
        case .arrow: return L("Arrow")
        case .text: return L("Text")
        case .bubble: return L("Bubble text")
        case .pen: return L("Pen")
        case .highlighter: return L("Highlighter")
        case .pixelate: return L("Pixelate")
        case .magnify: return L("Magnifier")
        case .step: return L("Step")
        case .stamp: return L("Stamp")
        case .spotlight: return L("Spotlight")
        case .note: return L("Note")
        case .eraser: return L("Eraser")
        }
    }
    var symbol: String {
        switch self {
        case .hand: return "hand.draw"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        case .bubble: return "text.bubble"
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .pixelate: return "square.grid.3x3.fill"
        case .magnify: return "plus.magnifyingglass"
        case .step: return "1.circle"
        case .stamp: return "face.smiling"
        case .spotlight: return "flashlight.on.fill"
        case .note: return "note.text"
        case .eraser: return "eraser"
        }
    }
}
