import Foundation

enum Typing {
    static func isCalculation(_ buffer: String) -> Bool {
        guard buffer.hasPrefix("v"), let second=buffer.dropFirst().first else {return false}
        return "0123456789.+-(".contains(second)
    }
    static func acceptsToolCharacter(_ text: String, buffer: String, enabled: Bool) -> Bool {
        enabled && (buffer == "v" || isCalculation(buffer)) && text.count == 1 && "0123456789.+-*/()".contains(text)
    }
    static func pageRange(count: Int, selected: Int, size: Int) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let width = max(1, min(9, size))
        let start = max(0, min(count-1, selected)) / width * width
        return start..<min(count, start+width)
    }
    static func nextPage(count: Int, selected: Int, size: Int, direction: Int) -> Int {
        guard count > 0 else { return 0 }
        let width = max(1, min(9, size))
        let page = max(0, min(count-1, selected)) / width
        return max(0, min((count-1)/width, page+direction)) * width
    }
    static func punctuation(_ text: String) -> String? {
        [",":"，", ".":"。", "?":"？", "!":"！", ":":"：", ";":"；",
         "(":"（", ")":"）", "[":"【", "]":"】", "\\":"、"][text]
    }
    static func speechLocale(_ value: String?) -> String {
        ["zh-CN","en-US","ja-JP","es-ES"].contains(value ?? "") ? value! : "zh-CN"
    }
}
