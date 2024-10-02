//
//  DownloadManager.swift
//  
//
//  Created by Dmytro Anokhin on 29/07/2020.
//

import Foundation
import AsyncExtensions

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
    private var cancellables = [UUID: Stream.Continuation]()
    
    deinit {
        let cache = cancellables.map(\.value)
        cancellables.removeAll()
        cache.forEach {
            $0.finish()
        }
    }
    
    private func cache(_ uuid: UUID, continuation: Stream.Continuation) {
        cancellables[uuid] = continuation
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.uncache(uuid)
            }
        }
    }
    
    private func uncache(_ uuid: UUID) {
        cancellables.removeValue(forKey: uuid)
    }
    
    func store(_ download: Download, coordinator: URLSessionCoordinator) -> Stream {
        let publisher: DownloadAsyncTask
        if let current = publishers[download.url] {
            publisher = current
            print("use exists task for \(download.url)")
        } else {
            publisher = DownloadAsyncTask(download: download, coordinator: coordinator)
            publishers[download.url] = publisher
            print("create new publisher for \(download.url)")
        }
        let uuid = download.id
        
        let action: @Sendable (Stream.Continuation) async -> Void = { [weak self] continuation in
            guard let self else { return }
            await self.cache(uuid, continuation: continuation)
            do {
                for try await item in publisher.statusSequece().compactMap({ $0 as? Result<DownloadInfo, DownloadError> }) {
                    switch item {
                    case .success(let info):
                        continuation.yield(info)
                        if case .completion = info {
                            continuation.finish()
                            return
                        }
                    case .failure(let error):
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        return AsyncThrowingStream { continuation in
            Task {
                await action(continuation)
            }
        }
    }
    
    func pop(_ uuid: UUID) {
        if let task = cancellables[uuid] {
            cancellables.removeValue(forKey: uuid)
            task.finish()
        }
    }
}
