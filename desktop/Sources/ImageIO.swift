import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

func imageCommand(_ args: [String]) throws {
    guard args.count >= 3 else { throw NSError(domain:"参数不足",code:1) }
    let input = URL(fileURLWithPath: args[2])
    guard let source = CGImageSourceCreateWithURL(input as CFURL, nil) else { throw NSError(domain:"无法读取图片",code:1) }
    let count = CGImageSourceGetCount(source)
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String:Any] ?? [:]
    if args[1] == "--inspect" {
        var duration = 0.0
        for i in 0..<count {
            let p = CGImageSourceCopyPropertiesAtIndex(source,i,nil) as? [String:Any] ?? [:]
            let g = p[kCGImagePropertyGIFDictionary as String] as? [String:Any] ?? [:]
            duration += (g[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double) ?? (g[kCGImagePropertyGIFDelayTime as String] as? Double) ?? 0
        }
        var managed = false
        if input.pathExtension.lowercased() == "png", let data = try? Data(contentsOf:input) {
            var offset=8
            while offset+12 <= data.count {
                let n = data[offset..<offset+4].reduce(0){($0<<8)|Int($1)}
                if n<0 || n>data.count-offset-12 { break }
                let type=String(data:data[offset+4..<offset+8],encoding:.ascii) ?? ""
                if ["iCCP","cHRM","gAMA","cICP"].contains(type) {managed=true}
                offset += n+12
            }
        }
        let result:[String:Any] = ["width":props[kCGImagePropertyPixelWidth as String] ?? 0,"height":props[kCGImagePropertyPixelHeight as String] ?? 0,"depth":props[kCGImagePropertyDepth as String] ?? 8,"frames":count,"duration":duration,"colorManaged":managed]
        print(String(data:try JSONSerialization.data(withJSONObject:result),encoding:.utf8)!)
        return
    }
    guard args.count >= 5, count == 1 else {throw NSError(domain:"图片参数无效或含多帧",code:1)}
    let output=URL(fileURLWithPath:args[3])
    let maxDimension=Int(args.last!) ?? 0
    if args[1] == "--decode" {
        let w=props[kCGImagePropertyPixelWidth as String] as? Int ?? 1,h=props[kCGImagePropertyPixelHeight as String] as? Int ?? 1
        let limit=maxDimension>0 ? min(maxDimension,max(w,h)) : max(w,h)
        guard let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:limit] as CFDictionary), let space=CGColorSpace(name:CGColorSpace.sRGB),let ctx=CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw NSError(domain:"无法解码图片",code:1)}
        ctx.interpolationQuality = .high
        ctx.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        guard let rendered=ctx.makeImage(),let dest=CGImageDestinationCreateWithURL(output as CFURL,UTType.png.identifier as CFString,1,nil) else {throw NSError(domain:"无法创建图片",code:1)}
        CGImageDestinationAddImage(dest,rendered,nil)
        if !CGImageDestinationFinalize(dest){throw NSError(domain:"图片写入失败",code:1)}
    } else {
        let type=output.pathExtension.lowercased().hasPrefix("tif") ? UTType.tiff.identifier : UTType.heic.identifier
        guard let dest=CGImageDestinationCreateWithURL(output as CFURL,type as CFString,1,nil) else {throw NSError(domain:"编码器不可用",code:1)}
        var p=props
        p[kCGImageDestinationLossyCompressionQuality as String]=Double(args[4]) ?? 0.8
        p[kCGImagePropertyTIFFDictionary as String]=[kCGImagePropertyTIFFCompression as String:5]
        if maxDimension>0 {
            guard let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:maxDimension] as CFDictionary) else {throw NSError(domain:"缩放失败",code:1)}
            p[kCGImagePropertyOrientation as String]=1
            CGImageDestinationAddImage(dest,image,p as CFDictionary)
        }else{CGImageDestinationAddImageFromSource(dest,source,0,p as CFDictionary)}
        if !CGImageDestinationFinalize(dest){throw NSError(domain:"编码失败",code:1)}
    }
}
