//
//  DownloadManager.swift
//  
//
//  Created by Dmytro Anokhin on 29/07/2020.
//

import Foundation
//import AsyncExtensions

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public final class DownloadManager: Sendable {

    let coordinator: URLSessionCoordinator

    public init() {
        coordinator = URLSessionCoordinator(urlSessionConfiguration: .default)
    }
    
    public func download(for download: Download) -> AsyncStream<Result<DownloadInfo, Error>> {
        let coordinator = self.coordinator
        let publishers = self.publishers
        return AsyncStream { continuation in
            Task {
                let item = await publishers.store(download, coordinator: coordinator)
                do {
                    for try await value in item {
                        continuation.yield(.success(value))
                    }
                } catch {
                    continuation.yield(.failure(error))
                }
                continuation.finish()
            }
        }
    }
    
    private let publishers = PublishersHolder()
}

enum DownloadEventError: Error {
    case cancelled
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
actor PublishersHolder {
    typealias Stream = AsyncThrowingStream<DownloadInfo, DownloadError>
    
    private var publishers: [URL: DownloadAsyncTask] = [:]
    private var subscribers = [UUID: Stream.Continuation]()
    private var relations = [URL: Set<UUID>]()
    
    deinit {
        let cache = subscribers.map(\.value)
        subscribers.removeAll()
        cache.forEach {
            $0.finish()
        }
    }
    
    private func cache(_ uuid: UUID, in url: URL, continuation: Stream.Continuation) {
        continuation.onTermination = { _ in
            Task { [weak self] in
                await self?.uncache(uuid)
            }
        }
        subscribers[uuid] = continuation
        relations[url] = (relations[url] ?? Set<UUID>()).union([uuid])
    }
    
    private func uncache(_ uuid: UUID) {
        if let (url, sets) = relations.first(where: { $0.value.contains(uuid) }) {
            relations[url] = sets.subtracting([uuid])
        }
        subscribers.removeValue(forKey: uuid)
    }
    
    private func broadcast(to download: Download, with result: Result<DownloadInfo, DownloadError>) {
        guard let downstreams = relations[download.url]?.compactMap({ subscribers[$0] }) else {
            return
        }
        for continuation in downstreams {
            switch result {
            case .success(let info):
                continuation.yield(info)
                if case .completion = info {
                    continuation.finish()
                }
            case .failure(let error):
                continuation.finish(throwing: error)
            }
        }
    }
    
    func store(_ download: Download, coordinator: URLSessionCoordinator) -> Stream {
        let publisher: DownloadAsyncTask
        let newTask: Bool
        if let current = publishers[download.url] {
            publisher = current
            newTask = false
            print("use exists task for \(download.url)")
        } else {
            publisher = DownloadAsyncTask(download: download, coordinator: coordinator)
            publishers[download.url] = publisher
            newTask = true
            print("create new publisher for \(download.url)")
        }
        return AsyncThrowingStream { continuation in
            cache(download.id, in: download.url, continuation: continuation)
            if newTask {
                Task {
                    do {
                        for try await item in publisher.start().compactMap({ $0 as? Result<DownloadInfo, DownloadError> }) {
                            broadcast(to: download, with: item)
                        }
                    } catch {
                        broadcast(to: download, with: .failure(error))
                    }
                }
            }
        }
    }
}
