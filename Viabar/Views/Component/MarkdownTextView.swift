import SwiftUI

struct MarkdownTextView: View {
    let markdown: String

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(markdown)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            inlineText(text)
                .font(headingFont(level: level))
                .padding(.top, level == 1 ? 4 : 0)
        case let .unordered(text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                inlineText(text)
            }
            .padding(.leading, 4)
        case let .ordered(number, text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .foregroundStyle(.secondary)
                inlineText(text)
            }
            .padding(.leading, 4)
        case let .quote(text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 3)
                inlineText(text)
                    .foregroundStyle(.secondary)
            }
        case let .code(text):
            Text(verbatim: text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        case let .paragraph(text):
            inlineText(text)
        }
    }

    private func inlineText(_ source: String) -> Text {
        guard let value = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return Text(verbatim: source)
        }
        return Text(value)
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: .title2.bold()
        case 2: .headline
        default: .subheadline.bold()
        }
    }
}

private enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case unordered(text: String)
    case ordered(number: String, text: String)
    case quote(text: String)
    case code(String)
    case paragraph(String)
}

private enum MarkdownBlockParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var isInsideCodeBlock = false

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
            paragraphLines.removeAll()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if isInsideCodeBlock {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                } else {
                    flushParagraph()
                }
                isInsideCodeBlock.toggle()
                continue
            }

            if isInsideCodeBlock {
                codeLines.append(rawLine)
                continue
            }

            if line.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = heading(from: line) {
                flushParagraph()
                blocks.append(heading)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                blocks.append(.unordered(text: String(line.dropFirst(2))))
            } else if let ordered = orderedItem(from: line) {
                flushParagraph()
                blocks.append(ordered)
            } else if line.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(text: String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else {
                paragraphLines.append(line)
            }
        }

        if isInsideCodeBlock {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks
    }

    private static func heading(from line: String) -> MarkdownBlock? {
        let markerCount = line.prefix(while: { $0 == "#" }).count
        guard (1...3).contains(markerCount) else { return nil }
        let remainder = line.dropFirst(markerCount)
        guard remainder.first == " " else { return nil }
        return .heading(
            level: markerCount,
            text: remainder.trimmingCharacters(in: .whitespaces)
        )
    }

    private static func orderedItem(from line: String) -> MarkdownBlock? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let number = String(line[..<dotIndex])
        guard !number.isEmpty,
              number.allSatisfy(\.isNumber),
              line.index(after: dotIndex) < line.endIndex,
              line[line.index(after: dotIndex)] == " " else {
            return nil
        }
        let textStart = line.index(dotIndex, offsetBy: 2)
        return .ordered(number: number, text: String(line[textStart...]))
    }
}
