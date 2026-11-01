import SwiftUI
import CoreText
import UniformTypeIdentifiers

struct ComicSettingsSheet:View {
    @ObservedObject var model:BrowserModel
    @Environment(\.dismiss)private var dismiss
    @State private var importingFont=false
    @State private var importingModel=false
    @State private var key=""
    @State private var clientID=""
    @State private var customColor=""
    @State private var message:String?
    @State private var downloading=false
    @State private var redraw:Task<Void,Never>?
    private var prefs:ComicPreferences{model.data.settings.comicTranslation ?? ComicPreferences()}
    private var translation:TranslationPreferences{prefs.resolvedTranslation(model.data.settings)}
    var body:some View{
        NavigationStack{Form{
            Section("ترجمة صور المواقع"){
                Button("ترجمة الصور الآن",systemImage:"character.viewfinder"){model.current?.comicTranslation?.start();dismiss()}.accessibilityIdentifier("startImageTranslation")
                Toggle("ترجمة الصور تلقائيًا",isOn:binding(\.automatic))
                Picker("قراءة النص",selection:binding(\.mode)){ForEach(ComicReadingMode.allCases,id:\.self){Text($0.title).tag($0)}}
                Picker("لغة المصدر",selection:binding(\.source)){Text("اكتشاف تلقائي").tag("auto");ForEach(ComicPreferences.sourceLanguages,id:\.0){Text($0.1).tag($0.0)}}
                Picker("الترجمة إلى",selection:translationBinding(\.target)){ForEach(TranslationPreferences.languages,id:\.0){Text($0.1).tag($0.0)}}
                Toggle("عرض الأصل أثناء تجهيز الترجمة",isOn:binding(\.showUntranslated));Toggle("تجهيز الصور التالية أثناء القراءة",isOn:binding(\.readAhead))
                Text("هذا المسار مستقل عن ترجمة نص الصفحة. التعرف على النص محلي، وترسل النصوص فقط إلى المحرك المختار.").font(.footnote)
            }
            Section("محرك ترجمة الصور"){
                Toggle("نموذج محلي دون شبكة",isOn:binding(\.localModel))
                if prefs.localModel{Button("استيراد نموذج GGUF"){importingModel=true};Text("الحد 2 GiB. يجب أن يدعم النموذج لغاتك وإرجاع JSON. لا يتم التحويل إلى السحابة عند الفشل.").font(.footnote)}
                else{
                    Picker("المحرك",selection:binding(\.engine)){ForEach(ComicOnlineEngine.allCases,id:\.self){Text($0.title).tag($0)}}
                    if prefs.engine == .existing{
                        Picker("خدمة ZEUS",selection:translationBinding(\.engine)){ForEach(TranslationEngine.allCases,id:\.self){Text($0.title).tag($0)}}
                        if translation.engine == .ai{Picker("المزود",selection:translationBinding(\.providerID)){Text("اختر مزودًا").tag(nil as UUID?);ForEach(model.data.settings.aiProviders ?? []){Text($0.name).tag(Optional($0.id))}}}
                        Text("تُستخدم حسابات ومفاتيح مزودي ZEUS المحفوظة في هذا البروفايل. الاختيار واللغة هنا مستقلان عن نصوص الصفحات.").font(.footnote)
                    }
                    if prefs.engine.needsKey{if prefs.engine == .papago{TextField("Client ID",text:$clientID).textInputAutocapitalization(.never).autocorrectionDisabled()};SecureField("مفتاح الحساب",text:$key).textInputAutocapitalization(.never).autocorrectionDisabled();Button("حفظ في Keychain"){do{try AISecretVault.save(prefs.engine == .papago ? clientID+"\n"+key:key,profile:model.profile.id,provider:"comic-"+prefs.engine.rawValue);key="";message="حُفظ المفتاح."}catch{message=error.localizedDescription}}}
                    if translation.target=="ar",[ComicOnlineEngine.papago,.caiyun].contains(prefs.engine){Text("هذا المحرك لا يدعم العربية. استخدم Google أو Microsoft أو مزود ZEUS يدعمها.").font(.footnote)}
                    if prefs.engine == .papago{Text("Client ID في السطر الأول وClient Secret في الثاني.").font(.footnote)}
                }
            }
            Section("الخط والرسم"){
                Picker("الخط",selection:binding(\.fontName)){Text("الافتراضي").tag(nil as String?);ForEach(ComicFonts.names,id:\.self){Text($0).tag(Optional($0))}}
                Button("استيراد TTF / OTF / TTC"){importingFont=true}
                HStack{Text("حجم الخط");Slider(value:binding(\.fontScale),in:0.5...1.5,step:0.05);Text("\(Int(prefs.fontScale*100))٪")}
                Text("يُضبط الحجم داخل مساحة الفقاعة. تغيير الرسم يعيد استخدام النص والترجمة المحفوظين.").font(.footnote)
                Picker("لون الكلام",selection:binding(\.textColor)){Text("تلقائي حسب الخلفية").tag(nil as String?);Text("أسود").tag(Optional("101010"));Text("أبيض").tag(Optional("FAFAFA"));Text("أزرق داكن").tag(Optional("163B72"));Text("أحمر داكن").tag(Optional("8B2020"));if let value=prefs.textColor,!["101010","FAFAFA","163B72","8B2020"].contains(value){Text("مخصص").tag(Optional(value))}}
                TextField("لون مخصص مثل #163B72",text:$customColor).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("تطبيق اللون"){var p=prefs;p.textColor=customColor.isEmpty ? nil:customColor;save(p)}.disabled(!customColor.isEmpty && ComicPixels.color(customColor)==nil)
            }
            Section("نماذج OCR والحفظ"){
                Button(downloading ? "جارٍ تنزيل النماذج والتحقق منها…":"تنزيل نماذج اللغة المحددة"){
                    downloading=true;Task{defer{downloading=false};do{let source=prefs.source == "auto" ? "ko":prefs.source;try await ComicModelStore.shared.prepare(source:source);message="تم تنزيل النماذج والتحقق من بصمتها."}catch{message=error.localizedDescription}}
                }.disabled(downloading)
                Text("الوضع الأسرع يستخدم ML Kit المضمّن. الوضعان المتوازن والدقيق يحتاجان حزمة Paddle للغة المصدر؛ في الاكتشاف التلقائي نزّل حزم لغاتك باختيار كل لغة ثم التنزيل.").font(.footnote)
                Toggle("حفظ النتائج على الجهاز",isOn:translationBinding(\.retainTranslations,default:true))
                Button("مسح حفظ صور هذا البروفايل",role:.destructive){let id=model.profile.id;Task{do{try await ComicMemory.shared.clear(profile:id);message="مُسحت النتائج المحفوظة."}catch{message=error.localizedDescription}}}
                if let message{Text(message).font(.footnote)}
            }
        }.navigationTitle("ترجمة الصور والمانهوا").toolbar{ToolbarItem(placement:.confirmationAction){Button("تم"){dismiss()}}}}
        .onAppear{customColor=prefs.textColor ?? ""}
        .onChange(of:prefs.engine){_,_ in key="";clientID=""}
        .fileImporter(isPresented:$importingFont,allowedContentTypes:[.data]){result in do{let url=try result.get();let name=try ComicFonts.importFont(url);var p=prefs;p.fontName=name;save(p)}catch{message=error.localizedDescription}}
        .fileImporter(isPresented:$importingModel,allowedContentTypes:[.data]){result in Task{do{try await ComicLocalTranslator.shared.importModel(result.get());message="استُورد النموذج المحلي."}catch{message=error.localizedDescription}}}
    }
    private func save(_ value:ComicPreferences){model.data.settings.comicTranslation=value;model.persist();if let session=model.current?.comicTranslation,session.active{session.pause();redraw?.cancel();redraw=Task{do{try await Task.sleep(for:.milliseconds(250));try Task.checkCancellation();if session.active{session.start()}}catch{}}}}
    private func binding<T>(_ path:WritableKeyPath<ComicPreferences,T>)->Binding<T>{Binding(get:{prefs[keyPath:path]},set:{var p=prefs;p[keyPath:path]=$0;save(p)})}
    private func translationBinding<T>(_ path:WritableKeyPath<TranslationPreferences,T>)->Binding<T>{Binding(get:{translation[keyPath:path]},set:{var t=translation;t[keyPath:path]=$0;var p=prefs;p.translation=t;save(p)})}
    private func translationBinding(_ path:WritableKeyPath<TranslationPreferences,Bool?>,default fallback:Bool)->Binding<Bool>{Binding(get:{translation[keyPath:path] ?? fallback},set:{var t=translation;t[keyPath:path]=$0;var p=prefs;p.translation=t;save(p)})}
}
struct ComicTranslationCard:View{
    @ObservedObject var session:ComicTranslation
    let settings:()->Void
    var body:some View{if session.active{VStack(alignment:.leading,spacing:6){HStack{Image(systemName:"character.viewfinder");Text(session.running ? session.stage:"ترجمة الصور · \(session.completed) منطقة").font(.subheadline);Spacer();if session.running{ProgressView();Button("إيقاف"){session.pause()}}else{Button("متابعة"){session.start()}};Button("الأصل"){Task{await session.restore()}};Button(action:settings){Image(systemName:"slider.horizontal.3")}};if let error=session.error{Text(error).font(.caption).textSelection(.enabled)};if let notice=session.storageNotice{Text(notice).font(.caption)}}.padding(12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16)).padding(.horizontal,12).padding(.bottom,8).frame(maxWidth:700).environment(\.layoutDirection,.rightToLeft).accessibilityIdentifier("imageTranslationCard")}}
}
@MainActor enum ComicFonts{
    static let root=ComicModelStore.root.appendingPathComponent("Fonts")
    static var names:[String]{registerAll();return (try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil))?.compactMap{url in guard let descriptors=CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)as? [CTFontDescriptor],let first=descriptors.first else{return nil};return CTFontDescriptorCopyAttribute(first,kCTFontNameAttribute)as? String}.sorted() ?? []}
    static func registerAll(){for url in (try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? []{CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)}}
    static func importFont(_ url:URL)throws->String{
        let scoped=url.startAccessingSecurityScopedResource();defer{if scoped{url.stopAccessingSecurityScopedResource()}}
        guard ["ttf","otf","ttc"].contains(url.pathExtension.lowercased()),(try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max)<=16_777_216,let descriptors=CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)as? [CTFontDescriptor],let first=descriptors.first,let name=CTFontDescriptorCopyAttribute(first,kCTFontNameAttribute)as? String else{throw ComicFailure.message("اختر خط TTF أو OTF أو TTC صالحًا بحجم لا يتجاوز 16 MiB.")}
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let target=root.appendingPathComponent(UUID().uuidString+"."+url.pathExtension.lowercased());try FileManager.default.copyItem(at:url,to:target)
        var error:Unmanaged<CFError>?;guard CTFontManagerRegisterFontsForURL(target as CFURL,.process,&error)else{try? FileManager.default.removeItem(at:target);throw ComicFailure.message("تعذّر تسجيل الخط.")};return name
    }
}
