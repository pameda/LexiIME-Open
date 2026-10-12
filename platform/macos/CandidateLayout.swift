import AppKit

// Partition all candidates once by their measured word width. A long candidate
// gets its own page; page keys and number keys use these same ranges.
enum CandidateLayout {
    static let spacing: CGFloat = 6
    static let maximumRowWidth: CGFloat = 624
    static func textWidth(_ text: String, fontSize: Int) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font:NSFont.systemFont(ofSize:CGFloat(fontSize),weight:.medium)]).width)
    }
    static func isLong(_ text: String, fontSize: Int) -> Bool {
        textWidth(text,fontSize:fontSize)>96
    }
    static func cellWidth(_ text: String, fontSize: Int) -> CGFloat {
        if isLong(text,fontSize:fontSize) {return min(480,max(260,textWidth(text,fontSize:fontSize)+40))}
        return max(104,textWidth(text,fontSize:fontSize)+28)
    }
    static func pages(texts: [String], preferredCount: Int, fontSize: Int, maximumWidth: CGFloat=maximumRowWidth) -> [Range<Int>] {
        let count=max(1,min(9,preferredCount)),limit=max(104,maximumWidth)
        var result:[Range<Int>]=[],start=0,used:CGFloat=0
        for i in texts.indices {
            let long=isLong(texts[i],fontSize:fontSize)
            let width=cellWidth(texts[i],fontSize:fontSize)
            if i>start && (long || i-start>=count || used+spacing+width>limit) {
                result.append(start..<i);start=i;used=0
            }
            used += (i>start ? spacing:0)+width
            if long {result.append(i..<(i+1));start=i+1;used=0}
        }
        if start<texts.count {result.append(start..<texts.count)}
        return result
    }
    static func range(pages: [Range<Int>], selected: Int) -> Range<Int> {
        pages.first(where:{$0.contains(selected)}) ?? pages.first ?? 0..<0
    }
    static func next(pages: [Range<Int>], selected: Int, direction: Int) -> Int {
        guard !pages.isEmpty else {return 0}
        let current=pages.firstIndex(where:{$0.contains(selected)}) ?? 0
        return pages[max(0,min(pages.count-1,current+direction))].lowerBound
    }
    static func gloss(_ full: String, single: Bool) -> String {
        let clean=full.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
        let limit=single ? 64:32
        return clean.count>limit ? String(clean.prefix(limit-1))+"…":clean
    }
}
