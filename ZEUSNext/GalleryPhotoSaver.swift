import Foundation
import WebKit
import Photos
import ImageIO

final class BoundedGalleryImageDownload: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    static let maximumBytes = 16_777_216
    private let cookies: [HTTPCookie]
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var response: HTTPURLResponse?
    private var bytes = Data()
    private var session: URLSession?
    private var completed = false
    private let stateLock = NSLock()
    private var task: URLSessionDataTask?
    private var wasCancelled = false

    init(cookies: [HTTPCookie]) { self.cookies = cookies }

    func load(_ request: URLRequest, configuration: URLSessionConfiguration) async throws -> (Data, HTTPURLResponse) {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
                self.continuation = continuation
                let queue = OperationQueue()
                queue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                self.session = session
                let task = session.dataTask(with: request)
                stateLock.lock()
                self.task = task
                let cancelled = wasCancelled
                stateLock.unlock()
                if cancelled { task.cancel() } else { task.resume() }
            }
        }, onCancel: { self.cancel() })
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            completionHandler(.cancel)
            finish(.failure(URLError(.badServerResponse)))
            return
        }
        guard response.expectedContentLength <= Int64(Self.maximumBytes) || response.expectedContentLength < 0 else {
            completionHandler(.cancel)
            finish(.failure(URLError(.dataLengthExceedsMaximum)))
            return
        }
        self.response = http
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !completed else { return }
        guard data.count <= Self.maximumBytes - bytes.count else {
            dataTask.cancel()
            finish(.failure(URLError(.dataLengthExceedsMaximum)))
            return
        }
        bytes.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var next = request
        next.setValue(nil, forHTTPHeaderField: "Cookie")
        if let url = next.url {
            for (key, value) in DownloadFiles.cookieHeaders(cookies, for: url) { next.setValue(value, forHTTPHeaderField: key) }
        }
        completionHandler(next)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)); return }
        guard let response else { finish(.failure(URLError(.badServerResponse))); return }
        finish(.success((bytes, response)))
    }

    private func finish(_ result: Result<(Data, HTTPURLResponse), Error>) {
        guard !completed else { return }
        completed = true
        let continuation = self.continuation
        self.continuation = nil
        stateLock.lock()
        task = nil
        stateLock.unlock()
        session?.finishTasksAndInvalidate()
        session = nil
        switch result {
        case .success(let value): continuation?.resume(returning: value)
        case .failure(let error): continuation?.resume(throwing: error)
        }
    }

    private func cancel() {
        stateLock.lock()
        wasCancelled = true
        let task = self.task
        stateLock.unlock()
        task?.cancel()
    }
}

@MainActor enum GalleryPhotoSaver {
    static func authorize() async -> Bool {
        let status = await withCheckedContinuation { c in PHPhotoLibrary.requestAuthorization(for: .addOnly) { c.resume(returning: $0) } }
        return status == .authorized || status == .limited
    }
    static func save(address: String, store: WKWebsiteDataStore, source: WKWebView?) async throws {
        guard let url = URL(string: address) else { throw URLError(.badURL) }
        let path: URL
        if ["blob", "data"].contains(url.scheme ?? "") {
            guard let source else { throw URLError(.badURL) }
            if url.scheme == "data", address.utf8.count > BoundedGalleryImageDownload.maximumBytes * 3 + 4096 { throw URLError(.dataLengthExceedsMaximum) }
            let value = try await source.callAsyncJavaScript("const limit=\(BoundedGalleryImageDownload.maximumBytes);if(address.length>\(BoundedGalleryImageDownload.maximumBytes * 3 + 4096))throw Error('image too large');const response=await fetch(address);if(!response.ok)throw Error('image request failed');const reader=response.body?.getReader();if(!reader)throw Error('image stream unavailable');const chunks=[];let size=0;try{while(true){const part=await reader.read();if(part.done)break;size+=part.value.byteLength;if(size>limit){await reader.cancel();throw Error('image too large')}chunks.push(part.value)}}catch(error){try{await reader.cancel()}catch{}throw error}const blob=new Blob(chunks,{type:response.headers.get('content-type')||''});return await new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(r.result);r.onerror=reject;r.readAsDataURL(blob)});", arguments: ["address": address], in: nil, contentWorld: .page)
            guard let raw = value as? String, let encoded = raw.split(separator: ",", maxSplits: 1).last, let data = Data(base64Encoded: String(encoded)), data.count <= BoundedGalleryImageDownload.maximumBytes else { throw URLError(.cannotDecodeContentData) }
            path = FileManager.default.temporaryDirectory.appendingPathComponent("ZEUS-Photo-" + UUID().uuidString)
            do { try data.write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
            catch { try? FileManager.default.removeItem(at: path); throw error }
        } else {
            guard BrowserURL.isWeb(url) else { throw URLError(.unsupportedURL) }
            let cookies: [HTTPCookie] = await withCheckedContinuation { c in store.httpCookieStore.getAllCookies { c.resume(returning: $0) } }
            let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCache = nil
            let downloader = BoundedGalleryImageDownload(cookies: cookies)
            var request = URLRequest(url: url); request.allHTTPHeaderFields = DownloadFiles.cookieHeaders(cookies, for: url)
            if let page = source?.url, let origin = BrowserModel.origin(page) { request.setValue(origin + "/", forHTTPHeaderField: "Referer") }
            let (data, response) = try await downloader.load(request, configuration: config)
            guard response.statusCode == 200, data.count <= BoundedGalleryImageDownload.maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
            path = FileManager.default.temporaryDirectory.appendingPathComponent("ZEUS-Photo-" + UUID().uuidString + "." + ((response.suggestedFilename ?? "image.jpg") as NSString).pathExtension)
            do { try data.write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
            catch { try? FileManager.default.removeItem(at: path); throw error }
        }
        defer { try? FileManager.default.removeItem(at: path) }
        guard CGImageSourceCreateWithURL(path as CFURL, nil) != nil else { throw URLError(.cannotDecodeContentData) }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: path) } completionHandler: { success, error in
                if success { c.resume() } else { c.resume(throwing: error ?? URLError(.cannotCreateFile)) }
            }
        }
    }
}
