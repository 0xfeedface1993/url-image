//
//  URLImageService+RemoteImage.swift
//  
//
//  Created by Dmytro Anokhin on 15/01/2021.
//

import Foundation
@preconcurrency import Combine
import Model
import DownloadManager

extension Published.Publisher: @unchecked Sendable where Output: Sendable { }

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension URLImageService {

    public struct RemoteImagePublisher: Publisher {

        public typealias Output = ImageInfo
        public typealias Failure = Error

        public func receive<S>(subscriber: S) where S: Subscriber,
                                                    RemoteImagePublisher.Failure == S.Failure,
                                                    RemoteImagePublisher.Output == S.Input {

            let subscription = RemoteImageSubscription(subscriber: subscriber, remoteImage: remoteImage)
            subscriber.receive(subscription: subscription)
        }

        let remoteImage: RemoteImage

        init(remoteImage: RemoteImage) {
            self.remoteImage = remoteImage
        }
    }

    final class RemoteImageSubscription<SubscriberType: Subscriber>: Subscription where SubscriberType.Input == ImageInfo,
                                                                                       SubscriberType.Failure == Error {

        private var subscriber: SubscriberType?

        private let remoteImage: RemoteImage

        init(subscriber: SubscriberType, remoteImage: RemoteImage) {
            self.subscriber = subscriber
            self.remoteImage = remoteImage
        }

        private var cancellable: AnyCancellable?
        private var task: Task<Void, Never>?
        private var task2: Task<Void, Never>?

        func request(_ demand: Subscribers.Demand) {
            guard demand > 0 else {
                return
            }
            
            let remote = remoteImage
            nonisolated(unsafe) let subscriber = subscriber
            
            let operation: @Sendable () async -> Void = {
                if #available(macOS 12.0, iOS 15, *) {
                    let state = await remote.loadingState
                    for await loadingState in state.values {
                        switch loadingState {
                        case .initial:
                            break
                            
                        case .inProgress:
                            break
                            
                        case .success(let transientImage):
                            let _ = subscriber?.receive(transientImage.info)
                            subscriber?.receive(completion: .finished)
                            
                        case .failure(let error):
                            subscriber?.receive(completion: .failure(error))
                        }
                    }
                } else {
                    // Fallback on earlier versions
                }
//                await remote.loadingState.sink(receiveValue: { loadingState in
//                    switch loadingState {
//                        case .initial:
//                            break
//
//                        case .inProgress:
//                            break
//
//                        case .success(let transientImage):
//                            let _ = subscriber?.receive(transientImage.info)
//                            subscriber?.receive(completion: .finished)
//
//                        case .failure(let error):
//                            subscriber?.receive(completion: .failure(error))
//                    }
//                })
            }
            
            task2 = Task(operation: operation)
//            cancellable = remote.loadingState.sink(receiveValue: { [weak self] loadingState in
//                guard let self = self else {
//                    return
//                }
//
//                switch loadingState {
//                    case .initial:
//                        break
//
//                    case .inProgress:
//                        break
//
//                    case .success(let transientImage):
//                        let _ = self.subscriber?.receive(transientImage.info)
//                        self.subscriber?.receive(completion: .finished)
//
//                    case .failure(let error):
//                        self.subscriber?.receive(completion: .failure(error))
//                }
//            })
            
            task = Task {
                await withTaskCancellationHandler {
                    await remote.load()
                } onCancel: {
                    Task {
                        await remote.cancel()
                    }
                }
            }
        }

        func cancel() {
            let remote = remoteImage
            Task {
                await remote.cancel()
            }
            task?.cancel()
            task2?.cancel()
            cancellable = nil
            task = nil
        }
    }

    @MainActor public func makeRemoteImage(url: URL, identifier: String?, options: URLImageOptions) -> RemoteImage {
        let inMemory = fileStore == nil

        let destination = makeDownloadDestination(inMemory: inMemory)
        let urlRequestConfiguration = options.urlRequestConfiguration ?? makeURLRequestConfiguration(inMemory: inMemory)

        let download = Download(url: url, destination: destination, urlRequestConfiguration: urlRequestConfiguration)

        return RemoteImage(service: self, download: download, identifier: identifier, options: options)
    }

    @MainActor public func remoteImagePublisher(_ url: URL, identifier: String?, options: URLImageOptions = URLImageOptions()) -> RemoteImagePublisher {
        let remoteImage = makeRemoteImage(url: url, identifier: identifier, options: options)
        return RemoteImagePublisher(remoteImage: remoteImage)
    }

    /// Creates download destination depending if download must happen in memory or on disk
    private func makeDownloadDestination(inMemory: Bool) -> Download.Destination {
        if inMemory {
            return .inMemory
        }
        else {
            let path = FileManager.default.tmpFilePathInCachesDirectory()
            return .onDisk(path)
        }
    }

    private func makeURLRequestConfiguration(inMemory: Bool) -> Download.URLRequestConfiguration {
        if inMemory {
            return Download.URLRequestConfiguration()
        }
        else {
            return Download.URLRequestConfiguration(allHTTPHeaderFields: nil,
                                                    cachePolicy: .reloadIgnoringLocalCacheData)
        }
    }
}
