import AppKit

// Original compact keyboard mark: six keys and a space bar.
// Transparent key cutouts stay crisp under native menu-bar template tinting.
func mark() -> NSBezierPath {
    let p=NSBezierPath(roundedRect:NSRect(x:1,y:4,width:18,height:13),xRadius:3,yRadius:3)
    for y in [12.0,8.9] {
        for x in [4.0,8.9,13.8] {
            p.append(NSBezierPath(roundedRect:NSRect(x:x,y:y,width:2.2,height:2.0),xRadius:0.55,yRadius:0.55))
        }
    }
    p.append(NSBezierPath(roundedRect:NSRect(x:5.5,y:6,width:9,height:1.6),xRadius:0.7,yRadius:0.7))
    p.windingRule = .evenOdd
    return p
}
func cgPath(_ path:NSBezierPath) -> CGPath {
    let result=CGMutablePath()
    var points=[NSPoint](repeating:.zero,count:3)
    for i in 0..<path.elementCount {
        switch path.element(at:i,associatedPoints:&points) {
        case .moveTo: result.move(to:points[0])
        case .lineTo: result.addLine(to:points[0])
        case .curveTo, .cubicCurveTo: result.addCurve(to:points[2],control1:points[0],control2:points[1])
        case .quadraticCurveTo: result.addQuadCurve(to:points[1],control:points[0])
        case .closePath: result.closeSubpath()
        @unknown default: break
        }
    }
    return result
}
func draw(_ context:CGContext,color:Bool) {
    context.saveGState()
    if color {
        let tile=CGPath(roundedRect:CGRect(x:1,y:1,width:18,height:18),cornerWidth:4.2,cornerHeight:4.2,transform:nil)
        context.saveGState();context.addPath(tile);context.clip()
        let space=CGColorSpaceCreateDeviceRGB()
        let colors=[CGColor(red:0.10,green:0.79,blue:0.45,alpha:1),CGColor(red:0,green:0.55,blue:0.40,alpha:1)] as CFArray
        let gradient=CGGradient(colorsSpace:space,colors:colors,locations:[0,1])!
        context.drawLinearGradient(gradient,start:CGPoint(x:0,y:20),end:CGPoint(x:0,y:0),options:[])
        context.restoreGState();context.translateBy(x:3,y:3);context.scaleBy(x:0.70,y:0.70)
        context.setFillColor(CGColor(gray:1,alpha:1))
    } else {context.setFillColor(CGColor(gray:0,alpha:1))}
    context.addPath(cgPath(mark()));context.drawPath(using:.eoFill);context.restoreGState()
}
func bitmap(_ pixels:Int,color:Bool) -> NSBitmapImageRep {
    let context=CGContext(data:nil,width:pixels,height:pixels,bitsPerComponent:8,bytesPerRow:pixels*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x:CGFloat(pixels)/20,y:CGFloat(pixels)/20);draw(context,color:color)
    let rep=NSBitmapImageRep(cgImage:context.makeImage()!);rep.size=NSSize(width:20,height:20);return rep
}
let output=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
let mono=[bitmap(20,color:false),bitmap(40,color:false)]
try NSBitmapImageRep.representationOfImageReps(in:mono,using:.tiff,properties:[:])!.write(to:output.appendingPathComponent("menu.tiff"))
var bounds=CGRect(x:0,y:0,width:20,height:20)
let pdf=NSMutableData();let consumer=CGDataConsumer(data:pdf)!
let context=CGContext(consumer:consumer,mediaBox:&bounds,nil)!
context.beginPDFPage(nil);draw(context,color:false);context.endPDFPage();context.closePDF()
try (pdf as Data).write(to:output.appendingPathComponent("menu.pdf"))
for (name,color) in [("AppIcon",true),("InputIcon",false)] {
    let folder=output.appendingPathComponent(name+".iconset",isDirectory:true)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    for size in [16,32,128,256,512] {
        for scale in [1,2] {
            let filename="icon_\(size)x\(size)"+(scale==2 ? "@2x" : "")+".png"
            let rep=bitmap(size*scale,color:color);rep.size=NSSize(width:size,height:size)
            try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(filename))
        }
    }
}
try bitmap(256,color:true).representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("preview.png"))
try bitmap(160,color:false).representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("menu-preview.png"))
print("Rendered original transparent menu mark and complete Retina iconsets")
