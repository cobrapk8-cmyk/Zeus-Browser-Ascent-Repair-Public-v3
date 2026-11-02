import XCTest
import WebKit
import UIKit
#if canImport(ZEUSBrowser)
@testable import ZEUSBrowser
#else
@testable import ZEUSNext
#endif

@MainActor final class NativeComicTranslationTests:XCTestCase{
    private func renderer(_ size:CGSize)->UIGraphicsImageRenderer{let format=UIGraphicsImageRendererFormat();format.scale=1;return UIGraphicsImageRenderer(size:size,format:format)}
    func testRegionsOwnEveryRowExactlyOnceAndBoundPixels(){
        let regions=ComicGeometry.regions(width:1500,height:70000)
        XCTAssertGreaterThan(regions.count,10)
        var previous=0
        for region in regions{XCTAssertLessThanOrEqual(region.width*region.height,8_000_000);XCTAssertEqual(region.y+region.coreTop,previous);previous=region.y+region.coreBottom;XCTAssertLessThan(region.coreTop,region.coreBottom)}
        XCTAssertEqual(previous,70000);XCTAssertTrue(ComicGeometry.regions(width:0,height:1).isEmpty)
    }
    func testStripNeverCrossesUnloadedPanelAndPreservesPixelOrder()throws{
        func candidate(_ id:String,_ y:Double,pending:Bool=false)->ComicCandidate{ComicCandidate(id:id,source:"https://example.invalid/"+id,kind:"image",width:200,height:400,x:0,y:y,w:200,h:400,pending:pending,revision:"0")}
        let a=candidate("a",0),b=candidate("b",400),c=candidate("c",800)
        XCTAssertEqual(ComicWindow.neighbours(of:b,in:[a,b,c]).before?.id,"a")
        let gap=candidate("gap",400,pending:true)
        XCTAssertNil(ComicWindow.neighbours(of:a,in:[a,gap,c]).after)
        func image(_ color:UIColor)->CGImage{renderer(CGSize(width:20,height:20)).image{ctx in color.setFill();ctx.fill(CGRect(x:0,y:0,width:20,height:20))}.cgImage!}
        let joined=try ComicWindow.join(image(.green),before:image(.red),after:image(.blue))
        XCTAssertEqual(joined.offset,20);XCTAssertEqual(joined.image.height,60)
        let pixels=try XCTUnwrap(ComicPixels.rgba(joined.image,width:20,height:60))
        XCTAssertGreaterThan(pixels[0],200);XCTAssertGreaterThan(pixels[(40*20)*4+2],200)
    }
    func testNativeTallPNGRegionMatchesOriginal()throws{
        let image=renderer(CGSize(width:100,height:12000)).image{ctx in UIColor.red.setFill();ctx.fill(CGRect(x:0,y:0,width:100,height:12000))}
        let data=try XCTUnwrap(image.pngData()),region=ComicRegion(y:11000,width:100,height:1000,coreTop:0,coreBottom:1000)
        let decoded=try ComicPixels.decodeRegion(data,region:region)
        XCTAssertEqual(decoded.width,100);XCTAssertEqual(decoded.height,1000)
        let pixels=try XCTUnwrap(ComicPixels.rgba(decoded,width:100,height:1000));XCTAssertGreaterThan(pixels[0],200)
    }
    func testTallImageScrollJumpPrioritizesVisibleRegion(){
        let candidate=ComicCandidate(id:"long",source:"https://example.invalid/long.png",kind:"image",width:1000,height:70000,x:0,y:0,w:1000,h:70000,pending:false,revision:"0")
        let regions=ComicGeometry.regions(width:1000,height:70000)
        let queued=ComicGeometry.prioritized(regions,candidate:candidate,scroll:50000,viewport:800,readAhead:false)
        XCTAssertFalse(queued.isEmpty)
        XCTAssertTrue(queued.allSatisfy{$0.y+$0.coreBottom>=50000&&$0.y+$0.coreTop<=50800})
        XCTAssertFalse(queued.contains{$0.y==0})
    }
    func testCTCBlankRepeatedGlyphAndDictionaryValidation()throws{
        let dictionary=try ComicPaddle.dictionary("Global:\n  character_dict:\n  - 'ا'\n  - 'ب'\n")
        let result=ComicPaddle.ctc([0,1,0,0, 0,1,0,0, 1,0,0,0, 0,1,0,0, 0,0,1,0],steps:5,classes:4,dictionary:dictionary)
        XCTAssertEqual(result.0,"ااب");XCTAssertEqual(result.1,1)
        XCTAssertThrowsError(try ComicPaddle.dictionary("invalid"))
    }
    func testArabicCoreTextFitsAndColorIsValidated()throws{
        let layout=try XCTUnwrap(ComicPixels.layout("أين ذهب صديقي؟",rect:CGRect(x:0,y:0,width:160,height:90),target:"ar",fontName:nil,fontScale:1))
        XCTAssertLessThanOrEqual(layout.height,90);XCTAssertGreaterThan(layout.size,6)
        XCTAssertNil(ComicPixels.color("<script>"));XCTAssertNotNil(ComicPixels.color("#163B72"))
    }
    func testArabicFontScaleCannotExceedOriginalLetterHeight()throws{
        let rect=CGRect(x:0,y:0,width:250,height:90)
        let normal=try XCTUnwrap(ComicPixels.layout("أين ذهب صديقي؟",rect:rect,target:"ar",fontName:nil,fontScale:1,sourceLineHeight:18))
        let enlarged=try XCTUnwrap(ComicPixels.layout("أين ذهب صديقي؟",rect:rect,target:"ar",fontName:nil,fontScale:1.5,sourceLineHeight:18))
        XCTAssertLessThanOrEqual(enlarged.size,18*1.10+0.5,"Translated lettering must remain bounded by the source line height")
        XCTAssertEqual(enlarged.size,normal.size,accuracy:0.5,"User scaling cannot enlarge Arabic beyond the measured fit")
    }
    func testArabicLetteringChangesActualPixelsInsideTheBalloon()throws{
        let raster=renderer(CGSize(width:320,height:200)).image{context in
            UIColor.white.setFill();context.fill(CGRect(x:0,y:0,width:320,height:200))
            ("HELLO" as NSString).draw(at:CGPoint(x:90,y:40),withAttributes:[.font:UIFont.systemFont(ofSize:32),.foregroundColor:UIColor.black])
        }
        let line=ComicLine(text:"HELLO",confidence:1,rect:CGRect(x:88,y:40,width:120,height:40))
        let speech=ComicSpeech(id:"0",text:"HELLO",lines:[line],rect:CGRect(x:55,y:20,width:210,height:90),vertical:false,balloon:true)
        let output=try ComicPixels.render(try XCTUnwrap(raster.cgImage),speeches:[speech],translations:[TranslationSegment(id:"0",text:"مرحبًا يا صديقي")],target:"ar",fontName:nil,fontScale:1,textColor:"163B72")
        let pixels=try XCTUnwrap(ComicPixels.rgba(output,width:320,height:200))
        var blue=0,outside=0,blackSourcePixels=0
        for y in 0..<200{for x in 0..<320{let i=(y*320+x)*4
            if speech.rect.contains(CGPoint(x:x,y:y)),pixels[i]<45&&pixels[i+1]<45&&pixels[i+2]<45{blackSourcePixels+=1}
            if Int(pixels[i+2])>Int(pixels[i])+25 && Int(pixels[i+2])>Int(pixels[i+1])+15{blue+=1;if !speech.rect.contains(CGPoint(x:x,y:y)){outside+=1}}
        }}
        XCTAssertGreaterThan(blue,50,"CoreText must draw the selected color into the image")
        XCTAssertEqual(outside,0,"Arabic lettering must remain inside the original balloon")
        XCTAssertLessThan(blackSourcePixels,20,"The source glyphs should be removed before Arabic is drawn")
        let attachment=XCTAttachment(image:UIImage(cgImage:output));attachment.name="Arabic lettering - actual pixels";attachment.lifetime = .keepAlways;add(attachment)
    }
    func testBalloonInteriorProtectsBordersAndProvidesRoomForArabic()throws{
        let image=renderer(CGSize(width:300,height:220)).image{context in
            UIColor.darkGray.setFill();context.fill(CGRect(x:0,y:0,width:300,height:220))
            UIColor.white.setFill();UIBezierPath(ovalIn:CGRect(x:50,y:30,width:200,height:160)).fill()
            UIColor.black.setFill();context.fill(CGRect(x:110,y:90,width:80,height:4))
        }.cgImage!
        let pixels=try XCTUnwrap(ComicPixels.rgba(image,width:300,height:220))
        let interior=try XCTUnwrap(ComicBalloons.interior(CGRect(x:100,y:80,width:100,height:40),pixels:pixels,width:300,height:220))
        XCTAssertGreaterThan(interior.width,150);XCTAssertGreaterThan(interior.height,100)
        XCTAssertGreaterThan(interior.minX,45);XCTAssertLessThan(interior.maxX,255)
    }
    func testBalloonGroupsFragmentedLinesAndDropsDuplicateOCR()throws{
        let image=renderer(CGSize(width:320,height:240)).image{context in
            UIColor.darkGray.setFill();context.fill(CGRect(x:0,y:0,width:320,height:240))
            UIColor.white.setFill();UIBezierPath(ovalIn:CGRect(x:20,y:20,width:280,height:200)).fill()
            ("HELLO THERE" as NSString).draw(at:CGPoint(x:88,y:78),withAttributes:[.font:UIFont.systemFont(ofSize:20),.foregroundColor:UIColor.black])
            ("MY FRIEND" as NSString).draw(at:CGPoint(x:126,y:111),withAttributes:[.font:UIFont.systemFont(ofSize:20),.foregroundColor:UIColor.black])
        }.cgImage!
        let first=ComicLine(text:"HELLO THERE",confidence:0.99,rect:CGRect(x:82,y:72,width:160,height:32))
        let duplicate=ComicLine(text:"HELLO THERE",confidence:0.40,rect:first.rect.insetBy(dx:1,dy:1))
        let second=ComicLine(text:"MY FRIEND",confidence:0.95,rect:CGRect(x:120,y:105,width:100,height:32))
        let speeches=ComicBalloons.speeches([first,duplicate,second],image:image,source:"en")
        XCTAssertEqual(speeches.count,1,"OCR fragments inside one balloon should share one translation")
        XCTAssertEqual(speeches.first?.lines.count,2,"Duplicate OCR boxes must not be translated or rendered twice")
        XCTAssertEqual(speeches.first?.balloon,true)
    }
    func testBalloonGroupingKeepsNeighboringBubblesSeparate()throws{
        let image=renderer(CGSize(width:320,height:200)).image{context in
            UIColor.darkGray.setFill();context.fill(CGRect(x:0,y:0,width:320,height:200))
            UIColor.white.setFill();UIBezierPath(ovalIn:CGRect(x:10,y:20,width:140,height:140)).fill();UIBezierPath(ovalIn:CGRect(x:170,y:20,width:140,height:140)).fill()
            ("FIRST" as NSString).draw(at:CGPoint(x:44,y:70),withAttributes:[.font:UIFont.systemFont(ofSize:19),.foregroundColor:UIColor.black])
            ("SECOND" as NSString).draw(at:CGPoint(x:203,y:70),withAttributes:[.font:UIFont.systemFont(ofSize:19),.foregroundColor:UIColor.black])
        }.cgImage!
        let lines=[ComicLine(text:"FIRST",confidence:0.95,rect:CGRect(x:38,y:66,width:90,height:30)),ComicLine(text:"SECOND",confidence:0.95,rect:CGRect(x:198,y:66,width:100,height:30))]
        let speeches=ComicBalloons.speeches(lines,image:image,source:"en")
        XCTAssertEqual(speeches.count,2,"Separate bubble interiors must remain separate translations")
        XCTAssertTrue(speeches.allSatisfy{$0.lines.count==1})
    }
    func testRendererCleanupRemovesGlyphsAndPreservesTexturedGradient()throws{
        let size=CGSize(width:320,height:180)
        func paintBackground(_ context:UIGraphicsImageRendererContext){
            let colors=[UIColor(red:0.88,green:0.82,blue:0.95,alpha:1).cgColor,UIColor(red:0.22,green:0.26,blue:0.43,alpha:1).cgColor] as CFArray
            let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:nil)!
            context.cgContext.drawLinearGradient(gradient,start:CGPoint(x:0,y:0),end:CGPoint(x:0,y:180),options:[])
            for x in stride(from:0,to:320,by:16){UIColor(white:1,alpha:0.09).setFill();context.fill(CGRect(x:x,y:0,width:3,height:180))}
        }
        let clean=renderer(size).image{paintBackground($0)}.cgImage!
        let marked=renderer(size).image{context in
            paintBackground(context)
            ("ORIGINAL" as NSString).draw(at:CGPoint(x:92,y:63),withAttributes:[.font:UIFont.boldSystemFont(ofSize:34),.foregroundColor:UIColor.black])
        }.cgImage!
        let line=ComicLine(text:"ORIGINAL",confidence:1,rect:CGRect(x:85,y:54,width:175,height:52))
        let speech=ComicSpeech(id:"0",text:"ORIGINAL",lines:[line],rect:line.rect,vertical:false,balloon:false)
        let output=try ComicPixels.cleanup(marked,speeches:[speech])
        let expected=try XCTUnwrap(ComicPixels.rgba(clean,width:320,height:180)),actual=try XCTUnwrap(ComicPixels.rgba(output,width:320,height:180))
        var difference=0,residualGlyphPixels=0,samples=0
        for y in Int(line.rect.minY)..<Int(line.rect.maxY){for x in Int(line.rect.minX)..<Int(line.rect.maxX){let i=(y*320+x)*4
            let delta=abs(Int(actual[i])-Int(expected[i]))+abs(Int(actual[i+1])-Int(expected[i+1]))+abs(Int(actual[i+2])-Int(expected[i+2]))
            difference+=delta;samples+=1;if delta>90{residualGlyphPixels+=1}
        }}
        XCTAssertLessThan(Double(difference)/Double(samples*3),18,"Inpainted area should follow the original gradient and vertical texture")
        XCTAssertLessThan(residualGlyphPixels,60,"Original dark glyph pixels must not remain under the new lettering")
        for point in [CGPoint(x:8,y:8),CGPoint(x:310,y:170)]{let i=(Int(point.y)*320+Int(point.x))*4;for channel in 0..<3{XCTAssertLessThanOrEqual(abs(Int(actual[i+channel])-Int(expected[i+channel])),2,"Cleanup must not alter pixels outside its text mask")}}
    }
    func testRendererDoesNotPaintTwoOwnersForSameOCRLine()throws{
        let image=renderer(CGSize(width:260,height:130)).image{context in UIColor.white.setFill();context.fill(CGRect(x:0,y:0,width:260,height:130))}.cgImage!
        let line=ComicLine(text:"ORIGINAL",confidence:1,rect:CGRect(x:75,y:45,width:110,height:28))
        let first=ComicSpeech(id:"0",text:"ORIGINAL",lines:[line],rect:CGRect(x:35,y:20,width:190,height:80),vertical:false,balloon:true)
        let nearDuplicate=ComicLine(text:"ORIGINAL",confidence:0.90,rect:line.rect.insetBy(dx:1,dy:1))
        let duplicate=ComicSpeech(id:"1",text:"ORIGINAL",lines:[nearDuplicate],rect:first.rect,vertical:false,balloon:true)
        let only=try ComicPixels.render(image,speeches:[first],translations:[TranslationSegment(id:"0",text:"أهلاً")],target:"ar",fontName:nil,fontScale:1)
        let both=try ComicPixels.render(image,speeches:[first,duplicate],translations:[TranslationSegment(id:"0",text:"أهلاً"),TranslationSegment(id:"1",text:"تكرار")],target:"ar",fontName:nil,fontScale:1)
        XCTAssertEqual(try ComicPixels.rgba(both,width:260,height:130),try ComicPixels.rgba(only,width:260,height:130))
    }
    func testGroupingDoesNotJoinAdjacentBalloons(){
        let lines=[ComicLine(text:"첫 줄",confidence:1,rect:CGRect(x:10,y:10,width:80,height:20)),ComicLine(text:"둘째 줄",confidence:1,rect:CGRect(x:10,y:35,width:80,height:20)),ComicLine(text:"다른 말",confidence:1,rect:CGRect(x:200,y:12,width:80,height:20))]
        let speeches=ComicGeometry.group(lines,source:"ko")
        XCTAssertEqual(speeches.count,2);XCTAssertTrue(speeches.contains{$0.lines.count==2})
    }
    func testGeometryGroupsCenteredFragmentsWithLooseLineSpacing(){
        let lines=[ComicLine(text:"FIRST",confidence:1,rect:CGRect(x:90,y:20,width:100,height:16)),ComicLine(text:"SECOND",confidence:1,rect:CGRect(x:115,y:56,width:50,height:16))]
        let speeches=ComicGeometry.group(lines,source:"en")
        XCTAssertEqual(speeches.count,1,"Centered fragments in one text block should not become separately scaled translations")
        XCTAssertEqual(speeches.first?.lines.count,2)
    }
    func testGeometryDoesNotJoinSeparatedCenteredBlocks(){
        let mediumGap=[ComicLine(text:"FIRST",confidence:1,rect:CGRect(x:90,y:20,width:100,height:16)),ComicLine(text:"SECOND",confidence:1,rect:CGRect(x:115,y:60,width:50,height:16))]
        let distant=[ComicLine(text:"FIRST",confidence:1,rect:CGRect(x:90,y:20,width:100,height:16)),ComicLine(text:"SECOND",confidence:1,rect:CGRect(x:115,y:84,width:50,height:16))]
        XCTAssertEqual(ComicGeometry.group(mediumGap,source:"en").count,2,"Separated centered balloons must not merge at medium spacing")
        XCTAssertEqual(ComicGeometry.group(distant,source:"en").count,2,"Distant centered text blocks must not be merged")
    }
    func testArabicOCRVisualOrderDoesNotReverseLatinTokensOrNumbers(){
        XCTAssertEqual(ComicBidi.logicalFromVisual("ابحرم"),"مرحبا")
        XCTAssertEqual(ComicBidi.logicalFromVisual(")ابحرم( ABC"),"ABC (مرحبا)")
        XCTAssertEqual(ComicBidi.logicalFromVisual("12.5"),"12.5")
        XCTAssertEqual(ComicBidi.logicalFromVisual("(ابحرم) ABC"),"ABC (مرحبا)")
        XCTAssertEqual(ComicBidi.logicalFromVisual("]ابحرم[ 12.5"),"12.5 [مرحبا]")
    }
    func testActualLocalOCRReadsRasterText()async throws{
        let image=renderer(CGSize(width:640,height:180)).image{context in
            UIColor.white.setFill();context.fill(CGRect(x:0,y:0,width:640,height:180))
            ("HELLO WORLD" as NSString).draw(at:CGPoint(x:60,y:60),withAttributes:[.font:UIFont.systemFont(ofSize:52),.foregroundColor:UIColor.black])
        }.cgImage!
        let result=try await ComicOCR.shared.read(image,source:"en",mode:.fastest)
        XCTAssertTrue(result.lines.map(\.text).joined(separator:" ").uppercased().contains("HELLO"))
    }
    func testActualPinnedPaddleModelReadsRasterText()async throws{
        try await ComicModelStore.shared.prepare(source:"en")
        let image=renderer(CGSize(width:640,height:180)).image{context in
            UIColor.white.setFill();context.fill(CGRect(x:0,y:0,width:640,height:180))
            ("HELLO WORLD" as NSString).draw(at:CGPoint(x:60,y:60),withAttributes:[.font:UIFont.systemFont(ofSize:52),.foregroundColor:UIColor.black])
        }.cgImage!
        let lines=try await ComicPaddle.shared.read(image,source:"en",careful:false)
        XCTAssertTrue(lines.map(\.text).joined(separator:" ").uppercased().contains("HELLO"))
    }
    func testDeletedProfileCannotReceiveLateCacheWrites()async throws{
        let owner=UUID();try await ComicMemory.shared.clear(profile:owner,deleting:true)
        do{try await ComicMemory.shared.save(Data("late".utf8),profile:owner,layer:.translation,key:"key");XCTFail("deleted profile accepted a late result")}catch is CancellationError{}catch{XCTFail(error.localizedDescription)}
    }
    func testImageSettingsAreIndependentOfPageTranslation()throws{
        var data=ProfileData();var page=TranslationPreferences();page.target="fr";data.settings.translation=page
        var comic=ComicPreferences();var image=TranslationPreferences();image.target="ar";comic.translation=image;data.settings.comicTranslation=comic
        let decoded=try JSONDecoder().decode(ProfileData.self,from:JSONEncoder().encode(data))
        XCTAssertEqual(decoded.settings.translation?.target,"fr");XCTAssertEqual(decoded.settings.comicTranslation?.translation?.target,"ar")
        XCTAssertEqual(ComicPreferences().mode,.fastest)
    }
    func testFailedNeighbourContextDoesNotCancelCurrentImage()async throws{
        let context=try await ComicTranslation.optionalContext("test"){()->Int in throw URLError(.timedOut)}
        XCTAssertNil(context)
        do{_ = try await ComicTranslation.optionalContext("test"){()->Int in throw CancellationError()};XCTFail("Cancellation must stop the image job")}catch is CancellationError{}catch{XCTFail(error.localizedDescription)}
    }
    func testImageFallbackAllowsPublicHTTPSAndNeverSendsCookies(){
        let page=URL(string:"https://reader.example.net/series/one")!
        let sameOrigin=URL(string:"https://reader.example.net/panel.png")!
        let cdn=URL(string:"https://images.example.org/panel.png")!
        let otherPort=URL(string:"https://reader.example.net:8443/panel.png")!
        let insecure=URL(string:"http://reader.example.net/panel.png")!
        let localPage=URL(string:"http://127.0.0.1:8765/comic")!
        let localImage=URL(string:"http://127.0.0.1:8765/panel.png")!
        let localCDN=URL(string:"http://127.0.0.2:8765/panel.png")!
        let privateAddress=URL(string:"http://192.168.1.1/panel.png")!
        let linkLocal=URL(string:"https://169.254.10.20/panel.png")!
        let privateName=URL(string:"https://printer.local/panel.png")!
        let publicIPv6=URL(string:"https://[2606:4700:4700::1111]/panel.png")!
        let privateIPv6=URL(string:"https://[fc00::1]/panel.png")!
        let multicastIPv6=URL(string:"https://[ff02::1]/panel.png")!
        XCTAssertTrue(ComicImageFetch.allows(sameOrigin,from:page))
        XCTAssertTrue(ComicImageFetch.allows(cdn,from:page),"Public HTTPS image CDNs may be cross-origin")
        XCTAssertFalse(ComicImageFetch.allows(otherPort,from:page))
        XCTAssertFalse(ComicImageFetch.allows(insecure,from:page),"Remote cleartext images are not fetched natively")
        XCTAssertTrue(ComicImageFetch.allows(localImage,from:localPage))
        XCTAssertTrue(ComicImageFetch.allows(localCDN,from:localPage),"Cross-origin loopback fixture remains testable")
        XCTAssertFalse(ComicImageFetch.allows(privateAddress,from:page))
        XCTAssertFalse(ComicImageFetch.allows(linkLocal,from:page))
        XCTAssertFalse(ComicImageFetch.allows(privateName,from:page))
        XCTAssertTrue(ComicImageFetch.allows(publicIPv6,from:page))
        XCTAssertFalse(ComicImageFetch.allows(privateIPv6,from:page))
        XCTAssertFalse(ComicImageFetch.allows(multicastIPv6,from:page))
        XCTAssertFalse(ComicImageFetch.allows(URL(string:"https://[::ffff:192.168.1.1]/panel.png")!,from:page))
        XCTAssertFalse(ComicImageFetch.allows(URL(string:"https://user:password@reader.example.net/panel.png")!,from:page))
        XCTAssertFalse(ComicImageFetch.sendsCookies(for:localImage,page:localPage))
        XCTAssertFalse(ComicImageFetch.sendsCookies(for:sameOrigin,page:page))
        XCTAssertTrue(ComicImageFetch.allowsRedirect(from:sameOrigin,to:cdn))
        XCTAssertFalse(ComicImageFetch.allowsRedirect(from:sameOrigin,to:insecure),"HTTPS downgrade must be rejected")
        XCTAssertFalse(ComicImageFetch.allowsRedirect(from:sameOrigin,to:URL(string:"https://192.168.1.1/panel.png")!))
        XCTAssertFalse(ComicImageFetch.allowsRedirect(from:sameOrigin,to:URL(string:"https://user:password@cdn.example.org/panel.png")!))
        XCTAssertTrue(ComicImageFetch.allowsRedirect(from:localImage,to:localCDN))
        XCTAssertFalse(ComicImageFetch.allowsRedirect(from:localImage,to:URL(string:"http://127.0.0.1:8766/next.png")!))
    }
    func testActualWebKitSwapRestoreAndStaleResults()async throws{
        let image=renderer(CGSize(width:200,height:100)).image{c in UIColor.white.setFill();c.fill(CGRect(x:0,y:0,width:200,height:100));("ORIGINAL" as NSString).draw(at:CGPoint(x:20,y:30),withAttributes:[.foregroundColor:UIColor.black,.font:UIFont.systemFont(ofSize:20)])}
        let original=try XCTUnwrap(image.pngData()).base64EncodedString(),replacement=try XCTUnwrap(ComicPixels.png(XCTUnwrap(image.cgImage))).base64EncodedString()
        let controller=WKUserContentController();controller.addUserScript(WKUserScript(source:ComicTranslation.script,injectionTime:.atDocumentEnd,forMainFrameOnly:false,in:ComicTranslation.world))
        let config=WKWebViewConfiguration();config.userContentController=controller;let view=WKWebView(frame:CGRect(x:0,y:0,width:390,height:700),configuration:config)
        let html="<html><body><picture><source id='source' srcset='data:image/png;base64,\(original)'><img id='panel' width='200' height='100' src='data:image/png;base64,\(original)'></picture></body></html>"
        view.loadHTMLString(html,baseURL:URL(string:"https://comic.invalid"))
        let deadline=Date().addingTimeInterval(15)
        while Date()<deadline{if (try? await view.callAsyncJavaScript("return !!globalThis.zeusComic && document.images[0].complete",arguments:[:],in:nil,contentWorld:ComicTranslation.world))as? Bool==true{break};try await Task.sleep(for:.milliseconds(100))}
        let result=try await view.callAsyncJavaScript("await document.images[0].decode();const s=zeusComic.scan(false);const c=s.items[0];return {id:c.id,revision:c.revision,generation:zeusComic.start()};",arguments:[:],in:nil,contentWorld:ComicTranslation.world)as? [String:Any]
        let id=try XCTUnwrap(result?["id"]as? String),revision=try XCTUnwrap(result?["revision"]as? String)
        let arguments:[String:Any]=["id":id,"revision":revision,"data":replacement,"region":["x":0,"y":0,"width":200,"height":100],"mark":"ar","generation":result?["generation"]as? Int ?? 0]
        let applied=try await view.callAsyncJavaScript("return await zeusComic.apply(id,revision,data,region,mark,generation)",arguments:arguments,in:nil,contentWorld:ComicTranslation.world)as? Bool
        XCTAssertEqual(applied,true)
        let isolated = try await view.evaluateJavaScript("typeof globalThis.zeusComic") as? String
        XCTAssertEqual(isolated,"undefined")
        let removedSource = try await view.evaluateJavaScript("document.querySelector('#source').hasAttribute('srcset')") as? Bool
        XCTAssertEqual(removedSource,false)
        _ = try await view.callAsyncJavaScript("zeusComic.restore()",arguments:[:],in:nil,contentWorld:ComicTranslation.world)
        let restoredSource = try await view.evaluateJavaScript("document.querySelector('#source').hasAttribute('srcset')") as? Bool
        XCTAssertEqual(restoredSource,true)
        let stale = try await view.callAsyncJavaScript("return await zeusComic.apply(id,revision,data,region,mark,generation)",arguments:arguments,in:nil,contentWorld:ComicTranslation.world) as? Bool
        XCTAssertEqual(stale,false)
    }
    func testBackgroundPanelsKeepOriginalPixelsAfterApplyingOneRegion()async throws{
        let raster=renderer(CGSize(width:200,height:100)).image{context in
            UIColor.red.setFill();context.fill(CGRect(x:0,y:0,width:200,height:50));UIColor.blue.setFill();context.fill(CGRect(x:0,y:50,width:200,height:50))
        }
        let original=try XCTUnwrap(raster.pngData()).base64EncodedString()
        let controller=WKUserContentController();controller.addUserScript(WKUserScript(source:ComicTranslation.script,injectionTime:.atDocumentEnd,forMainFrameOnly:false,in:ComicTranslation.world))
        let config=WKWebViewConfiguration();config.userContentController=controller
        let view=WKWebView(frame:CGRect(x:0,y:0,width:390,height:700),configuration:config)
        view.loadHTMLString("<html><body><div style='width:200px;height:100px;background-image:url(data:image/png;base64,\(original));background-size:100% 100%;background-repeat:no-repeat'></div></body></html>",baseURL:URL(string:"https://comic.invalid"))
        let deadline=Date().addingTimeInterval(15)
        while Date()<deadline{if (try? await view.callAsyncJavaScript("return !!globalThis.zeusComic",arguments:[:],in:nil,contentWorld:ComicTranslation.world))as? Bool==true{break};try await Task.sleep(for:.milliseconds(100))}
        let result=try await view.callAsyncJavaScript("const c=zeusComic.scan(false).items[0],g=zeusComic.start(),region={x:0,y:0,width:200,height:50};const transfer=await zeusComic.capture(c.id,c.revision,region),data=zeusComic.take(transfer.token,0,transfer.length);if(!await zeusComic.apply(c.id,c.revision,data,region,'ar',g))throw Error('apply failed');const again=zeusComic.scan(false).items;if(again.length!==1)throw Error('lost background candidate');const next=await zeusComic.capture(c.id,c.revision,{x:0,y:50,width:200,height:50}),bytes=zeusComic.take(next.token,0,next.length);zeusComic.restore();return bytes;",arguments:[:],in:nil,contentWorld:ComicTranslation.world)as? String
        let bytes=try XCTUnwrap(Data(base64Encoded:try XCTUnwrap(result))),image=try ComicPixels.decode(bytes),pixels=try XCTUnwrap(ComicPixels.rgba(image,width:200,height:50))
        XCTAssertLessThan(pixels[0],10);XCTAssertGreaterThan(pixels[2],245,"Second window must capture the original blue lower half")
        let restored=try await view.evaluateJavaScript("document.querySelector('div').style.backgroundImage")as? String
        XCTAssertTrue(restored?.contains("data:image/png")==true)
    }
    func testEndToEndImagesDoNotTranslateDOMAndFontChangesReuseOCRAndProvider()async throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model=BrowserModel(profiles:ProfileStore(root:root,downloadsRoot:root.appendingPathComponent("Downloads")),useBackgroundDownloads:false)
        model.data.settings.shieldsEnabled=false
        var provider=AIProviderConfiguration();provider.baseURL="http://127.0.0.1:8765/v1";provider.model="comic-"+UUID().uuidString;model.data.settings.aiProviders=[provider]
        var preferences=ComicPreferences();preferences.source="en";preferences.showUntranslated=true
        var translation=TranslationPreferences();translation.engine = .ai;translation.providerID=provider.id;preferences.translation=translation;model.data.settings.comicTranslation=preferences
        let tab=try XCTUnwrap(model.current);tab.url="https://comic-example.net/reader"
        let prepared=await model.prepare(tab),view=try XCTUnwrap(prepared),session=try XCTUnwrap(tab.comicTranslation)
        let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.first)
        let window=UIWindow(windowScene:scene);window.frame=scene.screen.bounds;window.rootViewController=UIViewController();view.frame=window.bounds;window.rootViewController?.view.addSubview(view);window.windowLevel = .normal+1;window.makeKeyAndVisible()
        defer{tab.dispose();window.isHidden=true;try? FileManager.default.removeItem(at:root)}
        let sourceURL=URL(string:"https://raw.githubusercontent.com/cobrapk8-cmyk/Zeus-Browser-Ascent-Repair-Public-v3/bc82343575ff5dc3c830ab6859a53fed343e39e7/.zeus-ci/fixtures/comic-hello-world.png")!
        view.loadHTMLString("<html><body><p id='text'>Original page text stays unchanged.</p><img id='comic' style='width:100%;height:auto' src='\(sourceURL.absoluteString)'></body></html>",baseURL:URL(string:tab.url))
        var deadline=Date().addingTimeInterval(20)
        while Date()<deadline{if (try? await view.callAsyncJavaScript("return !!globalThis.zeusComic && document.images[0]?.complete && document.images[0]?.naturalWidth>0",arguments:[:],in:nil,contentWorld:ComicTranslation.world))as? Bool==true{break};try await Task.sleep(for:.milliseconds(100))}
        session.start();deadline=Date().addingTimeInterval(35)
        while Date()<deadline && (session.running||session.completed==0) && session.error==nil{try await Task.sleep(for:.milliseconds(100))}
        XCTAssertNil(session.error);XCTAssertGreaterThan(session.imageFallbackCount,0,"Cross-origin HTTPS image must use native fallback");XCTAssertGreaterThan(session.ocrRuns,0);XCTAssertGreaterThan(session.completed,0)
        let unchanged=try await view.evaluateJavaScript("document.querySelector('#text').textContent")as? String
        XCTAssertEqual(unchanged,"Original page text stays unchanged.")
        let sourceBefore=try await view.evaluateJavaScript("document.images[0].src")as? String
        XCTAssertTrue(sourceBefore?.hasPrefix("blob:")==true)
        let endpoint=URL(string:"http://127.0.0.1:8765/translation-requests?model="+provider.model)!
        let (firstData,_)=try await URLSession.shared.data(from:endpoint)
        let before=try XCTUnwrap(JSONSerialization.jsonObject(with:firstData)as? [[String]])
        XCTAssertFalse(before.isEmpty);let ocrBefore=session.ocrRuns,completeBefore=session.completed
        preferences.fontScale=0.65;preferences.textColor="163B72";model.data.settings.comicTranslation=preferences
        session.pause();session.start();deadline=Date().addingTimeInterval(25)
        while Date()<deadline && (session.running||session.completed==completeBefore) && session.error==nil{try await Task.sleep(for:.milliseconds(100))}
        XCTAssertNil(session.error);XCTAssertGreaterThan(session.completed,completeBefore);XCTAssertEqual(session.ocrRuns,ocrBefore)
        let (secondData,_)=try await URLSession.shared.data(from:endpoint),after=try XCTUnwrap(JSONSerialization.jsonObject(with:secondData)as? [[String]])
        XCTAssertEqual(before.count,after.count,"Changing lettering must not spend another translation request")
        if let snapshot=try? await view.takeSnapshot(configuration:nil){let attachment=XCTAttachment(image:snapshot);attachment.name="Image-only end-to-end - Arabic custom color";attachment.lifetime = .keepAlways;add(attachment)}
        await session.restore()
        let original=try await view.evaluateJavaScript("document.images[0].src")as? String
        XCTAssertTrue(original?.hasPrefix("https://raw.githubusercontent.com/")==true,"Original HTTPS image source should be restored")
        try await ComicMemory.shared.clear(profile:model.profile.id)
    }
    func testCrossOriginNoReferrerImageTranslatesWhenServerRejectsReferer()async throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model=BrowserModel(profiles:ProfileStore(root:root,downloadsRoot:root.appendingPathComponent("Downloads")),useBackgroundDownloads:false)
        model.data.settings.shieldsEnabled=false
        var provider=AIProviderConfiguration();provider.baseURL="http://127.0.0.1:8765/v1";provider.model="referrer-"+UUID().uuidString;model.data.settings.aiProviders=[provider]
        var preferences=ComicPreferences();preferences.source="en";preferences.showUntranslated=true
        var translation=TranslationPreferences();translation.engine = .ai;translation.providerID=provider.id;preferences.translation=translation;model.data.settings.comicTranslation=preferences
        let tab=try XCTUnwrap(model.current),page=URL(string:"http://127.0.0.1:8765/comic-referrer-guard-page")!;tab.url=page.absoluteString
        let prepared=await model.prepare(tab),view=try XCTUnwrap(prepared),session=try XCTUnwrap(tab.comicTranslation)
        let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.first)
        let window=UIWindow(windowScene:scene);window.frame=scene.screen.bounds;window.rootViewController=UIViewController();view.frame=window.bounds;window.rootViewController?.view.addSubview(view);window.windowLevel = .normal+1;window.makeKeyAndVisible()
        defer{session.pause();tab.dispose();window.isHidden=true;try? FileManager.default.removeItem(at:root)}
        view.load(URLRequest(url:page))
        var ready=false,deadline=Date().addingTimeInterval(20)
        while Date()<deadline{if (try? await view.callAsyncJavaScript("return !!globalThis.zeusComic && document.images[0]?.complete && document.images[0]?.naturalWidth>0",arguments:[:],in:nil,contentWorld:ComicTranslation.world))as? Bool==true{ready=true;break};try await Task.sleep(for:.milliseconds(100))}
        guard ready else{XCTFail("The cross-origin no-referrer fixture image should load in WebKit");return}
        session.start();deadline=Date().addingTimeInterval(45)
        while Date()<deadline && session.completed==0 && session.error==nil{try await Task.sleep(for:.milliseconds(100))}
        guard session.completed>0 else{XCTFail("No cross-origin image was translated by the fixture provider");return}
        XCTAssertNil(session.error,"The image pipeline should succeed when Referer is rejected")
        XCTAssertGreaterThan(session.imageFallbackCount,0,"A tainted cross-origin canvas must use native image fallback")
        XCTAssertGreaterThan(session.ocrRuns,0)
        let requestsURL=URL(string:"http://127.0.0.1:8765/translation-requests?model="+provider.model)!
        let (requestData,_)=try await URLSession.shared.data(from:requestsURL),requests=try XCTUnwrap(JSONSerialization.jsonObject(with:requestData)as? [[String]])
        XCTAssertFalse(requests.isEmpty,"The configured fixture provider must receive the recognized text")
        let unchanged=try await view.evaluateJavaScript("document.querySelector('#text').textContent")as? String
        XCTAssertTrue(unchanged=="The article text remains untouched.","Image translation must not alter page text")
        await session.restore();try await ComicMemory.shared.clear(profile:model.profile.id)
    }
    func testLiveComixChapterTranslationWhenOptedIn()async throws{
        let gate=URL(string:"http://127.0.0.1:8765/live-smoke-enabled")!
        let (_,gateResponse)=try await URLSession.shared.data(from:gate)
        guard (gateResponse as? HTTPURLResponse)?.statusCode==200 else{throw XCTSkip("Opt-in live chapter smoke test")}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model=BrowserModel(profiles:ProfileStore(root:root,downloadsRoot:root.appendingPathComponent("Downloads")),useBackgroundDownloads:false)
        model.data.settings.shieldsEnabled=false
        var provider=AIProviderConfiguration();provider.baseURL="http://127.0.0.1:8765/v1";provider.model="live-"+UUID().uuidString;model.data.settings.aiProviders=[provider]
        var preferences=ComicPreferences();preferences.source="en";preferences.showUntranslated=true
        var translation=TranslationPreferences();translation.engine = .ai;translation.providerID=provider.id;preferences.translation=translation;model.data.settings.comicTranslation=preferences
        let page=URL(string:"https://comix.to/title/z0l20-god-level-assassin-im-the-shadow/11531282-chapter-148")!
        let tab=try XCTUnwrap(model.current);tab.url=page.absoluteString
        let prepared=await model.prepare(tab),view=try XCTUnwrap(prepared),session=try XCTUnwrap(tab.comicTranslation)
        let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.first)
        let window=UIWindow(windowScene:scene);window.frame=scene.screen.bounds;window.rootViewController=UIViewController();view.frame=window.bounds;window.rootViewController?.view.addSubview(view);window.windowLevel = .normal+1;window.makeKeyAndVisible()
        defer{session.pause();tab.dispose();window.isHidden=true;try? FileManager.default.removeItem(at:root)}
        view.load(URLRequest(url:page))
        var loadedImages=0,externalImages=false,deadline=Date().addingTimeInterval(45)
        while Date()<deadline{
            let probe=(try? await view.callAsyncJavaScript("const images=Array.from(document.images).filter(i=>i.complete&&i.naturalWidth>=120&&i.naturalHeight>=120);return {loaded:images.length,external:images.some(i=>{try{return new URL(i.currentSrc||i.src,location.href).host!==location.host}catch{return false}})}",arguments:[:],in:nil,contentWorld:ComicTranslation.world))as? [String:Any]
            loadedImages=probe?["loaded"]as? Int ?? 0;externalImages=probe?["external"]as? Bool ?? false
            if loadedImages>0{break};try await Task.sleep(for:.milliseconds(200))
        }
        guard loadedImages>0 else{XCTFail("The live chapter should expose at least one loaded comic image");return}
        session.start();deadline=Date().addingTimeInterval(105)
        while Date()<deadline && (session.completed==0 || (externalImages && session.imageFallbackCount==0)){try await Task.sleep(for:.milliseconds(200))}
        let applied=session.completed,fallbacks=session.imageFallbackCount,ocr=session.ocrRuns
        session.pause()
        XCTAssertGreaterThan(applied,0,"At least one live chapter image must be translated and applied")
        XCTAssertGreaterThan(ocr,0,"The live chapter must pass through on-device OCR")
        if externalImages{XCTAssertGreaterThan(fallbacks,0,"External chapter images must use the native fallback")}
        let endpoint=URL(string:"http://127.0.0.1:8765/translation-requests?model="+provider.model)!
        let (requestData,_)=try await URLSession.shared.data(from:endpoint),requests=try XCTUnwrap(JSONSerialization.jsonObject(with:requestData)as? [[String]])
        XCTAssertFalse(requests.isEmpty,"The configured provider fixture must receive recognized text")
        await session.restore();try await ComicMemory.shared.clear(profile:model.profile.id)
    }
    func testOCRAndTranslationCachesAreSeparateAndProfileScoped()async throws{
        let first=UUID(),second=UUID(),bytes=Data("reading".utf8)
        try await ComicMemory.shared.save(bytes,profile:first,layer:.reading,key:"same")
        let found=await ComicMemory.shared.data(profile:first,layer:.reading,key:"same"),other=await ComicMemory.shared.data(profile:second,layer:.reading,key:"same"),translation=await ComicMemory.shared.data(profile:first,layer:.translation,key:"same")
        XCTAssertEqual(found,bytes);XCTAssertNil(other);XCTAssertNil(translation);try await ComicMemory.shared.clear(profile:first)
    }
}
