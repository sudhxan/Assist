import SwiftUI

enum Palette {
    static let mint = Color(red: 0.37, green: 0.95, blue: 0.76)
    static let sky = Color(red: 0.31, green: 0.78, blue: 0.99)
    static let violet = Color(red: 0.58, green: 0.47, blue: 1.0)
    static let pink = Color(red: 1.0, green: 0.50, blue: 0.72)
    static let aurora: [Color] = [mint, sky, violet, pink, mint]
    static let highlight = Color(red: 0.66, green: 0.98, blue: 0.87)

    static var auroraLinear: LinearGradient {
        LinearGradient(colors: [mint, sky, violet], startPoint: .leading, endPoint: .trailing)
    }

    static func speaker(_ speaker: Speaker) -> Color {
        switch speaker {
        case .me: mint
        case .them: sky
        case .room: violet
        }
    }
}

struct IconButton: View {
    let symbol: String
    var help = ""
    var size: CGFloat = 12
    var active = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(active ? AnyShapeStyle(Palette.auroraLinear) : AnyShapeStyle(.white.opacity(hovering ? 0.95 : 0.6)))
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 0.5))
    }
}

struct PanelBackground: View {
    var glowing = false

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.white.opacity(0.055))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(glowing ? AnyShapeStyle(Palette.auroraLinear.opacity(0.6)) : AnyShapeStyle(.white.opacity(0.07)), lineWidth: glowing ? 1 : 0.5)
            )
    }
}

struct ActionChip: View {
    let title: String
    let symbol: String
    var shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.auroraLinear)
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(.white.opacity(hovering ? 0.13 : 0.07)))
            .overlay(Capsule().stroke(hovering ? AnyShapeStyle(Palette.auroraLinear) : AnyShapeStyle(.white.opacity(0.08)), lineWidth: hovering ? 1 : 0.5))
            .scaleEffect(hovering ? 1.04 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hovering)
    }
}

struct NoticeBanner: View {
    @Environment(AppModel.self) private var model
    let notice: Notice

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(notice.isError ? Color.orange : Palette.sky)
            Text(notice.text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let action = notice.action {
                Button(action == .apiKeySettings || action == .languageSettings ? "Settings" : "Open Settings") {
                    switch action {
                    case .apiKeySettings: model.openSettings(.ai)
                    case .languageSettings: model.openSettings(.general)
                    default: Permissions.open(action)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.mint)
            }
            IconButton(symbol: "xmark", size: 9) { model.notice = nil }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill((notice.isError ? Color.orange : Palette.sky).opacity(0.13)))
    }
}

/// Lightweight Markdown: bullets, numbered lists, headings, code fences, and inline styles.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(MarkdownLite.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let line):
                    Text(MarkdownLite.inline(line))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                case .bullet(let line, let depth):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•").foregroundStyle(Palette.auroraLinear).fontWeight(.black)
                        Text(MarkdownLite.inline(line))
                    }
                    .padding(.leading, CGFloat(depth) * 12)
                case .numbered(let number, let line):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(number).").foregroundStyle(Palette.mint).monospacedDigit().fontWeight(.semibold)
                        Text(MarkdownLite.inline(line))
                    }
                case .paragraph(let line):
                    Text(MarkdownLite.inline(line))
                case .code(let code):
                    Text(code)
                        .font(.system(size: 11.5, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.07)))
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.white.opacity(0.92))
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
}

enum MarkdownLite {
    enum Block {
        case heading(String)
        case bullet(String, Int)
        case numbered(String, String)
        case paragraph(String)
        case code(String)
    }

    static func blocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var code: [String]?
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(raw)
                continue
            }
            guard !line.isEmpty else { continue }
            let indent = raw.prefix(while: { $0 == " " || $0 == "\t" }).count
            if line.hasPrefix("#") {
                blocks.append(.heading(String(line.drop(while: { $0 == "#" })).trimmed))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                blocks.append(.bullet(String(line.dropFirst(2)), min(indent / 2, 3)))
            } else if let numbered = numberedItem(line) {
                blocks.append(.numbered(numbered.0, numbered.1))
            } else {
                blocks.append(.paragraph(line))
            }
        }
        if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
        return blocks
    }

    private static func numberedItem(_ line: String) -> (String, String)? {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let marker = rest.first, marker == "." || marker == ")", rest.dropFirst().first == " " else { return nil }
        return (String(digits), String(rest.dropFirst(2)))
    }

    static func inline(_ text: String) -> AttributedString {
        var attributed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            attributed[run.range].foregroundColor = Palette.highlight
        }
        return attributed
    }

    /// First meaningful line, keeping inline Markdown.
    static func firstLine(_ text: String) -> String {
        for block in blocks(text) {
            switch block {
            case .heading(let s), .bullet(let s, _), .paragraph(let s), .numbered(_, let s): return s
            case .code(let s): return s.components(separatedBy: "\n").first ?? s
            }
        }
        return ""
    }
}
