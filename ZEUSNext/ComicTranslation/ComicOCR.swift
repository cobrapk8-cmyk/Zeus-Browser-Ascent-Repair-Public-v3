import Foundation
import CoreGraphics
import UIKit
import Vision
import NaturalLanguage
#if canImport(MLKitTextRecognition)
import MLKitTextRecognition
import MLKitTextRecognitionChinese
import MLKitTextRecognitionJapanese
import MLKitTextRecognitionKorean
import MLKitVision
#endif

actor ComicOCR {
    static let shared=ComicOCR()
    #if canImport(MLKitTextRecognition)
    private var fastRecognizers:[String:TextRecognizer]=[:]
    #endif
    func purge(){
        #if canImport(MLKitTextRecognition)
        fastRecognizers.removeAll()
        #endif
    }
    func read(_ image:CGImage,source:String,mode:ComicReadingMode)async throws->ComicReading{
        try Task.checkCancellation()
        let detected=source == "auto" ? try await Self.detectScript(image) : source
        let fastSupported=ComicModelStore.recognizer(detected)=="latin" || ["ja","zh","ko"].contains(where:detected.hasPrefix)
        let fast=fastSupported ? try await self.fast(image,source:detected):[]
        var lines=fast
        #if targetEnvironment(simulator)
        var runtime="Apple Vision (simulator only; ML Kit has no arm64 simulator slice)"
        #else
        var runtime="MLKit"
        #endif
        if mode != .fastest || !fastSupported {
            let accurate=try await ComicPaddle.shared.read(image,source:detected,careful:mode == .careful)
            runtime=fastSupported ? "MLKit+Paddle/ONNX":"Paddle/ONNX"
            if mode == .careful{lines=accurate}else{
                for line in accurate where !lines.contains(where:{$0.rect.intersection(line.rect).area/min(max(1,$0.rect.area),max(1,line.rect.area))>0.5}){lines.append(line)}
                // A low-confidence fast line is replaced only by a stronger overlapping reading.
                lines=lines.map{line in accurate.filter{$0.rect.intersection(line.rect).area/max(1,line.rect.area)>0.5&&$0.confidence>line.confidence}.max(by:{$0.confidence<$1.confidence}) ?? line}
            }
        }
        return ComicReading(lines:lines,speeches:ComicBalloons.speeches(lines,image:image,source:detected),language:detected,runtime:runtime)
    }
    private static func detectScript(_ image:CGImage)async throws->String{
        let samples=try vision(image,languages:["ko-KR","ja-JP","zh-Hans","en-US"],accurate:true)
        let text=samples.map(\.text).joined(separator:" ")
        let recognizer=NLLanguageRecognizer();recognizer.processString(text)
        let scalars=text.unicodeScalars
        if scalars.contains(where:{(0xAC00...0xD7AF).contains($0.value)}){return "ko"}
        if scalars.contains(where:{(0x3040...0x30FF).contains($0.value)}){return "ja"}
        if scalars.filter({(0x4E00...0x9FFF).contains($0.value)}).count>=2{return "zh"}
        return recognizer.dominantLanguage?.rawValue ?? "en"
    }
    private func fast(_ image:CGImage,source:String)async throws->[ComicLine]{
        #if canImport(MLKitTextRecognition)
        let recognizer: TextRecognizer
        let script=source.hasPrefix("ko") ? "ko":source.hasPrefix("ja") ? "ja":source.hasPrefix("zh") ? "zh":"latin"
        if let saved=fastRecognizers[script]{recognizer=saved}
        else if source.hasPrefix("ko"){recognizer=TextRecognizer.textRecognizer(options:KoreanTextRecognizerOptions())}
        else if source.hasPrefix("ja"){recognizer=TextRecognizer.textRecognizer(options:JapaneseTextRecognizerOptions())}
        else if source.hasPrefix("zh"){recognizer=TextRecognizer.textRecognizer(options:ChineseTextRecognizerOptions())}
        else{recognizer=TextRecognizer.textRecognizer(options:TextRecognizerOptions())}
        if fastRecognizers[script]==nil{fastRecognizers.removeAll();fastRecognizers[script]=recognizer}
        let result=try await withCheckedThrowingContinuation{(c:CheckedContinuation<Text,Error>)in recognizer.process(VisionImage(image:UIImage(cgImage:image))){text,error in if let error{c.resume(throwing:error)}else if let text{c.resume(returning:text)}else{c.resume(throwing:ComicFailure.message("لم يُرجع OCR نتيجة."))}}}
        return result.blocks.flatMap(\.lines).map{ComicLine(text:$0.text,confidence:0.5,rect:$0.frame)}
        #elseif targetEnvironment(simulator)
        return try Self.vision(image,languages:[source == "auto" ? "en-US":source],accurate:true)
        #else
        // Standalone builds without the SDK remain diagnosable, not falsely labelled ML Kit.
        throw ComicFailure.message("هذا البناء لا يتضمن ML Kit. استخدم بناء ترجمة الصور الكامل.")
        #endif
    }
    private static func vision(_ image:CGImage,languages:[String],accurate:Bool)throws->[ComicLine]{
        let request=VNRecognizeTextRequest();request.recognitionLevel=accurate ? .accurate:.fast;let aliases=["ko":"ko-KR","ja":"ja-JP","zh":"zh-Hans","en":"en-US","ar":"ar-SA"]
        let supported=try request.supportedRecognitionLanguages()
        let requested=languages.map{aliases[$0] ?? $0}.filter{supported.contains($0)}
        request.recognitionLanguages=requested.isEmpty ? ["en-US"]:requested;request.usesLanguageCorrection=false
        try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
        return (request.results ?? []).compactMap{r in guard let value=r.topCandidates(1).first else{return nil};let b=r.boundingBox;return ComicLine(text:value.string,confidence:value.confidence,rect:CGRect(x:b.minX*CGFloat(image.width),y:(1-b.maxY)*CGFloat(image.height),width:b.width*CGFloat(image.width),height:b.height*CGFloat(image.height)))}
    }
}
private extension CGRect {var area:CGFloat {isNull ? 0:max(0,width)*max(0,height)}}
