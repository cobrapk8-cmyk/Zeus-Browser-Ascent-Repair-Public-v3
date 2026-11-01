import Foundation
import CoreGraphics
import OnnxRuntimeBindings

actor ComicPaddle {
    static let shared=ComicPaddle()
    private let environment: ORTEnv
    private var sessions:[String:ORTSession]=[:]
    private var dictionaries:[String:[String]]=[:]
    init(){environment=try! ORTEnv(loggingLevel:.error)}
    func purge(){sessions.removeAll();dictionaries.removeAll()}
    private func session(_ name:String)async throws->ORTSession{
        if let s=sessions[name]{return s}
        let file=try await ComicModelStore.shared.file(name,download:false)
        let options=try ORTSessionOptions();try options.setIntraOpNumThreads(2);try options.setGraphOptimizationLevel(.all)
        let s=try ORTSession(env:environment,modelPath:file.path,sessionOptions:options)
        // Detector plus at most one script. Loading another script evicts the old one.
        if name != "det.onnx" {for key in Array(sessions.keys) where key != "det.onnx"{sessions[key]=nil}}
        sessions[name]=s;return s
    }
    private func infer(_ pixels:CGImage,width:Int,height:Int,detector:Bool,session:ORTSession)throws->([Float],[Int]){
        guard width*height<=2_100_000,let rgba=ComicPixels.rgba(pixels,width:width,height:height)else{throw ComicFailure.message("تعذّر تجهيز بكسلات OCR.")}
        let size=width*height;var tensor=[Float](repeating:0,count:size*3)
        let mean:[Float]=detector ? [0.485,0.456,0.406]:[0.5,0.5,0.5]
        let std:[Float]=detector ? [0.229,0.224,0.225]:[0.5,0.5,0.5]
        for i in 0..<size{for channel in 0..<3{tensor[channel*size+i]=(Float(rgba[i*4+(2-channel)])/255-mean[channel])/std[channel]}}
        let data=tensor.withUnsafeBufferPointer{NSMutableData(bytes:$0.baseAddress!,length:$0.count*MemoryLayout<Float>.size)}
        let value=try ORTValue(tensorData:data,elementType:.float,shape:[1,3,NSNumber(value:height),NSNumber(value:width)])
        let inputs=try session.inputNames(),outputs=try session.outputNames()
        guard let input=inputs.first,let output=outputs.first else{throw ComicFailure.message("واجهة نموذج OCR غير صالحة.")}
        let values=try session.run(withInputs:[input:value],outputNames:Set([output]),runOptions:nil)
        guard let result=values[output]else{throw ComicFailure.message("لم يُرجع النموذج نتيجة.")}
        let shape=try result.tensorTypeAndShapeInfo().shape.map(\.intValue)
        let bytes=try result.tensorData();let count=bytes.length/MemoryLayout<Float>.size
        guard count<30_000_000,shape.allSatisfy({$0>0})else{throw ComicFailure.message("خرج OCR أكبر من الحد.")}
        return(Array(UnsafeBufferPointer(start:bytes.bytes.assumingMemoryBound(to:Float.self),count:count)),shape)
    }
    func read(_ image:CGImage,source:String,careful:Bool)async throws->[ComicLine]{
        let detector=try await session("det.onnx"),name=ComicModelStore.recognizer(source),recognizer=try await session(name+".onnx")
        let dictionary:[String]
        if let saved=dictionaries[name]{dictionary=saved}else{
            let file=try await ComicModelStore.shared.file(name+".yml",download:false)
            dictionary=try Self.dictionary(String(contentsOf:file,encoding:.utf8));dictionaries=[name:dictionary]
        }
        let maxPixels:Double=ProcessInfo.processInfo.physicalMemory<5*1024*1024*1024 ? 700_000:2_000_000
        let factor=min(1,sqrt(maxPixels/Double(image.width*image.height)),4000/Double(max(image.width,image.height)))
        let width=max(32,Int((Double(image.width)*factor/32).rounded())*32),height=max(32,Int((Double(image.height)*factor/32).rounded())*32)
        let (probabilities,shape)=try infer(image,width:width,height:height,detector:true,session:detector)
        guard shape.count==4 else{throw ComicFailure.message("أبعاد خرج كاشف النص غير صالحة.")}
        let mapHeight=shape[2],mapWidth=shape[3]
        let regions=Self.boxes(probabilities,width:mapWidth,height:mapHeight)
        var lines:[ComicLine]=[]
        for box in regions.prefix(1000){
            try Task.checkCancellation()
            let scaleX=CGFloat(image.width)/CGFloat(mapWidth),scaleY=CGFloat(image.height)/CGFloat(mapHeight)
            let rect=CGRect(x:box.minX*scaleX,y:box.minY*scaleY,width:box.width*scaleX,height:box.height*scaleY).integral.intersection(CGRect(x:0,y:0,width:image.width,height:image.height))
            guard let cut=image.cropping(to:rect),cut.width>2,cut.height>2 else{continue}
            let rotated=Double(cut.height)>Double(cut.width)*1.5 ? ComicPixels.rotated(cut):cut
            let targetWidth=max(8,min(4096,Int(ceil(Double(rotated.width)*48/Double(rotated.height)))))
            let (logits,s)=try infer(rotated,width:targetWidth,height:48,detector:false,session:recognizer)
            guard s.count==3 else{throw ComicFailure.message("أبعاد خرج قارئ النص غير صالحة.")}
            let result=Self.ctc(logits,steps:s[1],classes:s[2],dictionary:dictionary)
            let text=name=="arabic" ? ComicBidi.logicalFromVisual(result.0):result.0
            if !text.trimmingCharacters(in:CharacterSet.whitespacesAndNewlines).isEmpty{lines.append(ComicLine(text:text,confidence:result.1,rect:rect))}
        }
        // Careful mode re-detects at native-sized overlapping crops, retaining lines
        // missed by a reduced global pass. The scheduler bounds image dimensions.
        if careful && factor<0.75 {
            let step=max(128,image.height/2)
            for y in stride(from:0,to:image.height,by:step){
                let rect=CGRect(x:0,y:max(0,y-64),width:image.width,height:min(image.height-max(0,y-64),step+128))
                guard let part=image.cropping(to:rect)else{continue}
                let additional=try await read(part,source:source,careful:false)
                for var line in additional{line.rect.origin.y+=rect.minY;if !lines.contains(where:{$0.rect.intersection(line.rect).width>min($0.rect.width,line.rect.width)*0.6 && abs($0.rect.midY-line.rect.midY)<min($0.rect.height,line.rect.height)*0.6}){lines.append(line)}}
            }
        }
        return lines
    }
    static func dictionary(_ yaml:String)throws->[String]{
        let lines=yaml.components(separatedBy:.newlines)
        guard let start=lines.firstIndex(where:{$0.trimmingCharacters(in:.whitespaces)=="character_dict:"})else{throw ComicFailure.message("قاموس OCR مفقود.")}
        var result:[String]=[]
        for line in lines.dropFirst(start+1){guard line.hasPrefix("  - ")else{break};var value=String(line.dropFirst(4)).trimmingCharacters(in:.whitespaces);if value.hasPrefix("'"),value.hasSuffix("'"){value=String(value.dropFirst().dropLast()).replacingOccurrences(of:"''",with:"'")};result.append(value)}
        // Paddle's class zero is CTC blank; append space as in PaddleOCR decoding.
        guard !result.isEmpty else{throw ComicFailure.message("قاموس OCR فارغ.")};return [""]+result+[" "]
    }
    static func ctc(_ values:[Float],steps:Int,classes:Int,dictionary:[String])->(String,Float){
        guard steps>0,classes>0,values.count>=steps*classes else{return("",0)}
        var text="",last=0,total:Float=0,count=0
        for t in 0..<steps{let start=t*classes;var best=0;for c in 1..<classes where values[start+c]>values[start+best]{best=c};if best != 0 && best != last && best<dictionary.count{text+=dictionary[best];total+=values[start+best];count+=1};last=best}
        return(text,count==0 ? 0:total/Float(count))
    }
    static func boxes(_ map:[Float],width:Int,height:Int)->[CGRect]{
        guard width>0,height>0,map.count>=width*height else{return []}
        var seen=[UInt8](repeating:0,count:width*height),result:[CGRect]=[]
        for start in 0..<width*height where seen[start]==0 && map[start]>0.3{
            var queue=[start],head=0,minX=start%width,maxX=minX,minY=start/width,maxY=minY;var score:Float=0
            seen[start]=1
            while head<queue.count{let i=queue[head];head+=1;score+=map[i];let x=i%width,y=i/width;minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y)
                for (dx,dy)in [(-1,0),(1,0),(0,-1),(0,1)]{let nx=x+dx,ny=y+dy;if nx>=0&&nx<width&&ny>=0&&ny<height{let n=ny*width+nx;if seen[n]==0&&map[n]>0.3{seen[n]=1;queue.append(n)}}}
            }
            if queue.count>=3 && score/Float(queue.count)>0.5{let rect=CGRect(x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1);let expansion=min(rect.width,rect.height)*0.25;result.append(rect.insetBy(dx:-expansion,dy:-expansion))}
        }
        return result
    }
}
