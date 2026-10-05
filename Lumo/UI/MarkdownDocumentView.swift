import SwiftUI

/// Renders Claude Markdown as readable blocks instead of one dense Text view.
/// Inline Markdown (bold, italic, code, links) is preserved while paragraphs,
/// lists and headings receive deliberate vertical breathing room.
struct MarkdownDocumentView: View {
    let source: String
    var fontSize: CGFloat = 14.5

    private var blocks: [String] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        var result:[String] = []; var current:[String] = []
        func flush() { let value=current.joined(separator:"\n").trimmingCharacters(in:.whitespacesAndNewlines); if !value.isEmpty { result.append(value) }; current=[] }
        for line in normalized.components(separatedBy:"\n") {
            if line.trimmingCharacters(in:.whitespaces).isEmpty { flush() }
            else { current.append(line) }
        }
        flush(); return result
    }

    var body: some View {
        VStack(alignment:.leading, spacing:12) {
            ForEach(Array(blocks.enumerated()), id:\.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
    }

    @ViewBuilder private func blockView(_ block:String) -> some View {
        if block.hasPrefix("```") {
            Text(block.replacingOccurrences(of:"```",with:""))
                .font(.system(size:fontSize-1, design:.monospaced))
                .textSelection(.enabled).padding(10).frame(maxWidth:.infinity,alignment:.leading)
                .background(Color.white.opacity(0.06),in:RoundedRectangle(cornerRadius:10))
        } else if block.hasPrefix("### ") {
            markdown(String(block.dropFirst(4))).font(.system(size:fontSize+1,weight:.semibold))
        } else if block.hasPrefix("## ") {
            markdown(String(block.dropFirst(3))).font(.system(size:fontSize+2,weight:.bold))
        } else if block.hasPrefix("# ") {
            markdown(String(block.dropFirst(2))).font(.system(size:fontSize+3,weight:.bold))
        } else {
            markdown(block).font(.system(size:fontSize)).lineSpacing(4)
        }
    }

    private func markdown(_ value:String) -> Text {
        if let attributed = try? AttributedString(markdown:value, options:.init(interpretedSyntax:.full, failurePolicy:.returnPartiallyParsedIfPossible)) { return Text(attributed) }
        return Text(value)
    }
}
