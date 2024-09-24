//
//  DownloadManager.swift
//  
//
//  Created by Dmytro Anokhin on 29/07/2020.
//

import Foundation
@preconcurrency import Combine
import AsyncExtensions

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public final class DownloadManager {

    let coordinator: URLSessionCoordinator

    public init() {
        coordinator = URLSessionCoordinator(urlSessionConfiguration: .default)
    }

    public typealias DownloadTaskPublisher = Publishers.Share<DownloadPublisher>

//    public func publisher(for download: Download) -> DownloadTaskPublisher {
//        sync {
//            let publisher = publishers[download] ?? DownloadPublisher(download: download, manager: self).share()
//            publishers[download] = publisher
//
//            return publisher
//        }
//    }
    
//    public func download(for download: Download) -> AsyncStream<Result<DownloadInfo, Error>> {
//        AsyncStream { continuation in
//            sync {
//                let current = publishers[download]
//                let publisher = current ?? DownloadPublisher(download: download, manager: self).share()
//                print("current downloader task for \(download.url) - \(current), publisher \(publisher)")
//                publishers[download] = publisher
//                var cancelHash: Int?
//                let cancellable = publisher.sink { [weak self] completion in
//                    switch completion {
//                    case .finished:
//                        break
//                    case .failure(let error):
//                        continuation.yield(with: .success(.failure(error)))
//                    }
//                    continuation.finish()
//                    if let cancelHash {
//                        self?.sync {
//                            guard let self else { return }
//                            if let cancel = self.cancellableSets.first(where: { $0.hashValue == cancelHash }) {
//                                self.cancellableSets.remove(cancel)
//                            }
//                            self.cancellableHashTable[download]?.removeAll(where: { $0 == cancelHash })
//                        }
//                    }
//                } receiveValue: { output in
//                    continuation.yield(.success(output))
//                }
//                cancellableSets.insert(cancellable)
//                cancelHash = cancellable.hashValue
//                var values = cancellableHashTable[download] ?? []
//                values.append(cancelHash!)
//                cancellableHashTable[download] = values
//            }
//        }
//    }
    
    public func download(for download: Download) -> AsyncStream<Result<DownloadInfo, Error>> {
        let coordinator = self.coordinator
        let publishers = self.publishers
        let task: @Sendable (AsyncStream<Result<DownloadInfo, Error>>.Continuation) async -> Void = { continuation in
            let _ = await publishers.store(download, coordinator: coordinator, action: { result in
                switch result {
                case .success(let info):
                    continuation.yield(.success(info))
                case .failure(let error):
                    continuation.yield(with: .success(.failure(error)))
                }
            })
        }
        return AsyncStream { continuation in
            Task {
                await task(continuation)
            }
        }
    }

//    public func reset(download: Download) {
//        async { [weak self] in
//            guard let self = self else {
//                return
//            }
//
//            self.publishers[download] = nil
//            if let hashValues = self.cancellableHashTable[download] {
//                let cancellables = self.cancellableSets.filter({ hashValues.contains($0.hashValue) })
//                for cancellable in cancellables {
//                    self.cancellableSets.remove(cancellable)
//                    cancellable.cancel()
//                }
//            }
//        }
//        Task {
//            await publishers.remove(download)
//        }
//    }

//    private var publishers: [Download: DownloadTaskPublisher] = [:]
    private let publishers = PublishersHolder()

    private let serialQueue = DispatchQueue(label: "DownloadManager.serialQueue")

//    private func async(_ closure: @escaping () -> Void) {
//        serialQueue.async(execute: closure)
//    }
//
//    private func sync<T>(_ closure: () -> T) -> T {
//        serialQueue.sync(execute: closure)
//    }
}

//@available(macOS 11.0, *)
//struct Downloader: AsyncSequence {
//    typealias AsyncIterator = Iterator
//    typealias Element = DownloadInfo
//    let download: Download
//    let manager: DownloadManager
//    
//    struct Iterator: AsyncIteratorProtocol {
//        let download: Download
//        let manager: DownloadManager
//        
//        func next() async throws -> Element? {
//            
//        }
//    }
//    
//    func makeAsyncIterator() -> Iterator {
//        Iterator(download: download, manager: manager)
//        
//        manager.coordinator.startDownload(download,
//                                          receiveResponse: { _ in
//        },
//                                          receiveData: {  _, _ in
//        },
//                                          reportProgress: { _, progress in
//            let _ = self.subscriber?.receive(.progress(progress))
//        },
//                                          completion: { [weak self] _, result in
//            guard let self = self else {
//                return
//            }
//            
//            switch result {
//            case .success(let downloadResult):
//                switch downloadResult {
//                case .data(let data):
//                    break
//                case .file(let path):
//                    break
//                }
//            case .failure(let error):
//                break
//            }
//            
//            self.manager.reset(download: self.download)
//        })
//    }
//}

enum DownloadEventError: Error {
    case cancelled
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
actor PublishersHolder: @unchecked Sendable {
    private var publishers: [URL: DownloadManager.DownloadTaskPublisher] = [:]
    private var cancellableHashTable = [UUID: AnyCancellable]()
    private var cancellables = [URL: Set<UUID>]()
    private let subject = AsyncBufferedChannel<UUID>()
    private var loaded = false
    
    deinit {
        subject.finish()
    }
    
    func store(_ download: Download, coordinator: URLSessionCoordinator, action: @escaping (Result<DownloadInfo, Error>) -> Void) -> DownloadManager.DownloadTaskPublisher {
        if !loaded {
            loaded = true
            let subject = self.subject
            Task {
                for await uuid in subject {
                    pop(uuid)
                }
                print("publisher obseration finished.")
            }
        }
        
        let publisher: Publishers.Share<DownloadPublisher>
        if let current = publishers[download.url] {
            publisher = current
            print("use exists task for \(download.url)")
        } else {
            publisher = DownloadPublisher(download: download, coordinator: coordinator).share()
            publishers[download.url] = publisher
            print("create new publisher for \(download.url)")
        }
        let uuid = download.id
        let subject = self.subject
        cancellableHashTable[uuid] = publisher
            .handleEvents(receiveCancel: {
                action(.failure(DownloadEventError.cancelled))
            }).sink { completion in
                switch completion {
                case .finished:
                    break
                case .failure(let error):
                    action(.failure(error))
                }
                
                subject.send(uuid)
            } receiveValue: { output in
                action(.success(output))
            }
        var uuids = cancellables[download.url] ?? []
        uuids.insert(uuid)
        cancellables[download.url] = uuids
        return publisher
    }
    
//    func remove(_ download: Download) {
//        publishers.removeValue(forKey: download)
//        for uuid in cancellables[download] ?? [] {
//            cancellableHashTable[uuid]?.cancel()
//            cancellableHashTable.removeValue(forKey: uuid)
//        }
//        cancellables.removeValue(forKey: download)
//    }
    
    func pop(_ uuid: UUID) {
        if let task = cancellableHashTable[uuid] {
            cancellableHashTable.removeValue(forKey: uuid)
            task.cancel()
        }
        
        for (key, value) in cancellables.filter({ $0.value.contains(uuid) }) {
            var next = value
            next.remove(uuid)
            cancellables[key] = next
        }
    }
}
