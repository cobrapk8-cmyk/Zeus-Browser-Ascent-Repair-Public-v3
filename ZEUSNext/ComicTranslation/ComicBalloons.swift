import Foundation
import CoreGraphics

/// Recover closed, nearly uniform balloon interiors around recognised lines.
/// The search is bounded; textured/open regions keep their OCR geometry.
enum ComicBalloons {
    static func speeches(_ input:[ComicLine],image:CGImage,source:String)->[ComicSpeech]{
        let lines=uniqueLines(input)
        guard let pixels=ComicPixels.rgba(image,width:image.width,height:image.height)else{return ComicGeometry.group(lines,source:source)}
        var plates:[(CGRect,[ComicLine])]=[],unplated:[ComicLine]=[]
        for line in lines{
            guard let plate=interior(line.rect,pixels:pixels,width:image.width,height:image.height)else{unplated.append(line);continue}
            if let index=plates.firstIndex(where:{overlap($0.0,plate)>0.7}){plates[index].1.append(line)}else{plates.append((plate,[line]))}
        }
        // A fragmented OCR box may fail its own flood-fill even though its centre
        // clearly lies inside a neighbouring line's already detected bubble.
        var remaining:[ComicLine]=[]
        for line in unplated{
            let center=CGPoint(x:line.rect.midX,y:line.rect.midY)
            let ranked=plates.indices.compactMap{index->(Int,CGFloat)? in
                let plate=plates[index].0,coverage=lineCoverage(line.rect,plate)
                guard plate.insetBy(dx:1,dy:1).contains(center),coverage>0.68 else{return nil}
                return(index,coverage)
            }.sorted{$0.1>$1.1}
            if let best=ranked.first,(ranked.count==1||best.1-ranked[1].1>0.15){plates[best.0].1.append(line)}else{remaining.append(line)}
        }
        var result=plates.map{plate,rawLines->ComicSpeech in
            let lines=uniqueLines(rawLines)
            let vertical=lines.allSatisfy{$0.rect.height>$0.rect.width*1.5}
            let ordered=lines.sorted{vertical ? $0.rect.midX>$1.rect.midX:$0.rect.minY<$1.rect.minY}
            return ComicSpeech(id:"",text:ordered.map(\.text).joined(separator:vertical ? "":"\n"),lines:ordered,rect:safeRectangle(plate,pixels:pixels,width:image.width,height:image.height),vertical:vertical,balloon:true)
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
