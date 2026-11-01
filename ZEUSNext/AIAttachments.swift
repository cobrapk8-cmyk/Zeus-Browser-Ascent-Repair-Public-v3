import Foundation
import UniformTypeIdentifiers
import ImageIO

enum AIImageAttachmentLimits {
    static let maximumFileBytes = 16_000_000
    static let maximumDimension: Int64 = 16_384
    static let maximumPixels: Int64 = 16_000_000

    static func validatedDimensions(width: Double, height: Double) throws -> (Int, Int) {
        guard width.isFinite, height.isFinite,
              width >= 1, height >= 1,
              width <= Double(maximumDimension), height <= Double(maximumDimension),
              width.rounded(.towardZero) == width, height.rounded(.towardZero) == height else {
            throw TranslationFailure.message("أبعاد الصورة غير صالحة أو تتجاوز الحد المسموح.")
        }
        let pixelWidth = Int64(width), pixelHeight = Int64(height)
        let (pixels, overflow) = pixelWidth.multipliedReportingOverflow(by: pixelHeight)
        guard !overflow, pixels <= maximumPixels else {
            throw TranslationFailure.message("الصورة كبيرة جدًا بعد فك الضغط؛ الحد الأقصى 16 مليون بكسل.")
        }
        return (Int(pixelWidth), Int(pixelHeight))
    }

    static func dimensions(in data: Data) throws -> (Int, Int) {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw TranslationFailure.message("تعذر قراءة أبعاد الصورة أو أن تنسيقها غير صالح.")
        }
        return try validatedDimensions(width: width.doubleValue, height: height.doubleValue)
    }
}

struct AIAttachment: Identifiable {
    let id = UUID()
    var name: String
    var mime: String
    var data: Data
    var width = 0
    var height = 0
    var isImage: Bool { mime.hasPrefix("image/") }

    static func validated(name: String, mime: String, data: Data) throws -> AIAttachment {
        guard data.count <= AIImageAttachmentLimits.maximumFileBytes else {
            throw TranslationFailure.message("الحد الأقصى للمرفق 16 ميجابايت.")
        }
        var item = AIAttachment(name: name, mime: mime, data: data)
        if item.isImage {
            let (width, height) = try AIImageAttachmentLimits.dimensions(in: data)
            item.width = width
            item.height = height
        }
        return item
    }

    static func load(_ url: URL) throws -> AIAttachment {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        guard (values.fileSize ?? Int.max) <= AIImageAttachmentLimits.maximumFileBytes else { throw TranslationFailure.message("الحد الأقصى للمرفق 16 ميجابايت.") }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try validated(name: url.lastPathComponent, mime: values.contentType?.preferredMIMEType ?? UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream", data: data)
    }
    var dataURL: String { "data:" + mime + ";base64," + data.base64EncodedString() }
}

extension AIProviderService {
    func chatGPTUpload(_ attachment: AIAttachment, secret: String) async throws -> (metadata: [String: Any], image: [String: Any]?) {
        let headers = try chatGPTHeaders(secret)
        let initURL = URL(string: "https://android.chat.openai.com/backend-api/files")!
        let value = try await AIHTTP.object(AIHTTP.request(initURL, method: "POST", body: ["file_name": attachment.name, "file_size": attachment.data.count, "mime_type": attachment.mime, "use_case": "multimodal"], headers: headers)) as? [String: Any]
        guard let fileID = value?["file_id"] as? String, let address = value?["upload_url"] as? String,
              let uploadURL = URL(string: address), uploadURL.scheme == "https", uploadURL.user == nil else { throw TranslationFailure.message("لم يُرجع ChatGPT رابط رفع صالحًا.") }
        var upload = URLRequest(url: uploadURL); upload.httpMethod = "PUT"; upload.httpBody = attachment.data
        upload.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type"); upload.setValue(attachment.mime, forHTTPHeaderField: "Content-Type")
        // Presigned storage receives only the selected file, never the account token.
        _ = try await AIHTTP.data(upload)
        let ack = URL(string: "https://android.chat.openai.com/backend-api/files/" + fileID + "/uploaded")!
        _ = try await AIHTTP.object(AIHTTP.request(ack, method: "POST", body: [:] as [String: String], headers: headers))
        let metadata: [String: Any] = ["id": fileID, "name": attachment.name, "mime_type": attachment.mime, "size": attachment.data.count]
        let image: [String: Any]? = attachment.isImage ? ["content_type": "image_asset_pointer", "asset_pointer": "file-service://" + fileID, "size_bytes": attachment.data.count, "width": max(1, attachment.width), "height": max(1, attachment.height)] : nil
        return (metadata, image)
    }
    func geminiUpload(_ attachment: AIAttachment, cookie: String) async throws -> String {
        let boundary = "ZEUS-" + UUID().uuidString
        let name = attachment.name.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\"", with: "_")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: \(attachment.mime)\r\n\r\n".utf8)
        body.append(attachment.data); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = try AIHTTP.request(URL(string: "https://content-push.googleapis.com/upload")!, method: "POST", headers: ["Cookie": cookie, "Origin": "https://gemini.google.com", "Referer": "https://gemini.google.com/", "X-Tenant-Id": "bard-storage", "Push-ID": "feeds/mcudyrk2a4khkz"])
        request.httpBody = body; request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
        let data = try await AIHTTP.data(request), uri = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard uri.hasPrefix("/") || uri.hasPrefix("https://") else { throw TranslationFailure.message("لم يُرجع Gemini معرّفًا صالحًا للملف المرفوع.") }; return uri
    }
}
