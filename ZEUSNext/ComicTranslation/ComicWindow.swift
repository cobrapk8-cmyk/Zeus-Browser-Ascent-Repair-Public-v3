import Foundation
import CoreGraphics

/// Neighbours contribute recognition context only when their actual CSS edges
/// touch. A pending or intervening panel always breaks the strip.
struct ComicWindow {
    struct Neighbours {var before:ComicCandidate?;var after:ComicCandidate?}
    static func neighbours(of current:ComicCandidate,in candidates:[ComicCandidate])->Neighbours{
        let sorted=candidates.sorted{$0.y<$1.y}
        guard let index=sorted.firstIndex(where:{$0.id==current.id})else{return Neighbours()}
        func touches(_ a:ComicCandidate,_ b:ComicCandidate)->Bool{
            !a.pending && !b.pending && a.width>0 && b.width>0 && abs(a.y+a.h-b.y)<=max(3,min(a.h,b.h)*0.01) && abs(a.x-b.x)<3 && abs(a.w-b.w)<max(a.w,b.w)*0.05
        }
        return Neighbours(before:index>0&&touches(sorted[index-1],current) ? sorted[index-1]:nil,after:index+1<sorted.count&&touches(current,sorted[index+1]) ? sorted[index+1]:nil)
    }
    static func join(_ center:CGImage,before:CGImage?,after:CGImage?)throws->(image:CGImage,offset:Int){
        func height(_ image:CGImage?)->Int{guard let image else{return 0};return Int((Double(image.height)*Double(center.width)/Double(image.width)).rounded())}
        let top=height(before),bottom=height(after),total=top+center.height+bottom
        guard center.width*total<=8_000_000,let context=ComicPixels.context(width:center.width,height:total)else{throw ComicFailure.message("تعذّر تجهيز سياق الفقاعة ضمن حد الذاكرة.")}
        // The context's bitmap row order matches CGImage cropping coordinates.
        if let before{context.draw(before,in:CGRect(x:0,y:center.height+bottom,width:center.width,height:top))}
        context.draw(center,in:CGRect(x:0,y:bottom,width:center.width,height:center.height))
        if let after{context.draw(after,in:CGRect(x:0,y:0,width:center.width,height:bottom))}
        guard let image=context.makeImage()else{throw ComicFailure.message("فشل تجميع منطقة القراءة.")};return(image,top)
    }
}
