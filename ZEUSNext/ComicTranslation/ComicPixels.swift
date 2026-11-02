import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UIKit
import ZeusComicRuntime

enum ComicPixels {
    static func context(width:Int,height:Int)->CGContext?{CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue)}
    static func rgba(_ image:CGImage,width:Int,height:Int)->[UInt8]?{guard let c=context(width:width,height:height)else{return nil};c.interpolationQuality = .high;c.draw(image,in:CGRect(x:0,y:0,width:width,height:height));return c.data.map{Array(UnsafeBufferPointer(start:$0.assumingMemoryBound(to:UInt8.self),count:width*height*4))}}
    static func rotated(_ image:CGImage)->CGImage{guard let c=context(width:image.height,height:image.width)else{return image};c.translateBy(x:CGFloat(image.height),y:0);c.rotate(by:.pi/2);c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height));return c.makeImage() ?? image}
    static func decode(_ data:Data)throws->CGImage{guard let source=CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false]as CFDictionary),let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil)as? [CFString:Any],let width=properties[kCGImagePropertyPixelWidth]as? Int,let height=properties[kCGImagePropertyPixelHeight]as? Int,width>0,height>0,width<=16_384,Int64(width)*Int64(height)<=16_000_000,let image=CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCacheImmediately:true]as CFDictionary)else{throw ComicFailure.message("تعذّر فك الصورة ضمن حد الذاكرة؛ لم تُخفض دقتها بصمت.")};return image}
    static func decodeRegion(_ data:Data,region:ComicRegion,expectedHeight:Int?=nil)throws->CGImage{
        if let source=CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false]as CFDictionary),let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil)as? [CFString:Any]{
            let width=(properties[kCGImagePropertyPixelWidth]as? NSNumber)?.intValue,height=(properties[kCGImagePropertyPixelHeight]as? NSNumber)?.intValue
            guard width==region.width,expectedHeight==nil||height==expectedHeight else{throw ComicFailure.message("تغيرت أبعاد الصورة؛ لم تُستخدم إحداثيات لا تطابق الأصل.")}
        }
        let pointer=data.withUnsafeBytes{buffer in zeus_comic_decode_region(buffer.bindMemory(to:UInt8.self).baseAddress,UInt(data.count),Int32(region.x),Int32(region.y),Int32(region.width),Int32(region.height))}
        if let pointer{
            let pixels=Data(bytesNoCopy:pointer,count:region.width*region.height*4,deallocator:.custom{p,_ in zeus_comic_free_pixels(p.assumingMemoryBound(to:UInt8.self))})
            guard let provider=CGDataProvider(data:pixels as CFData),let result=CGImage(width:region.width,height:region.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:region.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)else{throw ComicFailure.message("فشل إنشاء منطقة الصورة.")};return result
        }
        let image=try decode(data);guard image.width==region.width,expectedHeight==nil||image.height==expectedHeight,let crop=image.cropping(to:region.rect)else{throw ComicFailure.message("تعذّر فك المنطقة المطلوبة.")};return crop
    }
    static func png(_ image:CGImage)throws->Data{let output=NSMutableData();guard let destination=CGImageDestinationCreateWithData(output,"public.png" as CFString,1,nil)else{throw ComicFailure.message("تعذّر ترميز الصورة.")};CGImageDestinationAddImage(destination,image,nil);guard CGImageDestinationFinalize(destination)else{throw ComicFailure.message("فشل ترميز الصورة.")};return output as Data}

    private struct EraseLine { let rect:CGRect; let vertical:Bool }
    private struct RGB { let r:CGFloat; let g:CGFloat; let b:CGFloat }
    private struct Estimate { let color:RGB }
    private struct Prepared { let speech:ComicSpeech; let area:CGRect; let layout:TextLayout; let background:(CGFloat,CGFloat,CGFloat) }

    static func render(_ image:CGImage,speeches:[ComicSpeech],translations:[TranslationSegment],target:String,fontName:String?,fontScale:Double,textColor:String? = nil)throws->CGImage{
        guard let context=context(width:image.width,height:image.height),let pixels=rgba(image,width:image.width,height:image.height)else{throw ComicFailure.message("ذاكرة غير كافية للرسم.")}
        context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        var translated:[String:String]=[:]
        for segment in translations{translated[segment.id]=segment.text}
        var prepared:[Prepared]=[]
        for speech in speeches{
            guard let text=translated[speech.id],!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{continue}
            let alreadyOwned = !speech.lines.isEmpty && speech.lines.allSatisfy{line in prepared.contains{item in item.speech.lines.contains{sameLine($0,line)}}}
            if alreadyOwned{continue}
            let pad=speech.balloon ? 0:max(2,min(speech.rect.width,speech.rect.height)*0.08)
            let area=speech.rect.insetBy(dx:-pad,dy:-pad).intersection(CGRect(x:0,y:0,width:image.width,height:image.height)).integral
            guard area.width>3,area.height>3 else{continue}
            let sourceHeight=median(speech.lines.map{speech.vertical ? $0.rect.width:$0.rect.height})
            // Measure every layout before touching the source; a failed fit never erases it.
            guard let layout=layout(text,rect:area.insetBy(dx:2,dy:2),target:target,fontName:fontName,fontScale:fontScale,sourceLineHeight:sourceHeight)else{throw ComicFailure.message("لم يتسع النص للفقاعة؛ بقي الأصل دون مسح.")}
            let background=backgroundColor(pixels,width:image.width,height:image.height,rect:area,excluding:speech.lines)
            prepared.append(Prepared(speech:speech,area:area,layout:layout,background:background))
        }
        guard let data=context.data else{throw ComicFailure.message("تعذّر الوصول إلى ذاكرة الرسم.")}
        let eraseLines=prepared.flatMap{item in item.speech.lines.map{line in EraseLine(rect:line.rect,vertical:item.speech.vertical)}}
        clean(data.assumingMemoryBound(to:UInt8.self),pixels:pixels,width:image.width,height:image.height,lines:eraseLines)
        for item in prepared{
            let background=item.background
            let automatic=background.0*0.2126+background.1*0.7152+background.2*0.0722>0.5 ? CGColor(gray:0.04,alpha:1):CGColor(gray:0.98,alpha:1)
            let color=textColor.flatMap(Self.color) ?? automatic
            context.saveGState();context.setFillColor(color);context.textMatrix = .identity
            // CG image coordinates are top-left. CoreGraphics/CoreText are bottom-left.
            let box=CGRect(x:item.area.minX+2,y:CGFloat(image.height)-item.area.maxY+2+(item.area.height-4-item.layout.height)/2,width:item.area.width-4,height:item.layout.height)
            let attributed=NSMutableAttributedString(attributedString:item.layout.text);attributed.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String),value:color,range:NSRange(location:0,length:attributed.length))
            let frame=CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(attributed),CFRange(),CGPath(rect:box,transform:nil),nil);CTFrameDraw(frame,context);context.restoreGState()
        }
        guard let result=context.makeImage()else{throw ComicFailure.message("فشل رسم النص.")};return result
    }

    /// Runs the production cleanup without drawing a translation; used for pixel-level regression tests.
    static func cleanup(_ image:CGImage,speeches:[ComicSpeech])throws->CGImage{
        guard let context=context(width:image.width,height:image.height),let pixels=rgba(image,width:image.width,height:image.height)else{throw ComicFailure.message("ذاكرة غير كافية لتنظيف الصورة.")}
        context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        guard let data=context.data else{throw ComicFailure.message("تعذّر الوصول إلى ذاكرة التنظيف.")}
        let lines=speeches.flatMap{speech in speech.lines.map{line in EraseLine(rect:line.rect,vertical:speech.vertical)}}
        clean(data.assumingMemoryBound(to:UInt8.self),pixels:pixels,width:image.width,height:image.height,lines:lines)
        guard let result=context.makeImage()else{throw ComicFailure.message("فشل إنشاء الصورة المنظفة.")};return result
    }

    static func color(_ hex:String)->CGColor?{let value=hex.replacingOccurrences(of:"#",with:"");guard value.count==6,let n=UInt32(value,radix:16)else{return nil};return CGColor(red:CGFloat((n>>16)&255)/255,green:CGFloat((n>>8)&255)/255,blue:CGFloat(n&255)/255,alpha:1)}
    struct TextLayout{var text:NSAttributedString;var height:CGFloat;var size:CGFloat}
    static func layout(_ text:String,rect:CGRect,target:String,fontName:String?,fontScale:Double,sourceLineHeight:CGFloat?=nil)->TextLayout?{
        guard rect.width>2,rect.height>2 else{return nil}
        let style=NSMutableParagraphStyle();style.alignment = .center;style.baseWritingDirection=TranslationPreferences.rtl(target) ? .rightToLeft:.leftToRight;style.lineBreakMode = .byWordWrapping
        // OCR boxes may include padding; keep the safety margin deliberately small.
        let sourceCap=sourceLineHeight.map{max(8,$0*1.10)} ?? 96
        let maximum=min(CGFloat(96),min(rect.height,sourceCap))
        guard maximum>=6 else{return nil}
        var low:CGFloat=6,high=maximum,best:TextLayout?
        for _ in 0..<12{let size=(low+high)/2,font=CTFontCreateWithName((fontName ?? "ArialMT")as CFString,size,nil)
            let value=NSAttributedString(string:text,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font,.paragraphStyle:style])
            let setter=CTFramesetterCreateWithAttributedString(value);var fit=CFRange();let measured=CTFramesetterSuggestFrameSizeWithConstraints(setter,CFRange(),nil,CGSize(width:rect.width,height:CGFloat.greatestFiniteMagnitude),&fit)
            if measured.height<=rect.height && measured.width<=rect.width+0.5 && fit.length==value.length{best=TextLayout(text:value,height:ceil(measured.height),size:size);low=size}else{high=size}
        }
        guard let best else{return nil}
        // The fit search already found the largest safe size. User scale may reduce it, not exceed it.
        let scale=CGFloat(min(1.5,max(0.5,fontScale)))
        let chosen=max(6,min(best.size,best.size*scale))
        let font=CTFontCreateWithName((fontName ?? "ArialMT")as CFString,chosen,nil)
        let fitted=NSAttributedString(string:text,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font,.paragraphStyle:style])
        let finalSetter=CTFramesetterCreateWithAttributedString(fitted);var finalFit=CFRange()
        let measured=CTFramesetterSuggestFrameSizeWithConstraints(finalSetter,CFRange(),nil,CGSize(width:rect.width,height:CGFloat.greatestFiniteMagnitude),&finalFit)
        guard measured.height<=rect.height+0.5,measured.width<=rect.width+0.5,finalFit.length==fitted.length else{return nil}
        return TextLayout(text:fitted,height:ceil(measured.height),size:chosen)
    }

    private static func median(_ values:[CGFloat])->CGFloat?{
        let sorted=values.filter{$0.isFinite&&$0>0}.sorted();guard !sorted.isEmpty else{return nil}
        return sorted[sorted.count/2]
    }
    private static func sameLine(_ a:ComicLine,_ b:ComicLine)->Bool{
        let first=String(a.text.lowercased().filter{$0.isLetter||$0.isNumber}),second=String(b.text.lowercased().filter{$0.isLetter||$0.isNumber})
        guard !first.isEmpty,first==second else{return false}
        let intersection=a.rect.intersection(b.rect);guard !intersection.isNull else{return false}
        return intersection.width*intersection.height/max(1,min(a.rect.width*a.rect.height,b.rect.width*b.rect.height))>0.72
    }

    private static func backgroundColor(_ pixels:[UInt8],width:Int,height:Int,rect:CGRect,excluding lines:[ComicLine])->(CGFloat,CGFloat,CGFloat){
        let x0=max(0,Int(rect.minX)+2),x1=min(width-1,Int(rect.maxX)-2),y0=max(0,Int(rect.minY)+2),y1=min(height-1,Int(rect.maxY)-2)
        guard x1>=x0,y1>=y0 else{return(1,1,1)}
        let stepX=max(1,(x1-x0)/8),stepY=max(1,(y1-y0)/8)
        var samples:[(CGFloat,CGFloat,CGFloat,CGFloat)]=[]
        for y in stride(from:y0,through:y1,by:stepY){for x in stride(from:x0,through:x1,by:stepX){
            let point=CGPoint(x:CGFloat(x)+0.5,y:CGFloat(y)+0.5)
            if lines.contains(where:{$0.rect.insetBy(dx:-2,dy:-2).contains(point)}){continue}
            let i=(y*width+x)*4,r=CGFloat(pixels[i])/255,g=CGFloat(pixels[i+1])/255,b=CGFloat(pixels[i+2])/255,l=r*0.2126+g*0.7152+b*0.0722;samples.append((r,g,b,l))
        }}
        if samples.isEmpty{for y in stride(from:y0,through:y1,by:stepY){for x in stride(from:x0,through:x1,by:stepX){let i=(y*width+x)*4,r=CGFloat(pixels[i])/255,g=CGFloat(pixels[i+1])/255,b=CGFloat(pixels[i+2])/255,l=r*0.2126+g*0.7152+b*0.0722;samples.append((r,g,b,l))}}}
        guard !samples.isEmpty else{return(1,1,1)}
        samples.sort{$0.3<$1.3};let sample=samples[samples.count/2];return(sample.0,sample.1,sample.2)
    }

    private static func clean(_ canvas:UnsafeMutablePointer<UInt8>,pixels:[UInt8],width:Int,height:Int,lines:[EraseLine]){
        guard width>0,height>0,!lines.isEmpty,pixels.count>=width*height*4 else{return}
        let count=width*height,imageRect=CGRect(x:0,y:0,width:width,height:height)
        // 0 is unmasked, 1 is a horizontal glyph line, 2 is a vertical line.
        var hard=[UInt8](repeating:0,count:count),opacity=[UInt8](repeating:0,count:count)
        var maskMinX=width,maskMinY=height,maskMaxX=0,maskMaxY=0
        for line in lines{
            guard line.rect.width>0,line.rect.height>0 else{continue}
            let glyph=line.vertical ? min(line.rect.width,line.rect.height):line.rect.height
            let pad=max(2,min(24,glyph*0.34)),inner=max(1,pad*0.56),feather=max(1,pad-inner)
            let core=line.rect.insetBy(dx:-inner,dy:-inner),outer=line.rect.insetBy(dx:-pad,dy:-pad).intersection(imageRect).integral
            guard !outer.isNull,outer.width>0,outer.height>0 else{continue}
            let x0=max(0,Int(outer.minX)),x1=min(width,Int(outer.maxX)),y0=max(0,Int(outer.minY)),y1=min(height,Int(outer.maxY))
            guard x1>x0,y1>y0 else{continue}
            maskMinX=min(maskMinX,x0);maskMaxX=max(maskMaxX,x1);maskMinY=min(maskMinY,y0);maskMaxY=max(maskMaxY,y1)
            for y in y0..<y1{for x in x0..<x1{
                let index=y*width+x
                let point=CGPoint(x:CGFloat(x)+0.5,y:CGFloat(y)+0.5)
                let dx=max(0,max(core.minX-point.x,point.x-core.maxX)),dy=max(0,max(core.minY-point.y,point.y-core.maxY)),distance=max(dx,dy)
                let strength=UInt8((max(0,min(1,1-distance/feather))*255).rounded())
                if strength>0 && strength>=opacity[index]{opacity[index]=strength;hard[index]=line.vertical ? 2:1}
            }}
        }
        guard maskMinX<maskMaxX,maskMinY<maskMaxY,opacity.contains(where:{$0>0})else{return}
        let maxGlyph=lines.map{$0.vertical ? min($0.rect.width,$0.rect.height):$0.rect.height}.max() ?? 12
        let maxSearch=min(128,max(24,Int(maxGlyph*1.8)))
        func sample(_ x:Int,_ y:Int,_ dx:Int,_ dy:Int)->(RGB,Int)?{
            for distance in 1...maxSearch{
                let sx=x+dx*distance,sy=y+dy*distance
                guard sx>=0,sx<width,sy>=0,sy<height else{return nil}
                let maskIndex=sy*width+sx
                if hard[maskIndex]==0{let i=maskIndex*4;return(RGB(r:CGFloat(pixels[i]),g:CGFloat(pixels[i+1]),b:CGFloat(pixels[i+2])),distance)}
            }
            return nil
        }
        func estimate(_ first:(RGB,Int)?,_ second:(RGB,Int)?)->Estimate?{
            guard let first=first else{guard let second=second else{return nil};return Estimate(color:second.0)}
            guard let second=second else{return Estimate(color:first.0)}
            let total=CGFloat(first.1+second.1),t=CGFloat(first.1)/total
            let color=RGB(r:first.0.r*(1-t)+second.0.r*t,g:first.0.g*(1-t)+second.0.g*t,b:first.0.b*(1-t)+second.0.b*t)
            return Estimate(color:color)
        }
        for y in maskMinY..<maskMaxY{for x in maskMinX..<maskMaxX{
            let index=y*width+x,alpha=opacity[index];guard alpha>0 else{continue}
            let top=sample(x,y,0,-1),bottom=sample(x,y,0,1),left=sample(x,y,-1,0),right=sample(x,y,1,0)
            let alongY=estimate(top,bottom),alongX=estimate(left,right)
            let preferred=hard[index]==2 ? alongX:alongY,secondary=hard[index]==2 ? alongY:alongX
            let prediction:RGB
            if let preferred,let secondary{prediction=RGB(r:preferred.color.r*0.82+secondary.color.r*0.18,g:preferred.color.g*0.82+secondary.color.g*0.18,b:preferred.color.b*0.82+secondary.color.b*0.18)}
            else if let preferred{prediction=preferred.color}
            else if let secondary{prediction=secondary.color}
            else{continue}
            let i=index*4,a=CGFloat(alpha)/255
            canvas[i]=UInt8(max(0,min(255,(CGFloat(pixels[i])*(1-a)+prediction.r*a).rounded())))
            canvas[i+1]=UInt8(max(0,min(255,(CGFloat(pixels[i+1])*(1-a)+prediction.g*a).rounded())))
            canvas[i+2]=UInt8(max(0,min(255,(CGFloat(pixels[i+2])*(1-a)+prediction.b*a).rounded())))
            canvas[i+3]=pixels[i+3]
        }}
    }
}
