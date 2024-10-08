//
//  DownloadPublisher.swift
//  
//
//  Created by Dmytro Anokhin on 28/07/2020.
//

import Combine
import Log


@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public struct DownloadPublisher: Publisher {

    public typealias Output = DownloadInfo
    public typealias Failure = DownloadError

    public let download: Download

    public func receive<S>(subscriber: S) where S: Subscriber,
                                                DownloadPublisher.Failure == S.Failure,
                                                DownloadPublisher.Output == S.Input
    {
        let subscription = DownloadSubscription(subscriber: subscriber, download: download, coordinator: coordinator)
        subscriber.receive(subscription: subscription)
    }

    init(download: Download, coordinator: URLSessionCoordinator) {
        self.download = download
        self.coordinator = coordinator
    }

    private let coordinator: URLSessionCoordinator
}


@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
final class DownloadSubscription<SubscriberType: Subscriber>: Subscription where SubscriberType.Input == DownloadInfo, SubscriberType.Failure == DownloadError
{
    private var subscriber: SubscriberType?

    private let download: Download

    private unowned let coordinator: URLSessionCoordinator

    init(subscriber: SubscriberType, download: Download, coordinator: URLSessionCoordinator) {
        self.subscriber = subscriber
        self.download = download
        self.coordinator = coordinator
    }

    func request(_ demand: Subscribers.Demand) {
        guard demand > 0 else { return }

        log_debug(self, #function, "download.id = \(download.id), download.url = \(self.download.url)", detail: log_detailed)
        nonisolated(unsafe) let subscriber = subscriber
        let download = download
        let type = Self.self

        coordinator.startDownload(download,
            receiveResponse: { _ in
            },
            receiveData: {  _, _ in
            },
            reportProgress: { _, progress in
                let _ = subscriber?.receive(.progress(progress))
            },
            completion: { _, result in
                switch result {
                    case .success(let downloadResult):
                        switch downloadResult {
                            case .data(let data):
                                log_debug(type, #function, "download.id = \(download.id), download.url = \(download.url), downloaded \(data.count) bytes", detail: log_detailed)
                            case .file(let path):
                                log_debug(type, #function, "download.id = \(download.id), download.url = \(download.url), downloaded file to \(path)", detail: log_detailed)
                        }

                        let _ = subscriber?.receive(.completion(downloadResult))
                        subscriber?.receive(completion: .finished)

                    case .failure(let error):
                        log_debug(type, #function, "download.id = \(download.id), download.url = \(download.url), downloaded failed \(error)", detail: log_detailed)
                        subscriber?.receive(completion: .failure(error))
                }

//                self.manager.reset(download: self.download)
            })
    }

    func cancel() {
        log_debug(self, #function, "download.id = \(download.id), download.url = \(self.download.url)", detail: log_detailed)
        coordinator.cancelDownload(download)
//        manager.reset(download: download)
    }
}
