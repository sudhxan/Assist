import CoreGraphics
import Foundation

/// A run of recognized text and its box, in pixels with the origin at the top left.
struct OCRItem: Equatable, Sendable {
    var text: String
    var box: CGRect
}

/// One line as Vision read it: its box, and its text (split off from a leading line number).
struct OCRLine: Sendable {
    var box: CGRect
    var items: [OCRItem]
}

/// Rebuilds readable text from OCR boxes, keeping the structure a coding question depends on.
///
/// Sorting boxes top to bottom (what Vision's order amounts to) interleaves side-by-side panes
/// line by line, so a problem statement on the left and its starter code on the right come out
/// shuffled together, and every line loses its indentation. Here:
/// - **Panes are read one at a time.** A recursive XY-cut (Nagy & Seth, 1984) splits the page
///   at wide vertical gutters and at blank horizontal bands. A vertical gap whose two sides
///   share their baselines is a table or a form, not two columns, so it stays as rows.
/// - **Lines keep their indentation.** Each line is placed on a character grid relative to its
///   pane's left edge (the `pdftotext -layout` idea), which is what makes Python readable.
/// - **Editor line numbers are dropped**, so they aren't mistaken for code.
enum ScreenLayout {
    /// Marks the boundary between two panes in the output.
    static let paneBreak = "\n-----\n"

