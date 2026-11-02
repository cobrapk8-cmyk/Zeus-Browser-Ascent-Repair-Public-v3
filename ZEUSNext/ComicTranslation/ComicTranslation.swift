import Foundation
import Combine
import WebKit
import UIKit
import ImageIO
import CoreGraphics
import Darwin

@MainActor private final class ComicMessageRouter:NSObject,WKScriptMessageHandler{
    static let shared=ComicMessageRouter()
    let pages=NSMapTable<WKWebView,ComicTranslation>.weakToWeakObjects()
    func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage){if let view=message.webView{pages.object(forKey:view)?.receive(message)}}
}
@MainActor final class ComicTranslation:NSObject,ObservableObject{
    static let world=WKContentWorld.world(name:"ZEUS.ComicTranslation")
    static let script=Bundle.main.url(forResource:"comic-images",withExtension:"js").flatMap{try? String(contentsOf:$0,encoding:.utf8)} ?? ""
    weak var model:BrowserModel?
    weak var tab:BrowserTab?
    @Published var active=false
    @Published var running=false
    @Published var paused=false
    @Published var completed=0
    @Published var noTextRegions=0
    private(set) var ocrRuns=0
    private(set) var imageFallbackCount=0
    @Published var stage=""
    @Published var error:String?
    @Published var storageNotice:String?
    private var work:Task<Void,Never>?
    private var epoch=UUID()
    private var frames:[String:WKFrameInfo]=[:]
    private var documents:[String:ComicEnvelope]=[:]
    private var done=Set<String>()
    private var failed=Set<String>()
    private var pending=false
    private var readings:[String:ComicReading]=[:]
    private var textResults:[String:[TranslationSegment]]=[:]
    private var speechTexts:[String:String]=[:]
    private var fetched:[String:Data]=[:]
    private var fetchedOrder:[String]=[]
    private var resolvedScripts:[String:(String,Int)]=[:]
    private var observer:NSObjectProtocol?
    var preferences:ComicPreferences{model?.data.settings.comicTranslation ?? ComicPreferences()}
    var cardStatus:String{
        if running{return stage.isEmpty ? "جارٍ فحص الصور" : stage}
        if paused{return "الفحص متوقف مؤقتًا · \(completed) منطقة"}
        if error != nil{return completed>0 ? "نجاح جزئي · \(completed) منطقة" : "تعذّر إكمال الترجمة"}
        if completed>0{return "اكتمل الفحص الحالي · \(completed) منطقة"}
        if noTextRegions>0{return "لم يُعثر على حوار في الصور الحالية"}
        return "بانتظار الصور"
    }
    init(model:BrowserModel,tab:BrowserTab){self.model=model;self.tab=tab;super.init();observer=NotificationCenter.default.addObserver(forName:UIApplication.didReceiveMemoryWarningNotification,object:nil,queue:.main){[weak self]_ in Task{@MainActor in self?.pause();await ComicOCR.shared.purge();await ComicPaddle.shared.purge();await ComicLocalTranslator.shared.unload()}}}
    deinit{if let observer{NotificationCenter.default.removeObserver(observer)}}
    static func optionalContext<T>(_ label:String,operation:()async throws->T)async throws->T?{
        do{return try await operation()}catch is CancellationError{throw CancellationError()}catch{try Task.checkCancellation();let detail=error as NSError;NSLog("[ZEUS Comic] stage=\(label)-context result=unavailable domain=\(detail.domain) code=\(detail.code)");return nil}
    }
    func attach(to view:WKWebView,installScript:Bool=true){
        ComicMessageRouter.shared.pages.setObject(self,forKey:view)
        view.configuration.userContentController.removeScriptMessageHandler(forName:"zeusComic",contentWorld:Self.world)
        view.configuration.userContentController.add(ComicMessageRouter.shared,contentWorld:Self.world,name:"zeusComic")
        if installScript{view.configuration.userContentController.addUserScript(WKUserScript(source:Self.script,injectionTime:.atDocumentEnd,forMainFrameOnly:false,in:Self.world))}
    }
    func receive(_ message:WKScriptMessage){
        guard let model,let tab,message.webView===tab.webView,model.profile.id==tab.profileID,!model.requiresUnlock,let body=message.body as? [String:String],let document=body["document"],document.count<80 else{return}
        if frames.count<64||frames[document] != nil{frames[document]=message.frameInfo}
        if preferences.automatic,model.current?.id==tab.id,!active{start()}
        if active,model.current?.id==tab.id{schedule()}
    }
    private func valid(_ ticket:UUID)throws{
        try Task.checkCancellation()
        guard ticket==epoch,let model,let tab,model.profile.id==tab.profileID,!model.requiresUnlock,tab.webView != nil,model.tabs.contains(where:{$0===tab})else{throw CancellationError()}
    }
    private func call(_ code:String,args:[String:Any]=[:],frame:WKFrameInfo?)async throws->Any{
        guard let view=tab?.webView else{throw CancellationError()}
        return try await view.callAsyncJavaScript(code,arguments:args,in:frame?.isMainFrame==true ? nil:frame,contentWorld:Self.world) ?? NSNull()
    }
    func start(){guard let model,let tab,!tab.isHome,!model.requiresUnlock,model.profile.id==tab.profileID else{return};ComicFonts.registerAll();active=true;paused=false;error=nil;failed.removeAll();schedule()}
    func navigationStarted(){pause();active=false;completed=0;noTextRegions=0;ocrRuns=0;imageFallbackCount=0;done.removeAll();failed.removeAll();frames.removeAll();documents.removeAll();readings.removeAll();textResults.removeAll();speechTexts.removeAll();fetched.removeAll();resolvedScripts.removeAll();error=nil}
    func pause(){paused=true;epoch=UUID();work?.cancel();work=nil;running=false;pending=false;for frame in frames.values{Task{_ = try? await call("globalThis.zeusComic?.releaseAll?.()",frame:frame)}}}
    func becameVisible(){if active||preferences.automatic{start()}}
    func restore()async{pause();active=false;for frame in frames.values{_ = try? await call("globalThis.zeusComic?.restore()",frame:frame)};_ = try? await call("globalThis.zeusComic?.restore()",frame:nil);done.removeAll();failed.removeAll();completed=0;noTextRegions=0;error=nil}
    private func schedule(){if running{pending=true;return};guard active && !paused else{return};let ticket=epoch;running=true
        work=Task{[weak self]in guard let self else{return};defer{if epoch==ticket{running=false;work=nil;if pending{pending=false;schedule()}}}
            do{
                _ = try await call(Self.script,frame:nil)
                let id=try await call("return zeusComic.documentID",frame:nil)as? String ?? ""
                let children=frames.filter{!$0.value.isMainFrame}.map{($0.key,Optional($0.value))}
                for (document,frame) in [(id,Optional<WKFrameInfo>.none)]+children{
                    try valid(ticket)
                    do{try await sweep(document:document,frame:frame,ticket:ticket)}catch is CancellationError{throw CancellationError()}catch{if (error as NSError).domain==WKError.errorDomain,frame != nil{frames[document]=nil;continue};self.error=error.localizedDescription}
                }
            }catch is CancellationError{}catch{if epoch==ticket{self.error=error.localizedDescription}}
        }
    }
    private func sweep(document:String,frame:WKFrameInfo?,ticket:UUID)async throws{
        guard let model,let tab else{return}
        let owner=model.profile.id,prefs=preferences,translation=preferences.resolvedTranslation(model.data.settings)
        let provider=model.data.settings.aiProviders?.first{$0.id==translation.providerID}
        let translationMark=ComicIdentity.settings(prefs,translation:translation,provider:provider)+"|"+prefs.engine.rawValue+"|local:\(prefs.localModel)|"+ComicLocalTranslator.modelIdentity
        let mark=translationMark+"|renderer-v3|"+(prefs.fontName ?? "default")+"|\(prefs.fontScale)|"+(prefs.textColor ?? "auto")
        let persistent=translation.keepsTranslations && !model.profile.isPrivate
        let generation=try await call("return zeusComic.resume(mark)",args:["mark":mark],frame:frame)as? Int ?? 0
        let value=try await call("return zeusComic.scan(wake)",args:["wake":prefs.readAhead],frame:frame)
        let data=try JSONSerialization.data(withJSONObject:value),envelope=try JSONDecoder().decode(ComicEnvelope.self,from:data)
        guard envelope.document==document else{return};documents[document]=envelope
        let ordered=envelope.items.filter{!$0.pending&&$0.width>0&&$0.height>0}.sorted{a,b in
            let d1=max(0,a.y-envelope.scroll-envelope.viewport,envelope.scroll-a.y-a.h),d2=max(0,b.y-envelope.scroll-envelope.viewport,envelope.scroll-b.y-b.h);return d1<d2
        }
        // Bounded sweep; rescan geometry before the next window after a scroll.
        for candidate in ordered.prefix(prefs.readAhead ? 16:4){
            try valid(ticket)
            let allRegions=ComicGeometry.regions(width:candidate.width,height:candidate.height,maximumPixels:7_000_000)
            let regions=ComicGeometry.prioritized(allRegions,candidate:candidate,scroll:envelope.scroll,viewport:envelope.viewport,readAhead:prefs.readAhead)
            if allRegions.isEmpty{failed.insert(candidate.id);continue}
            for region in regions{
                let job="\(document)|\(candidate.id)|\(candidate.revision)|\(region.y)|\(mark)"
                if done.contains(job)||failed.contains(job){continue}
                if try await call("return zeusComic.has(id,revision,mark)",args:["id":candidate.id,"revision":candidate.revision,"mark":mark],frame:frame)as? Bool==true{done.insert(job);continue}
                do{
                    stage="جلب الصورة"
                    if !prefs.showUntranslated{_ = try await call("zeusComic.hold(id,revision)",args:["id":candidate.id,"revision":candidate.revision],frame:frame)}
                    let bytes=try await capture(candidate,region:region,frame:frame,ticket:ticket)
                    try valid(ticket)
                    let center=try await Task.detached{try ComicPixels.decode(bytes)}.value
                    let neighbours=ComicWindow.neighbours(of:candidate,in:envelope.items)
                    var before:CGImage?,after:CGImage?
                    let contextRows=max(0,min(256,(8_000_000/center.width-center.height)/2))
                    if contextRows>0,region.y==0,let previous=neighbours.before{
                        before=try await Self.optionalContext("previous"){
                            let height=min(previous.height,max(1,contextRows*previous.width/center.width)),area=ComicRegion(y:previous.height-height,width:previous.width,height:height,coreTop:0,coreBottom:height)
                            let context=try await capture(previous,region:area,frame:frame,ticket:ticket)
                            return try await Task.detached{try ComicPixels.decode(context)}.value
                        }
                    }
                    if contextRows>0,region.y+region.height==candidate.height,let next=neighbours.after{
                        after=try await Self.optionalContext("next"){
                            let height=min(next.height,max(1,contextRows*next.width/center.width)),area=ComicRegion(y:0,width:next.width,height:height,coreTop:0,coreBottom:height)
                            let context=try await capture(next,region:area,frame:frame,ticket:ticket)
                            return try await Task.detached{try ComicPixels.decode(context)}.value
                        }
                    }
                    let window=try await Task.detached{try ComicWindow.join(center,before:before,after:after)}.value
                    let image=window.image,offset=window.offset
                    let imageHash=try await Task.detached{ComicIdentity.hash(try ComicPixels.png(image))}.value
                    let readingKey=imageHash+"|ocr-v4|\(prefs.source)|\(prefs.mode.rawValue)"
                    stage="قراءة الفقاعات"
                    let reading:ComicReading
                    if let saved=readings[readingKey]{reading=saved}
                    else if persistent,let stored=await ComicMemory.shared.data(profile:owner,layer:.reading,key:readingKey),let saved=try? JSONDecoder().decode(ComicReading.self,from:stored){reading=saved}
                    else{ocrRuns+=1;reading=try await ComicOCR.shared.read(image,source:prefs.source == "auto" ? (resolvedScripts[document].flatMap{$0.1%3==0 ? nil:$0.0} ?? "auto"):prefs.source,mode:prefs.mode)
                        NSLog("[ZEUS Comic] stage=ocr result=success lines=\(reading.lines.count) speeches=\(reading.speeches.count)")
                        try valid(ticket)
                        if persistent{do{try await ComicMemory.shared.save(JSONEncoder().encode(reading),profile:owner,layer:.reading,key:readingKey)}catch{storageNotice="تعذّر حفظ قراءة الصورة؛ ستظل الجلسة الحالية متاحة."}}
                    }
                    if readings.count>=128{readings.removeAll()};readings[readingKey]=reading
                    let vote=resolvedScripts[document];resolvedScripts[document]=(reading.language,(vote?.1 ?? 0)+1)
                    try valid(ticket)
                    // A speech touching this core is rendered from its complete context,
                    // then clipped to this core. Its neighbour renders the other half.
                    let core=reading.speeches.filter{$0.rect.maxY>CGFloat(region.coreTop+offset)&&$0.rect.minY<CGFloat(region.coreBottom+offset)}
                    if core.isEmpty{noTextRegions+=1;done.insert(job);_ = try await call("zeusComic.release(id)",args:["id":candidate.id],frame:frame);continue}
                    stage="ترجمة الحوار"
                    let segments=core.map{TranslationSegment(id:$0.id,text:$0.text)}
                    let translationKey=readingKey+"|\(translationMark)"
                    let translated:[TranslationSegment]
                    if let saved=textResults[translationKey]{translated=saved}
                    else if persistent,let stored=await ComicMemory.shared.data(profile:owner,layer:.translation,key:translationKey),let saved=try? JSONDecoder().decode([TranslationSegment].self,from:stored){translated=saved}
                    else{NSLog("[ZEUS Comic] stage=provider result=start segments=\(segments.count)")
                        translated=try await translateSpeeches(segments,reading:reading,namespace:translationMark+"|"+ComicIdentity.hash(envelope.url),profile:owner,persistent:persistent,preferences:prefs,translation:translation,provider:provider,ticket:ticket)
                        NSLog("[ZEUS Comic] stage=provider result=success segments=\(translated.count)")
                        try valid(ticket)
                        if persistent{do{try await ComicMemory.shared.save(JSONEncoder().encode(translated),profile:owner,layer:.translation,key:translationKey)}catch{storageNotice="تعذّر حفظ الترجمة على الجهاز."}}
                    }
                    if textResults.count>=64{textResults.removeAll()};textResults[translationKey]=translated
                    try valid(ticket);stage="تنظيف الفقاعات ورسم العربية"
                    let renderedKey=translationKey+"|render-v3|\(prefs.fontName ?? "default")|\(prefs.fontScale)|\(prefs.textColor ?? "auto")"
                    let rendered:Data
                    if persistent,let stored=await ComicMemory.shared.data(profile:owner,layer:.rendered,key:renderedKey){rendered=stored}
                    else{rendered=try await Task.detached{let drawn=try ComicPixels.render(image,speeches:core,translations:translated,target:translation.target,fontName:prefs.fontName,fontScale:prefs.fontScale,textColor:prefs.textColor)
                        // Only this core is applied. Recognition context is retained above/below.
                        let rect=CGRect(x:0,y:region.coreTop+offset,width:region.width,height:region.coreBottom-region.coreTop)
                        guard let crop=drawn.cropping(to:rect)else{throw ComicFailure.message("تعذّر قص منطقة الرسم.")};return try ComicPixels.png(crop)}.value
                        try valid(ticket)
                        if persistent{do{try await ComicMemory.shared.save(rendered,profile:owner,layer:.rendered,key:renderedKey)}catch{storageNotice="تعذّر حفظ الصورة المترجمة؛ النص المحفوظ يظل متاحًا."}}
                    }
                    try valid(ticket);stage="عرض الترجمة"
                    let outputRegion:[String:Int]=["x":0,"y":region.y+region.coreTop,"width":region.width,"height":region.coreBottom-region.coreTop]
                    let applied=try await apply(rendered,candidate:candidate,region:outputRegion,mark:mark,generation:generation,frame:frame,ticket:ticket)
                    guard applied else{throw ComicFailure.message("لم يسمح الموقع بعرض الصورة المترجمة؛ بقي الأصل متاحًا.")}
                    done.insert(job);completed+=1;NSLog("[ZEUS Comic] stage=render result=applied")
                }catch is CancellationError{throw CancellationError()}catch{try valid(ticket);failed.insert(job);let detail=error as NSError;NSLog("[ZEUS Comic] stage=\(stage) result=failed domain=\(detail.domain) code=\(detail.code)");self.error=error.localizedDescription;_ = try? await call("zeusComic.release(id)",args:["id":candidate.id],frame:frame)}
                await Task.yield()
                if pending{return}
            }
        }
        // Mark only an image whose every region reached a terminal successful state.
        for candidate in ordered{let regions=ComicGeometry.regions(width:candidate.width,height:candidate.height,maximumPixels:7_000_000);if !regions.isEmpty&&regions.allSatisfy({done.contains("\(document)|\(candidate.id)|\(candidate.revision)|\($0.y)|\(mark)")}){_ = try? await call("zeusComic.mark(id,revision,mark)",args:["id":candidate.id,"revision":candidate.revision,"mark":mark],frame:frame)}}
        _=tab
    }
    private func translateSpeeches(_ segments:[TranslationSegment],reading:ComicReading,namespace:String,profile:UUID,persistent:Bool,preferences:ComicPreferences,translation:TranslationPreferences,provider:AIProviderConfiguration?,ticket:UUID)async throws->[TranslationSegment]{
        let namespace=namespace+"|"+reading.language
        func key(_ text:String)->String{ComicIdentity.hash(namespace+"\0"+text)}
        var values:[String:String]=[:]
        for segment in segments{if let value=speechTexts[key(segment.text)]{values[segment.text]=value}}
        if persistent{let saved=await ComicMemory.shared.lookupText(segments,namespace:namespace,profile:profile);values.merge(saved){_,saved in saved}}
        try valid(ticket)
        var unique=Set<String>()
        let missing=segments.filter{values[$0.text]==nil&&unique.insert($0.text).inserted}
        if !missing.isEmpty{
            let preceding=reading.speeches.prefix(while:{$0.id != missing.first?.id}).suffix(4).map(\.text)
            let response=try await ComicTextTranslator.translate(missing,source:reading.language,target:translation.target,preferences:translation,provider:provider,secret:AISecretVault.read(profile:profile,provider:translation.secretKey(provider:provider)),local:preferences.localModel,engine:preferences.engine,engineSecret:AISecretVault.read(profile:profile,provider:"comic-"+preferences.engine.rawValue),context:preceding)
            try valid(ticket)
            let originals=Dictionary(uniqueKeysWithValues:missing.map{($0.id,$0.text)})
            var fresh:[String:String]=[:]
            for item in response{if let original=originals[item.id]{fresh[original]=item.text}}
            guard fresh.count==missing.count else{throw ComicFailure.message("رد الترجمة لا يطابق الفقاعات.")}
            values.merge(fresh){_,new in new}
            if persistent,!(await ComicMemory.shared.saveText(fresh,namespace:namespace,profile:profile)){storageNotice="تعذّر حفظ بعض النصوص؛ قد تحتاج مساحة إضافية."}
        }
        try valid(ticket)
        if speechTexts.count>=8000{speechTexts.removeAll()}
        for (text,value)in values{speechTexts[key(text)]=value}
        return try segments.map{segment in guard let value=values[segment.text]else{throw ComicFailure.message("ترجمة ناقصة.")};return TranslationSegment(id:segment.id,text:value)}
    }
    private func capture(_ candidate:ComicCandidate,region:ComicRegion,frame:WKFrameInfo?,ticket:UUID)async throws->Data{
        do{
            let result=try await call("return await zeusComic.capture(id,revision,region)",args:["id":candidate.id,"revision":candidate.revision,"region":["x":region.x,"y":region.y,"width":region.width,"height":region.height]],frame:frame)as? [String:Any]
            guard let token=result?["token"]as? String,let length=result?["length"]as? Int,length>0,length<=33_554_432 else{throw ComicFailure.message("حمولة الصورة غير صالحة.")}
            defer{Task{_ = try? await call("zeusComic.drop(token)",args:["token":token],frame:frame)}}
            var output=Data();output.reserveCapacity(length)
            for offset in stride(from:0,to:length,by:65536){try valid(ticket);guard let part=try await call("return zeusComic.take(token,offset,count)",args:["token":token,"offset":offset,"count":min(65536,length-offset)],frame:frame)as? String,let bytes=Data(base64Encoded:part)else{throw ComicFailure.message("انقطع نقل الصورة.")};output.append(bytes)}
            guard output.count==length else{throw ComicFailure.message("صورة ناقصة.")};return output
        }catch{
            try valid(ticket)
            guard candidate.kind=="image",let tab,let url=URL(string:candidate.source),["https","http"].contains(url.scheme),candidate.width>0,candidate.height>0 else{throw error}
            let data:Data,cacheKey=candidate.source+"|"+candidate.id+"|"+candidate.revision+"|"+(frame?.request.url?.absoluteString ?? tab.url)
            if let cached=fetched[cacheKey]{data=cached}else{NSLog("[ZEUS Comic] stage=webkit-capture result=fallback")
                data=try await ComicImageFetch.fetch(url,view:tab.webView,page:frame?.request.url ?? URL(string:tab.url));imageFallbackCount+=1
                NSLog("[ZEUS Comic] stage=image-fetch result=success bytes=\(data.count)");fetched[cacheKey]=data;fetchedOrder.removeAll{$0==cacheKey};fetchedOrder.append(cacheKey)
                while fetchedOrder.count>4||fetched.values.reduce(0,{$0+$1.count})>33_554_432{let old=fetchedOrder.removeFirst();fetched[old]=nil}}
            return try await Task.detached{let crop=try ComicPixels.decodeRegion(data,region:region,expectedHeight:candidate.height);return try ComicPixels.png(crop)}.value
        }
    }
    private func apply(_ data:Data,candidate:ComicCandidate,region:[String:Int],mark:String,generation:Int,frame:WKFrameInfo?,ticket:UUID)async throws->Bool{
        guard data.count<=33_554_432 else{throw ComicFailure.message("الصورة المرسومة أكبر من حد النقل.")}
        let token=UUID().uuidString
        _ = try await call("zeusComic.outputStart(token,length)",args:["token":token,"length":data.count],frame:frame)
        defer{Task{_ = try? await call("zeusComic.outputDrop(token)",args:["token":token],frame:frame)}}
        for start in stride(from:0,to:data.count,by:49152){try valid(ticket);_ = try await call("zeusComic.outputPart(token,offset,data)",args:["token":token,"offset":start,"data":data.subdata(in:start..<min(start+49152,data.count)).base64EncodedString()],frame:frame)}
        try valid(ticket)
        return try await call("return await zeusComic.outputApply(token,id,revision,region,mark,generation)",args:["token":token,"id":candidate.id,"revision":candidate.revision,"region":region,"mark":mark,"generation":generation],frame:frame)as? Bool ?? false
    }
}

