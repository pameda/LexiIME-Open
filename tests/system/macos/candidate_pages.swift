import AppKit
@main struct CandidatePagesProbe {
    static func main() throws {
        let data=FileHandle.standardInput.readDataToEndOfFile()
        guard data.count<=65536,
              let request=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let texts=request["texts"] as? [String], texts.count<=36 else {exit(2)}
        let size=max(14,min(24,request["fontSize"] as? Int ?? 17))
        let pages=CandidateLayout.pages(texts:texts,preferredCount:request["preferredCount"] as? Int ?? 5,fontSize:size)
        let result:[String:Any]=["pages":pages.map{[$0.lowerBound,$0.upperBound]},"widths":texts.map{Double(CandidateLayout.cellWidth($0,fontSize:size))}]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:result))
    }
}
