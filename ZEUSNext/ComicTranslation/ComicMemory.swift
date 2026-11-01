import Foundation

actor ComicMemory {
    static let shared = ComicMemory()
    private var deleted=Set<UUID>()
    static let root = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ZEUSComicMemory")
    enum Layer: String { case reading, translation, rendered
        var limit:Int { self == .rendered ? 256*1024*1024 : 32*1024*1024 }
    }
    private func path(profile:UUID,layer:Layer,key:String)->URL {Self.root.appendingPathComponent(profile.uuidString).appendingPathComponent(layer.rawValue).appendingPathComponent(ComicIdentity.hash(key))}
    func data(profile:UUID,layer:Layer,key:String)->Data?{
        let url=path(profile:profile,layer:layer,key:key)
        guard let data=try? Data(contentsOf:url,options:.mappedIfSafe)else{return nil}
        try? FileManager.default.setAttributes([.modificationDate:Date()],ofItemAtPath:url.path);return data
    }
    func save(_ data:Data,profile:UUID,layer:Layer,key:String)throws{
        guard !deleted.contains(profile) else{throw CancellationError()}
        guard data.count<=layer.limit else{throw ComicFailure.message("الناتج يتجاوز سعة الحفظ.")}
        let url=path(profile:profile,layer:layer,key:key),folder=url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var root=Self.root;var values=URLResourceValues();values.isExcludedFromBackup=true;try root.setResourceValues(values)
        let files=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.fileSizeKey,.contentModificationDateKey]).map{u->(URL,Int,Date)in let v=try u.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey]);return(u,v.fileSize ?? 0,v.contentModificationDate ?? .distantPast)}.sorted{$0.2<$1.2}
        var bytes=files.reduce(0){$0+$1.1}
        for file in files where bytes+data.count>layer.limit{try FileManager.default.removeItem(at:file.0);bytes-=file.1}
        try data.write(to:url,options:[.atomic,.completeFileProtection])
    }
    func lookupText(_ segments:[TranslationSegment],namespace:String,profile:UUID)async->[String:String]{
        guard !deleted.contains(profile)else{return [:]}
        return await TranslationMemory.shared.lookup(segments,namespace:namespace,folder:Self.root.appendingPathComponent(profile.uuidString))
    }
    func saveText(_ values:[String:String],namespace:String,profile:UUID)async->Bool{
        guard !deleted.contains(profile)else{return false}
        let success=await TranslationMemory.shared.save(values,namespace:namespace,folder:Self.root.appendingPathComponent(profile.uuidString))
        if deleted.contains(profile){try? clear(profile:profile,deleting:true);return false}
        var root=Self.root;var metadata=URLResourceValues();metadata.isExcludedFromBackup=true;try? root.setResourceValues(metadata)
        return success
    }
    func clear(profile:UUID,deleting:Bool=false)throws{if deleting{deleted.insert(profile)};let folder=Self.root.appendingPathComponent(profile.uuidString);if FileManager.default.fileExists(atPath:folder.path){try FileManager.default.removeItem(at:folder)}}
    func clearAll()throws{if FileManager.default.fileExists(atPath:Self.root.path){try FileManager.default.removeItem(at:Self.root)}}
}