    static func render(_ raw: [OCRItem]) -> String {
        let items = raw.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && $0.box.width > 0 && $0.box.height > 0 }
        guard let left = items.map(\.box.minX).min() else { return "" }
        let metrics = Metrics(items)
        return layout(items, baseX: left, metrics)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .newlines)
    }

    struct Metrics {
        /// Median text height and the width of one character, in pixels.
        var lineHeight: CGFloat
        var charWidth: CGFloat

        init(_ items: [OCRItem]) {
            lineHeight = max(1, Self.median(items.map(\.box.height)))
            let widths = items.filter { $0.text.count >= 4 }.map { $0.box.width / CGFloat($0.text.count) }
            charWidth = max(1, widths.isEmpty ? lineHeight * 0.5 : Self.median(widths))
        }

        static func median(_ values: [CGFloat]) -> CGFloat {
            guard !values.isEmpty else { return 0 }
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
    }

    /// Combines two OCR passes over the same screen. Lines from the two passes that cover the
    /// same region are grouped, and the pass that read more text there wins the region; a
    /// line only one pass found is kept as is.
    static func merge(_ first: [OCRLine], _ second: [OCRLine]) -> [OCRItem] {
        let lines = first + second
        var parent = Array(lines.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        for i in first.indices {
            for j in first.count..<lines.count where covers(lines[i].box, lines[j].box) {
                parent[root(i)] = root(j)
            }
        }
        var groups: [Int: [Int]] = [:]
        for index in lines.indices { groups[root(index), default: []].append(index) }
        var items: [OCRItem] = []
        for members in groups.values {
            let (a, b) = (members.filter { $0 < first.count }, members.filter { $0 >= first.count })
            func characters(_ set: [Int]) -> Int {
                set.reduce(0) { $0 + lines[$1].items.reduce(0) { $0 + $1.text.filter { !$0.isWhitespace }.count } }
            }
            // A tie goes to the pass that read the region as fewer, whole lines.
            let (ca, cb) = (characters(a), characters(b))
            let winner = cb > ca || (cb == ca && b.count < a.count) ? b : a
            items += winner.flatMap { lines[$0].items }
        }
        return items
    }

    /// Two boxes cover the same text when they overlap by half of the smaller one.
    private static func covers(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = a.intersection(b)
        guard !overlap.isNull else { return false }
        return overlap.width * overlap.height >= 0.5 * min(a.width * a.height, b.width * b.height)
    }

    // MARK: XY-cut

    private static func layout(_ items: [OCRItem], baseX: CGFloat, _ m: Metrics) -> String {
        var items = items
        var baseX = baseX
        var rows = self.rows(items)
        // An editor's gutter is found per pane, before blank lines split the code into bands.
        if let stripped = withoutLineNumbers(rows) {
            rows = stripped
            items = stripped.flatMap { $0 }
            guard let left = items.map(\.box.minX).min() else { return "" }
            baseX = left
        }
        if rows.count >= 2, let x = columnCut(items, rows: rows, m) {
            let left = items.filter { $0.box.midX < x }
            let right = items.filter { $0.box.midX >= x }
            let parts = [layout(left, baseX: left.map(\.box.minX).min()!, m),
                         layout(right, baseX: right.map(\.box.minX).min()!, m)]
            return parts.filter { !$0.isEmpty }.joined(separator: paneBreak)
        }
        // Split at blank bands so each band can find its own columns. Bands keep the pane's
        // left edge, so indentation stays consistent across blank lines in code.
        var bands: [[[OCRItem]]] = [[rows[0]]]
        var gaps: [CGFloat] = []
        for (above, row) in zip(rows, rows.dropFirst()) {
            let gap = top(row) - bottom(above)
            if gap >= m.lineHeight {
                bands.append([row])
                gaps.append(gap)
            } else {
                bands[bands.count - 1].append(row)
            }
        }
        guard bands.count > 1 else { return lines(rows, baseX: baseX, m) }
        var text = ""
        for (index, band) in bands.enumerated() {
            let part = layout(band.flatMap { $0 }, baseX: baseX, m)
            guard !part.isEmpty else { continue }
            if !text.isEmpty { text += gaps[index - 1] >= 1.4 * m.lineHeight ? "\n\n" : "\n" }
            text += part
        }
        return text
    }

    /// The widest vertical gutter that separates two panes, if there is one.
    private static func columnCut(_ items: [OCRItem], rows: [[OCRItem]], _ m: Metrics) -> CGFloat? {
        let minimumGap = max(4 * m.charWidth, 1.5 * m.lineHeight)
        let spans = items.map { ($0.box.minX, $0.box.maxX) }.sorted { $0.0 < $1.0 }
        var reach = spans[0].1
        var best: (gap: CGFloat, x: CGFloat)?
        for span in spans.dropFirst() {
            if span.0 - reach >= minimumGap, span.0 - reach > (best?.gap ?? 0) {
                let x = (span.0 + reach) / 2
                if separatesPanes(items, at: x, m) { best = (span.0 - reach, x) }
            }
            reach = max(reach, span.1)
        }
        return best?.x
    }

    /// Two panes run independently; a table's columns share their rows. Counted over the rows
    /// of both sides, so a sparse pane (an editor with a few lines of starter code) can't look
    /// like a table just because its header and a couple of lines happen to line up.
    private static func separatesPanes(_ items: [OCRItem], at x: CGFloat, _ m: Metrics) -> Bool {
        let left = rows(items.filter { $0.box.midX < x }).map(center)
        let right = rows(items.filter { $0.box.midX >= x }).map(center)
        guard !left.isEmpty, !right.isEmpty else { return false }
        let tolerance = 0.2 * m.lineHeight
        func aligned(_ these: [CGFloat], _ those: [CGFloat]) -> Int {
            these.filter { y in those.contains { abs($0 - y) <= tolerance } }.count
        }
        let shared = aligned(left, right) + aligned(right, left)
        return Double(shared) / Double(left.count + right.count) < 0.5
    }

    private static func center(_ row: [OCRItem]) -> CGFloat {
        (top(row) + bottom(row)) / 2
    }

    // MARK: Rows and lines

    /// Items grouped into visual rows, top to bottom.
    private static func rows(_ items: [OCRItem]) -> [[OCRItem]] {
        var rows: [[OCRItem]] = []
        for item in items.sorted(by: { $0.box.midY < $1.box.midY }) {
            if let last = rows.last, let anchor = last.first,
               overlap(anchor.box, item.box) >= 0.5 * min(anchor.box.height, item.box.height) {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX } }
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
    }

    private static func top(_ row: [OCRItem]) -> CGFloat { row.map(\.box.minY).min() ?? 0 }
    private static func bottom(_ row: [OCRItem]) -> CGFloat { row.map(\.box.maxY).max() ?? 0 }

    /// Rows on a character grid: indentation from the pane's left edge, and short runs of
    /// spaces between pieces of the same row.
    private static func lines(_ rows: [[OCRItem]], baseX: CGFloat, _ m: Metrics) -> String {
        rows.map { row in
            var line = ""
            var cursor = baseX
            for (index, item) in row.enumerated() {
                let columns = Int(((item.box.minX - cursor) / m.charWidth).rounded())
                let spaces = index == 0 ? min(max(columns, 0), 60) : min(max(columns, 1), 8)
                line += String(repeating: " ", count: spaces) + item.text.trimmingCharacters(in: .whitespaces)
                cursor = item.box.maxX
            }
            return line
        }.joined(separator: "\n")
    }

    /// Drops an editor's line-number gutter: a column of increasing numbers, right-aligned,
    /// to the left of the code. OCR often misses single digits, so a partial gutter counts.
    /// Returns nil when there's no gutter.
    private static func withoutLineNumbers(_ rows: [[OCRItem]]) -> [[OCRItem]]? {
        let numbers = rows.map { row in row.first.flatMap { Int($0.text.trimmingCharacters(in: .whitespaces)) } }
        let present = numbers.compactMap { $0 }
        guard present.count >= 3 else { return nil }
        let pairs = Array(zip(present, present.dropFirst()))
        guard pairs.allSatisfy({ $1 > $0 }), pairs.filter({ $1 == $0 + 1 }).count * 2 >= pairs.count else { return nil }
        let gutter = rows.indices.filter { numbers[$0] != nil }.map { rows[$0][0].box }
        guard let low = gutter.map(\.maxX).min(), let high = gutter.map(\.maxX).max(),
              high - low <= Metrics.median(gutter.map(\.height)) else { return nil }
        // Within the gutter's span, the text starts to the right of the numbers.
        let numbered = rows.indices.filter { numbers[$0] != nil }
        let starts = numbered[0]...numbered[numbered.count - 1]
        let textStarts = starts.compactMap { index -> CGFloat? in
            let row = numbers[index] != nil ? rows[index].dropFirst() : rows[index][...]
            return row.first?.box.minX
        }
        guard !textStarts.isEmpty, Double(textStarts.filter { $0 > high }.count) >= 0.8 * Double(textStarts.count) else { return nil }
        return rows.indices.compactMap { index in
            let row = numbers[index] != nil ? Array(rows[index].dropFirst()) : rows[index]
            return row.isEmpty ? nil : row
        }
    }
}
