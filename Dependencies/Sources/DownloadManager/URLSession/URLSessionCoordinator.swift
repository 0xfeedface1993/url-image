//
//  URLSessionCoordinator.swift
//
//
//  Created by Dmytro Anokhin on 07/07/2020.
//

import Foundation
import Log

@globalActor
public actor URLSessionCoordinatorActor {
    public static let shared = URLSessionCoordinatorActor()
}


/// `URLSessionCoordinator` manages `URLSession` instance and forwards callbacks to responding `DownloadController` instances.
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
final class URLSessionCoordinator: Sendable {

    init(urlSessionConfiguration: URLSessionConfiguration) {
        let delegate = URLSessionDelegate()
        urlSession = URLSession(configuration: urlSessionConfiguration, delegate: delegate, delegateQueue: nil)

        Task { [weak self] in
            await self?.observer(delegate)
            print("url session observer finished.")
        }
    }
    
    func observer(_ delegate: URLSessionDelegate) async {
        for await state in delegate.taskStateStream() {
            switch state {
            case .didCompleteWithError(let urlSessionTask, let error):
                Task { @URLSessionCoordinatorActor in
                    let downloadTaskID = urlSessionTask.taskDescription!

                    guard let downloadTask = self.registry[downloadTaskID] else {
                        // This can happen when the task was cancelled
                        return
                    }

                    self.registry[downloadTaskID] = nil

                    if let error = error {
                        downloadTask.complete(withError: error)
                    }
                    else {
                        downloadTask.complete()
                    }
                }
            case .didReceiveResponse(let task, let response, let completion):
                Task { @URLSessionCoordinatorActor in
                    let downloadTaskID = task.taskDescription!

                    guard let downloadTask = self.registry[downloadTaskID] else {
                        // This can happen when the task was cancelled
                        completion(.cancel)
                        return
                    }

                    downloadTask.receive(response: response)
                    completion(.allow)
                }
            case .didReceiveData(let urlSessionTask, let data):
                Task { @URLSessionCoordinatorActor [weak self] in
                    guard let self else { return }
                    let downloadTaskID = urlSessionTask.taskDescription!

                    guard let downloadTask = self.registry[downloadTaskID] else {
                        // This can happen when the task was cancelled
                        return
                    }

                    downloadTask.receive(data: data)
                }
            case .didFinishDownloadingTo(let task, let location):
                await Task { @URLSessionCoordinatorActor in
                    let downloadTaskID = task.taskDescription!

                    guard let downloadTask = self.registry[downloadTaskID] else {
                        // This can happen when the task was cancelled
                        return
                    }

                    guard case Download.Destination.onDisk(let path) = downloadTask.download.destination else {
                        assertionFailure("Expected file path destination for download task")
                        return
                    }

                    let destination = URL(fileURLWithPath: path)
                    try? FileManager.default.moveItem(at: location, to: destination)
                }.value
            case .downloadTaskDidWriteData(let downloadTask, _, let totalBytesWritten, let totalBytesExpectedToWrite):
                Task { @URLSessionCoordinatorActor in
                    let downloadTaskID = downloadTask.taskDescription!

                    guard let downloadTask = self.registry[downloadTaskID] else {
                        // This can happen when the task was cancelled
                        return
                    }

                    downloadTask.downloadProgress(received: totalBytesWritten, expected: totalBytesExpectedToWrite)
                }
            }
        }
    }

    func startDownload(_ download: Download,
                       receiveResponse: @escaping DownloadReceiveResponse,
                       receiveData: @escaping DownloadReceiveData,
                       reportProgress: @escaping DownloadReportProgress,
                       completion: @escaping DownloadCompletion) {
        Task { @URLSessionCoordinatorActor [weak self] in
            guard let self else { return }
            log_debug(self, #function, "download.id = \(download.id), download.url: \(download.url)", detail: log_normal)

            let downloadTaskID = download.id.uuidString

            guard self.registry[downloadTaskID] == nil else {
                assertionFailure("Can not start \(download) twice")
                return
            }

            let observer = await DownloadTask.Observer(download: download, receiveResponse: receiveResponse, receiveData: receiveData, reportProgress: reportProgress, completion: completion)

            let downloadTask = self.makeDownloadTask(for: download, withObserver: observer)
            self.registry[downloadTaskID] = downloadTask

            downloadTask.urlSessionTask.resume()
        }
    }
    
    func startDownload(_ download: Download) -> AsyncStream<DownloadStatus> {
        AsyncStream { continuation in
            let downloadTaskID = download.id.uuidString
//            continuation.onTermination = { [weak self] termination in
//                Task { @URLSessionCoordinatorActor in
//                    guard let self else { return }
//                    self.registry.removeValue(forKey: downloadTaskID)
//                }
//            }
            Task { @URLSessionCoordinatorActor in
//                guard let self else { return }
                log_debug(self, #function, "download.id = \(download.id), download.url: \(download.url)", detail: log_normal)

                guard self.registry[downloadTaskID] == nil else {
                    assertionFailure("Can not start \(download) twice")
                    return
                }

                let observer = await DownloadTask.Observer(download: download) { _ in
                    
                } receiveData: { _, _ in
                    
                } reportProgress: { _, progress in
                    continuation.yield(.reportProgress(download: download, progress))
                } completion: { download, result in
                    continuation.yield(.completion(download: download, result))
                    continuation.finish()
                }
                
                let downloadTask = self.makeDownloadTask(for: download, withObserver: observer)
                self.registry[downloadTaskID] = downloadTask

                downloadTask.urlSessionTask.resume()
            }
        }
    }

    func cancelDownload(_ download: Download) {
        Task { @URLSessionCoordinatorActor [weak self] in
            self?.cancel(download)
        }
    }
    
    @URLSessionCoordinatorActor
    func cancel(_ download: Download) {
        log_debug(self, #function, "download.id = \(download.id), download.url: \(download.url)", detail: log_normal)

        let downloadTaskID = download.id.uuidString

        guard let downloadTask = self.registry[downloadTaskID] else {
            return
        }

        downloadTask.urlSessionTask.cancel()
        self.registry[downloadTaskID] = nil
    }

    // MARK: - Private

    private let urlSession: URLSession

    private func makeDownloadTask(for download: Download, withObserver observer: DownloadTask.Observer) -> DownloadTask {
        let urlSessionTask: URLSessionTask

        var request = URLRequest(url: download.url)
        request.allHTTPHeaderFields = download.urlRequestConfiguration.allHTTPHeaderFields

        switch download.destination {
            case .inMemory:
                urlSessionTask = urlSession.dataTask(with: request)
            case .onDisk:
                urlSessionTask = urlSession.downloadTask(with: request)
        }

        urlSessionTask.taskDescription = download.id.uuidString

        return DownloadTask(download: download, urlSessionTask: urlSessionTask, observer: observer)
    }

    private typealias DownloadTaskID = String

    @URLSessionCoordinatorActor
    private var registry: [DownloadTaskID: DownloadTask] = [:]
}
