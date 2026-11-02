import Foundation
import CoreGraphics

/// Recover closed, nearly uniform balloon interiors around recognised lines.
/// The search is bounded; textured/open regions keep their OCR geometry.
enum ComicBalloons {
    private struct Plate { var detected:CGRect;var bounds:CGRect;var lines:[ComicLine] }
    private struct Divider { var vertical:Bool;var position:CGFloat }
    static func speeches(_ input:[ComicLine],image:CGImage,source:String)->[ComicSpeech]{
        let lines=uniqueLines(input)
        guard let pixels=ComicPixels.rgba(image,width:image.width,height:image.height)else{return ComicGeometry.group(lines,source:source)}
        var plates:[Plate]=[],unplated:[ComicLine]=[]
        for line in lines{
            guard let plate=interior(line.rect,pixels:pixels,width:image.width,height:image.height)else{unplated.append(line);continue}
            let candidates=plates.indices.filter{overlap(plates[$0].detected,plate)>0.7}
            var nearest:(Int,CGFloat,ComicLine,Divider?)?
            for index in candidates{
                guard let prior=plates[index].lines.min(by:{distance($0.rect,line.rect)<distance($1.rect,line.rect)})else{continue}
                let d=distance(prior.rect,line.rect),verticalText=prior.rect.height>prior.rect.width*1.5&&line.rect.height>line.rect.width*1.5
                let divider=separatingDivider(prior.rect,line.rect,plate:plates[index].detected,verticalText:verticalText,pixels:pixels,width:image.width,height:image.height)
                if let current=nearest{if d<current.1{nearest=(index,d,prior,divider)}}else{nearest=(index,d,prior,divider)}
            }
            if let nearest,let divider=nearest.3{
                addSeparated(line,prior:nearest.2,divider:divider,index:nearest.0,detected:plate,plates:&plates)
            }else if let nearest{plates[nearest.0].lines.append(line)}
            else{plates.append(Plate(detected:plate,bounds:plate,lines:[line]))}
        }
        // A fragmented OCR box may fail its own flood-fill even though its centre
        // clearly lies inside a neighbouring line's already detected bubble.
        var remaining:[ComicLine]=[]
        for line in unplated{
            let center=CGPoint(x:line.rect.midX,y:line.rect.midY)
            let ranked=plates.indices.compactMap{index->(Int,CGFloat)? in
                let plate=plates[index].bounds,coverage=lineCoverage(line.rect,plate)
                guard plate.insetBy(dx:1,dy:1).contains(center),coverage>0.68 else{return nil}
                return(index,coverage)
            }.sorted{$0.1>$1.1}
            guard let best=ranked.first,(ranked.count==1||best.1-ranked[1].1>0.15),let prior=plates[best.0].lines.min(by:{distance($0.rect,line.rect)<distance($1.rect,line.rect)})else{remaining.append(line);continue}
            if let divider=separatingDivider(prior.rect,line.rect,plate:plates[best.0].detected,verticalText:prior.rect.height>prior.rect.width*1.5&&line.rect.height>line.rect.width*1.5,pixels:pixels,width:image.width,height:image.height){addSeparated(line,prior:prior,divider:divider,index:best.0,detected:plates[best.0].detected,plates:&plates)}else{plates[best.0].lines.append(line)}
        }
        var result=plates.map{plate->ComicSpeech in
            let lines=uniqueLines(plate.lines)
            let vertical=lines.allSatisfy{$0.rect.height>$0.rect.width*1.5}
            let ordered=lines.sorted{vertical ? $0.rect.midX>$1.rect.midX:$0.rect.minY<$1.rect.minY}
            return ComicSpeech(id:"",text:ordered.map(\.text).joined(separator:vertical ? "":"\n"),lines:ordered,rect:safeRectangle(plate.bounds,pixels:pixels,width:image.width,height:image.height),vertical:vertical,balloon:true)
        }
        result+=ComicGeometry.group(uniqueLines(remaining),source:source)
        result.sort{a,b in if abs(a.rect.minY-b.rect.minY)<min(a.rect.height,b.rect.height)*0.35{return source.hasPrefix("ja") ? a.rect.midX>b.rect.midX:a.rect.midX<b.rect.midX};return a.rect.minY<b.rect.minY}
        return result.enumerated().map{i,s in var s=s;s.id=String(i);return s}
    }
    private static func uniqueLines(_ lines:[ComicLine])->[ComicLine]{
        var result:[ComicLine]=[]
        for line in lines.sorted(by:{$0.confidence>$1.confidence}){
            // Keep distinct words even when OCR boxes overlap; collapse only near-identical
            // geometry with the same normalized text, preferring the higher-confidence read.
            if result.contains(where:{sameOCR($0,line)}){continue}
            result.append(line)
        }
        return result.sorted{$0.rect.minY<$1.rect.minY}
    }
    private static func sameOCR(_ a:ComicLine,_ b:ComicLine)->Bool{
        let first=String(a.text.lowercased().filter{$0.isLetter||$0.isNumber}),second=String(b.text.lowercased().filter{$0.isLetter||$0.isNumber})
        guard !first.isEmpty,first==second else{return false}
        return overlap(a.rect,b.rect)>0.72
    }
    private static func distance(_ a:CGRect,_ b:CGRect)->CGFloat{
        let dx=max(0,max(a.minX-b.maxX,b.minX-a.maxX)),dy=max(0,max(a.minY-b.maxY,b.minY-a.maxY));return dx*dx+dy*dy
    }
    private static func split(_ rect:CGRect,at position:CGFloat,vertical:Bool,keepBefore:Bool)->CGRect{
        if vertical{let cut=max(rect.minY+1,min(rect.maxY-1,position));return keepBefore ? CGRect(x:rect.minX,y:rect.minY,width:rect.width,height:cut-rect.minY):CGRect(x:rect.minX,y:cut,width:rect.width,height:rect.maxY-cut)}
        let cut=max(rect.minX+1,min(rect.maxX-1,position));return keepBefore ? CGRect(x:rect.minX,y:rect.minY,width:cut-rect.minX,height:rect.height):CGRect(x:cut,y:rect.minY,width:rect.maxX-cut,height:rect.height)
    }
    private static func addSeparated(_ line:ComicLine,prior:ComicLine,divider:Divider,index:Int,detected:CGRect,plates:inout [Plate]){
        let priorBefore=divider.vertical ? prior.rect.midY<line.rect.midY:prior.rect.midX<line.rect.midX
        plates[index].bounds=split(plates[index].bounds,at:divider.position,vertical:divider.vertical,keepBefore:priorBefore)
        let newBounds=split(detected,at:divider.position,vertical:divider.vertical,keepBefore:!priorBefore)
        plates.append(Plate(detected:detected,bounds:newBounds,lines:[line]))
    }
    private static func separatingDivider(_ a:CGRect,_ b:CGRect,plate:CGRect,verticalText:Bool,pixels:[UInt8],width:Int,height:Int)->Divider?{
        func dark(_ x:Int,_ y:Int)->Bool{let i=(y*width+x)*4;return CGFloat(pixels[i])*0.2126+CGFloat(pixels[i+1])*0.7152+CGFloat(pixels[i+2])*0.0722<82}
        if !verticalText{
            let top=a.midY<=b.midY ? a:b,bottom=a.midY<=b.midY ? b:a,gap=bottom.minY-top.maxY
            guard gap>=2,gap<=max(80,min(top.height,bottom.height)*6)else{return nil}
            let x0=max(0,Int(plate.minX+plate.width*0.08)),x1=min(width-1,Int(plate.maxX-plate.width*0.08)),y0=max(0,Int(top.maxY+1)),y1=min(height-1,Int(bottom.minY-1)),needed=max(10,Int(CGFloat(max(0,x1-x0+1))*0.10))
            guard x1>x0,y1>=y0 else{return nil}
            for y in y0...y1{var run=0;for x in x0...x1{if dark(x,y){run+=1;if run>=needed{return Divider(vertical:true,position:CGFloat(y)+0.5)}}else{run=0}}}
        }else{
            let left=a.midX<=b.midX ? a:b,right=a.midX<=b.midX ? b:a,gap=right.minX-left.maxX
            guard gap>=2,gap<=max(80,min(left.width,right.width)*6)else{return nil}
            let y0=max(0,Int(plate.minY+plate.height*0.08)),y1=min(height-1,Int(plate.maxY-plate.height*0.08)),x0=max(0,Int(left.maxX+1)),x1=min(width-1,Int(right.minX-1)),needed=max(10,Int(CGFloat(max(0,y1-y0+1))*0.10))
            guard y1>y0,x1>=x0 else{return nil}
            for x in x0...x1{var run=0;for y in y0...y1{if dark(x,y){run+=1;if run>=needed{return Divider(vertical:false,position:CGFloat(x)+0.5)}}else{run=0}}}
        }
        return nil
    }
    private static func safeRectangle(_ plate:CGRect,pixels:[UInt8],width:Int,height:Int)->CGRect{
        func color(_ x:CGFloat,_ y:CGFloat)->[Int]{let x=max(0,min(width-1,Int(x))),y=max(0,min(height-1,Int(y))),i=(y*width+x)*4;return [Int(pixels[i]),Int(pixels[i+1]),Int(pixels[i+2])]}
        let center=color(plate.midX,plate.minY+plate.height*0.2)
        let corners=[color(plate.minX+2,plate.minY+2),color(plate.maxX-3,plate.minY+2),color(plate.minX+2,plate.maxY-3),color(plate.maxX-3,plate.maxY-3)]
        let rectangular=corners.allSatisfy{c in zip(c,center).reduce(0){$0+abs($1.0-$1.1)}<75}
        return rectangular ? plate.insetBy(dx:3,dy:3):plate.insetBy(dx:plate.width*0.15,dy:plate.height*0.15)
    }
    private static func overlap(_ a:CGRect,_ b:CGRect)->CGFloat{let intersection=a.intersection(b);guard !intersection.isNull else{return 0};return intersection.width*intersection.height/max(1,min(a.width*a.height,b.width*b.height))}
    private static func lineCoverage(_ line:CGRect,_ plate:CGRect)->CGFloat{let intersection=line.intersection(plate);guard !intersection.isNull else{return 0};return intersection.width*intersection.height/max(1,line.width*line.height)}
    static func interior(_ text:CGRect,pixels:[UInt8],width:Int,height:Int)->CGRect?{
        guard text.width>2,text.height>2,pixels.count>=width*height*4 else{return nil}
        let margin=min(600,max(text.width*1.3,text.height*3))
        let roi=text.insetBy(dx:-margin,dy:-margin).integral.intersection(CGRect(x:0,y:0,width:width,height:height))
        guard !roi.isNull,roi.width*roi.height<=1_000_000 else{return nil}
        let left=Int(roi.minX),top=Int(roi.minY),rw=Int(roi.width),rh=Int(roi.height)
        var bins:[Int:(Int,Int,Int,Int)]=[:],seeds:[Int]=[]
        for yy in 0..<7{for xx in 0..<7{let x=min(width-1,max(0,Int(text.minX+text.width*CGFloat(xx+1)/8))),y=min(height-1,max(0,Int(text.minY+text.height*CGFloat(yy+1)/8))),i=(y*width+x)*4
            let r=Int(pixels[i]),g=Int(pixels[i+1]),b=Int(pixels[i+2]),key=(r/32)*64+(g/32)*8+b/32,old=bins[key] ?? (0,0,0,0);bins[key]=(old.0+r,old.1+g,old.2+b,old.3+1);seeds.append((y-top)*rw+x-left)}}
        guard let background=bins.values.max(by:{$0.3<$1.3})else{return nil}
        let red=background.0/background.3,green=background.1/background.3,blue=background.2/background.3
        func matches(_ index:Int)->Bool{let p=((index/rw+top)*width+index%rw+left)*4;return abs(Int(pixels[p])-red)+abs(Int(pixels[p+1])-green)+abs(Int(pixels[p+2])-blue)<75}
        var seen=[UInt8](repeating:0,count:rw*rh),best:CGRect?
        let maximum=min(150_000,max(4096,Int(text.width*text.height*40)))
        for seed in seeds where seed>=0&&seed<seen.count&&seen[seed]==0&&matches(seed){
            var queue=[seed],head=0,minX=seed%rw,maxX=minX,minY=seed/rw,maxY=minY,touches=false
            seen[seed]=1
            while head<queue.count&&queue.count<=maximum{let current=queue[head];head+=1;let x=current%rw,y=current/rw
                minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y)
                if x==0||y==0||x==rw-1||y==rh-1{touches=true}
                for(dx,dy)in [(-1,0),(1,0),(0,-1),(0,1)]{let nx=x+dx,ny=y+dy;if nx>=0&&nx<rw&&ny>=0&&ny<rh{let n=ny*rw+nx;if seen[n]==0&&matches(n){seen[n]=1;queue.append(n)}}}
            }
            guard !touches,queue.count<=maximum,CGFloat(queue.count)>text.width*text.height*0.5 else{continue}
            let bounds=CGRect(x:left+minX,y:top+minY,width:maxX-minX+1,height:maxY-minY+1)
            if bounds.insetBy(dx:-2,dy:-2).contains(text),best==nil||bounds.width*bounds.height>best!.width*best!.height{best=bounds}
        }
        return best
    }
}
