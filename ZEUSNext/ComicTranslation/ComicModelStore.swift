import Foundation
import CryptoKit

struct ComicModelArtifact: Codable { var name: String; var bytes: Int64; var url: String; var sha256: String }
actor ComicModelStore {
    static let shared = ComicModelStore()
    struct Catalog: Decodable { var version: Int; var models: [ComicModelArtifact] }
    static let root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ZEUSComicModels")
    static let catalog: [ComicModelArtifact] = {
        guard let url=Bundle.main.url(forResource:"comic-models",withExtension:"json"),let data=try? Data(contentsOf:url),let c=try? JSONDecoder().decode(Catalog.self,from:data),c.version==1 else{return []};return c.models
    }()
    private var loading: [String: Task<URL, Error>] = [:]
    func file(_ name: String, download: Bool) async throws -> URL {
        guard let artifact=Self.catalog.first(where:{$0.name==name}) else{throw ComicFailure.message("ملف نموذج OCR غير معروف: \(name)")}
        let destination=Self.root.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath:destination.path),try Self.valid(destination,artifact:artifact){return destination}
        guard download else{throw ComicFailure.message("نزّل حزمة OCR للغة المصدر من إعدادات ترجمة الصور أولًا.")}
        if let task=loading[name]{return try await task.value}
        let task=Task<URL,Error>{
            try FileManager.default.createDirectory(at:Self.root,withIntermediateDirectories:true)
            var directory=Self.root;var values=URLResourceValues();values.isExcludedFromBackup=true;try directory.setResourceValues(values)
            let delegate=ComicModelDownloadLimit(limit:artifact.bytes)
            let session=URLSession(configuration:.ephemeral,delegate:delegate,delegateQueue:nil);defer{session.invalidateAndCancel()}
            let (temporary,response)=try await session.download(from:URL(string:artifact.url)!)
            defer{try? FileManager.default.removeItem(at:temporary)}
            guard (response as? HTTPURLResponse)?.statusCode==200,try Self.valid(temporary,artifact:artifact) else{throw ComicFailure.message("فشل التحقق من حجم أو بصمة نموذج OCR؛ لم يُعتمد الملف.")}
            let part=Self.root.appendingPathComponent(name+".part")
            try? FileManager.default.removeItem(at:part);try FileManager.default.moveItem(at:temporary,to:part)
            try? FileManager.default.removeItem(at:destination);try FileManager.default.moveItem(at:part,to:destination)
            return destination
        }
        loading[name]=task
        defer{loading[name]=nil}
        return try await task.value
    }
    static func valid(_ url:URL,artifact:ComicModelArtifact)throws->Bool{
        guard try url.resourceValues(forKeys:[.fileSizeKey]).fileSize==Int(artifact.bytes)else{return false}
        let stream=try FileHandle(forReadingFrom:url);defer{try? stream.close()};var hash=SHA256()
        while let data=try stream.read(upToCount:1_048_576),!data.isEmpty{hash.update(data:data)}
        return hash.finalize().map{String(format:"%02x",$0)}.joined()==artifact.sha256
    }
    func prepare(source:String)async throws{
        let name=Self.recognizer(source)
        for file in ["det.onnx",name+".onnx",name+".yml"]{_ = try await self.file(file,download:true)}
    }
    static func recognizer(_ language:String)->String { if language.hasPrefix("ko"){return "korean"};if language.hasPrefix("ja")||language.hasPrefix("zh"){return "han"};if ["ar","fa","ur"].contains(where:language.hasPrefix){return "arabic"};if ["ru","uk","bg","sr"].contains(where:language.hasPrefix){return "cyrillic"};if language.hasPrefix("el"){return "greek"};if ["hi","mr","ne"].contains(where:language.hasPrefix){return "devanagari"};if language.hasPrefix("th"){return "thai"};if language.hasPrefix("ta"){return "tamil"};if language.hasPrefix("te"){return "telugu"};return "latin" }
    func removeAll()throws{try? FileManager.default.removeItem(at:Self.root)}
}
private final class ComicModelDownloadLimit:NSObject,URLSessionDownloadDelegate,@unchecked Sendable{
    let limit:Int64
    init(limit:Int64){self.limit=limit}
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL){}
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64){if totalBytesWritten>limit||totalBytesExpectedToWrite>limit{downloadTask.cancel()}}
}