private enum ComicImageFetchPolicy{
    static func allows(_ url:URL,from page:URL)->Bool{
        guard url.user==nil,url.password==nil,page.user==nil,page.password==nil,
              let host=url.host?.lowercased(),let pageHost=page.host?.lowercased(),
              let scheme=url.scheme?.lowercased(),let pageScheme=page.scheme?.lowercased(),
              ["https","http"].contains(scheme),["https","http"].contains(pageScheme) else{return false}
        if isLoopbackHost(host)||isLoopbackHost(pageHost){
            return scheme=="http"&&pageScheme=="http"&&isLoopbackHost(host)&&isLoopbackHost(pageHost)&&(url.port ?? 80)==(page.port ?? 80)
        }
        guard scheme=="https",url.port==nil||url.port==443,isPublicHost(host) else{return false}
        return true
    }
    static func sendsCookies(for _:URL,page _:URL)->Bool{false}
    static func allowsRedirect(from origin:URL,to url:URL)->Bool{
        guard url.user==nil,url.password==nil,
              let originHost=origin.host?.lowercased(),let host=url.host?.lowercased(),
              let originScheme=origin.scheme?.lowercased(),let scheme=url.scheme?.lowercased() else{return false}
        if isLoopbackHost(originHost)||isLoopbackHost(host){
            return originScheme=="http"&&scheme=="http"&&isLoopbackHost(originHost)&&isLoopbackHost(host)&&(origin.port ?? 80)==(url.port ?? 80)
        }
        return scheme=="https"&&(url.port==nil||url.port==443)&&isPublicHost(host)
    }
    static func isLoopbackHost(_ host:String)->Bool{
        let value=host.lowercased().trimmingCharacters(in:CharacterSet(charactersIn:"[]"))
        if value=="localhost"||value.hasSuffix(".localhost")||value=="::1"{return true}
        let parts=value.split(separator:".",omittingEmptySubsequences:false)
        guard parts.count==4,let first=Int(parts[0]),first==127 else{return false}
        return parts.allSatisfy{part in !part.isEmpty&&Int(part).map{(0...255).contains($0)}==true}
    }
    static func resolvesToPublicAddresses(_ host:String)->Bool{
        // All A/AAAA answers must be public; the connected peer is checked again after transfer.
        var hints=addrinfo();hints.ai_family=AF_UNSPEC;hints.ai_socktype=SOCK_STREAM
        var resolved:UnsafeMutablePointer<addrinfo>?
        let result=host.withCString{name in getaddrinfo(name,nil,&hints,&resolved)}
        guard result==0,let first=resolved else{return false}
        defer{freeaddrinfo(first)}
        var current:UnsafeMutablePointer<addrinfo>?=first;var found=false
        while let entry=current{
            if let address=entry.pointee.ai_addr{
                var numeric=[CChar](repeating:0,count:1025)
                let status=getnameinfo(address,entry.pointee.ai_addrlen,&numeric,socklen_t(numeric.count),nil,0,NI_NUMERICHOST)
                guard status==0,isPublicAddress(String(cString:numeric)) else{return false}
                found=true
            }
            current=entry.pointee.ai_next
        }
        return found
    }
    static func isSafeRemoteAddress(_ raw:String,origin:URL)->Bool{
        let address:String
        if raw.first=="["{address=String(raw.dropFirst().prefix{$0 != "]"})}
        else if raw.filter({$0==":"}).count==1,raw.contains("."){address=String(raw.split(separator:":",maxSplits:1)[0])}
        else{address=raw}
        if isLoopbackHost(origin.host ?? ""){return isLoopbackHost(address)}
        return isPublicAddress(address)
    }
    static func isPublicAddress(_ value:String)->Bool{
        if value.contains(":"){return isPublicIPv6(value)}
        return isPublicIPv4(value)
    }
    private static func isPublicHost(_ host:String)->Bool{
        let value=host.lowercased().trimmingCharacters(in:CharacterSet(charactersIn:"[]"))
        guard !value.isEmpty else{return false}
        if value.contains(":"){return isPublicIPv6(value)}
        let localSuffixes=["localhost","local","lan","internal","home.arpa","localdomain","test","example","invalid","onion","arpa"]
        if localSuffixes.contains(where:{value==$0||value.hasSuffix("."+$0)}){return false}
        let parts=value.split(separator:".",omittingEmptySubsequences:false),octets=parts.compactMap{Int($0)}
        if parts.count==4,octets.count==4,octets.allSatisfy({(0...255).contains($0)}){return isPublicIPv4(value)}
        if value.range(of:#"^(?:0x[0-9a-f]+|[0-9]+)(?:\.(?:0x[0-9a-f]+|[0-9]+))*$"#,options:.regularExpression) != nil{return false}
        return value.contains(".") && !value.hasSuffix(".")
    }
    private static func isPublicIPv4(_ value:String)->Bool{
        let parts=value.split(separator:".",omittingEmptySubsequences:false),octets=parts.compactMap{Int($0)}
        guard parts.count==4,octets.count==4,octets.allSatisfy({(0...255).contains($0)})else{return false}
        let a=octets[0],b=octets[1],c=octets[2]
        if a==0||a==10||a==127||a>=224{return false}
        if a==100&&(64...127).contains(b){return false}
        if a==169&&b==254{return false}
        if a==172&&(16...31).contains(b){return false}
        if a==192&&(b==168||(b==0&&(c==0||c==2))||(b==88&&c==99)){return false}
        if a==198&&((b==18||b==19)||(b==51&&c==100)){return false}
        if a==203&&b==0&&c==113{return false}
        return true
    }
    private static func isPublicIPv6(_ value:String)->Bool{
        var address=in6_addr()
        guard value.withCString({inet_pton(AF_INET6,$0,&address)})==1 else{return false}
        let bytes=withUnsafeBytes(of:address){Array($0)}
        if bytes.count==16,bytes[0]==0,bytes[1]==0,bytes[2]==0,bytes[3]==0,bytes[4]==0,bytes[5]==0,bytes[6]==0,bytes[7]==0,bytes[8]==0,bytes[9]==0,bytes[10]==0xff,bytes[11]==0xff{
            return isPublicIPv4(bytes[12...15].map{String($0)}.joined(separator:"."))
        }
        if bytes.count==16,bytes[0]==0,bytes[1]==0x64,bytes[2]==0xff,bytes[3]==0x9b,bytes[4...11].allSatisfy({$0==0}){
            return isPublicIPv4(bytes[12...15].map{String($0)}.joined(separator:"."))
        }
        guard bytes.count==16,(bytes[0]&0xe0)==0x20 else{return false}
        if bytes[0]==0x20&&bytes[1]==0x01{
            let second=(Int(bytes[2])<<8)|Int(bytes[3])
            if second<=0x01ff||second==0x0db8{return false}
        }
        if (bytes[0]==0x20&&bytes[1]==0x02)||(bytes[0]==0x3f&&(bytes[1]==0xfe||bytes[1]==0xff)){return false}
        return true
    }
}
@MainActor enum ComicImageFetch{
    static func allows(_ url:URL,from page:URL)->Bool{ComicImageFetchPolicy.allows(url,from:page)}
    static func sendsCookies(for url:URL,page:URL)->Bool{ComicImageFetchPolicy.sendsCookies(for:url,page:page)}
    static func allowsRedirect(from origin:URL,to url:URL)->Bool{ComicImageFetchPolicy.allowsRedirect(from:origin,to:url)}
    static func fetch(_ url:URL,view:WKWebView?,page:URL?=nil)async throws->Data{
        guard url.user==nil,url.password==nil,let view else{throw ComicFailure.message("تعذّر جلب صورة المصدر.")}
        guard let pageURL=page ?? view.url,ComicImageFetchPolicy.allows(url,from:pageURL) else{
            NSLog("[ZEUS Comic] stage=image-fetch result=blocked-policy")
            throw ComicFailure.message("تعذّر جلب الصورة: يلزم HTTPS لمضيف عام؛ ويُسمح بـHTTP على loopback للاختبارات فقط.")
        }
        if !ComicImageFetchPolicy.isLoopbackHost(url.host ?? ""){
            let host=url.host ?? ""
            // URLSession cannot pin DNS atomically; a rebind can trigger only a bounded unauthenticated GET, and its body is rejected before OCR/provider unless the actual peer is public.
            let resolvedIsPublic=await Task.detached(priority:.utility){ComicImageFetchPolicy.resolvesToPublicAddresses(host)}.value
            guard resolvedIsPublic else{NSLog("[ZEUS Comic] stage=image-fetch result=unsafe-dns");throw ComicFailure.message("أُوقف جلب الصورة لأن اسم المصدر لا يشير إلى عناوين إنترنت عامة.")}
        }
        let redirects=ComicImageRedirects(origin:url)
        let configuration=URLSessionConfiguration.ephemeral;configuration.httpCookieStorage=nil;configuration.httpShouldSetCookies=false;configuration.urlCache=nil
        let session=URLSession(configuration:configuration,delegate:redirects,delegateQueue:nil);defer{session.invalidateAndCancel()}
        var request=URLRequest(url:url);request.httpShouldHandleCookies=false
        request.setValue(nil,forHTTPHeaderField:"Cookie");request.setValue(nil,forHTTPHeaderField:"Authorization");request.setValue(nil,forHTTPHeaderField:"Referer")
        request.setValue("image/*,*/*;q=0.8",forHTTPHeaderField:"Accept")
        let (file,response)=try await session.download(for:request)
        defer{try? FileManager.default.removeItem(at:file)}
        guard redirects.remoteAddressesAreSafe else{NSLog("[ZEUS Comic] stage=image-fetch result=unsafe-peer");throw ComicFailure.message("أُوقف جلب الصورة لأن الاتصال لم يصل إلى عنوان شبكة عام آمن.")}
        let status=(response as? HTTPURLResponse)?.statusCode ?? 0
        let mime=response.mimeType?.lowercased() ?? ""
        guard status==200,mime.hasPrefix("image/"),mime != "image/svg+xml" else{throw ComicFailure.message("لم يُرجع موقع الصورة ملفًا نقطيًا مدعومًا (HTTP \(status)).")}
        guard (try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max)<=33_554_432 else{throw ComicFailure.message("حجم صورة المصدر يتجاوز 32 MiB.")}
        return try await Task.detached{try Data(contentsOf:file,options:.mappedIfSafe)}.value
    }
}
private final class ComicImageRedirects:NSObject,URLSessionDownloadDelegate,@unchecked Sendable{
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL){}
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64){if totalBytesWritten>33_554_432||totalBytesExpectedToWrite>33_554_432{downloadTask.cancel()}}
    let origin:URL
    private let lock=NSLock()
    private var remoteAddresses:[String?]=[]
    init(origin:URL){self.origin=origin}
    var remoteAddressesAreSafe:Bool{
        lock.lock();let addresses=remoteAddresses;lock.unlock()
        return !addresses.isEmpty&&addresses.allSatisfy{guard let address=$0 else{return false};return ComicImageFetchPolicy.isSafeRemoteAddress(address,origin:origin)}
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didFinishCollecting metrics:URLSessionTaskMetrics){
        let addresses=metrics.transactionMetrics.map{$0.remoteAddress}
        lock.lock();remoteAddresses.append(contentsOf:addresses);lock.unlock()
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){
        guard let url=request.url,ComicImageFetchPolicy.allowsRedirect(from:origin,to:url) else{completionHandler(nil);return}
        if !ComicImageFetchPolicy.isLoopbackHost(url.host ?? ""),!ComicImageFetchPolicy.resolvesToPublicAddresses(url.host ?? ""){completionHandler(nil);return}
        var next=request;next.httpShouldHandleCookies=false;next.setValue(nil,forHTTPHeaderField:"Cookie");next.setValue(nil,forHTTPHeaderField:"Authorization");next.setValue(nil,forHTTPHeaderField:"Referer")
        completionHandler(next)
    }
}
