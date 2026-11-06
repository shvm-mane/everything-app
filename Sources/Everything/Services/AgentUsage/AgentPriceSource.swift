// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentPriceSource {
    static let remote = URL(string: "https://raw.githubusercontent.com/vorssaint/vorssaint-utils/main/Resources/agent-prices.json")!
    static let refreshInterval: TimeInterval = 86_400
    static let retryInterval: TimeInterval = 6 * 3_600
    private static let fileName = "agent-prices.json"

    static func bundled() -> AgentPriceList? {
        guard let url = Bundle.main.url(forResource: "agent-prices", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return AgentPriceList.decode(data)
    }

    private static var cacheURL: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent(fileName, isDirectory: false)
    }

    static func cached() -> (list: AgentPriceList, saved: Date)? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url),
              let list = AgentPriceList.decode(data) else { return nil }
        let saved = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return (list, saved ?? .distantPast)
    }

    static func save(_ data: Data) {
        guard let container = PrivateFileStore.containerURL, let url = cacheURL,
              PrivateFileStore.createDirectory(at: container) else { return }
        PrivateFileStore.write(data, to: url)
    }

    static func download(completion: @escaping ((data: Data, list: AgentPriceList)?) -> Void) {
        AgentDownload.start(remote, limit: AgentPriceList.maximumSize) { data in
            guard let data, let list = AgentPriceList.decode(data) else { completion(nil); return }
            completion((data, list))
        }
    }
}

private final class AgentDownload: NSObject, URLSessionDataDelegate {
    private let limit: Int
    private let host: String?
    private var data = Data()
    private var status = 0
    private let completion: (Data?) -> Void

    private init(limit: Int, host: String?, completion: @escaping (Data?) -> Void) {
        self.limit = limit
        self.host = host
        self.completion = completion
    }

    static func start(_ url: URL, limit: Int, completion: @escaping (Data?) -> Void) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("EVERYTHING/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let delegate = AgentDownload(limit: limit, host: url.host, completion: completion)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        session.dataTask(with: request).resume()
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let sameHost = request.url?.scheme == "https" && request.url?.host == host
        completionHandler(sameHost ? request : nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        status = (response as? HTTPURLResponse)?.statusCode ?? 0
        completionHandler(status == 200 ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        data.append(chunk)
        if data.count > limit { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        completion(error == nil && status == 200 && data.count <= limit ? data : nil)
    }
}
