//
//  DownloadTask.swift
//  
//
//  Created by Dmytro Anokhin on 08/07/2020.
//

import Foundation

@globalActor
public actor DownloadTaskActor {
    public static let shared = DownloadTaskActor()
}

/// `DownloadTask` is a wrapper around `URLSessionTask` that accumulates received data in a memory buffer.
final class DownloadTask: Sendable {
    @DownloadTaskActor
    final class Observer {

        private var receiveResponse: DownloadReceiveResponse?

        func notifyReceiveResponse() {
            receiveResponse?(download)
        }

        private var receiveData: DownloadReceiveData?

        func notifyReceiveData(_ data: Data) {
            receiveData?(download, data)
        }

        private var reportProgress: DownloadReportProgress?

        func notifyReportProgress(_ progress: Float?) {
            reportProgress?(download, progress)
        }

        private var completion: DownloadCompletion?

        func notifyCompletion(_ result: Result<DownloadResult, DownloadError>) {
            completion?(download, result)
        }

        public let download: Download

        init(download: Download, receiveResponse: DownloadReceiveResponse?, receiveData: DownloadReceiveData?, reportProgress: DownloadReportProgress?, completion: DownloadCompletion?) {
            self.download = download
            self.receiveResponse = receiveResponse
            self.receiveData = receiveData
            self.reportProgress = reportProgress
            self.completion = completion
        }
    }
    
    let download: Download
    
    let urlSessionTask: URLSessionTask

    let observer: Observer

    init(download: Download, urlSessionTask: URLSessionTask, observer: Observer) {
        self.download = download
        self.urlSessionTask = urlSessionTask
        self.observer = observer
    }

    func complete(withError error: Error? = nil) {
        Task { @DownloadTaskActor in
//            guard let self else { return }
            if let error = error {
                self.observer.notifyCompletion(.failure(error))
                return
            }

            switch self.download.destination {
                case .inMemory:
                    if let data = self.buffer {
                        let result = DownloadResult.data(data)
                        self.observer.notifyCompletion(.success(result))
                    }
                    else {
                        let error = URLError(.unknown)
                        self.observer.notifyCompletion(.failure(error))
                    }

                case .onDisk(let path):
                    let result = DownloadResult.file(path)
                    self.observer.notifyCompletion(.success(result))
            }
        }
    }

    func receive(response: URLResponse) {
        Task { @DownloadTaskActor [weak self] in
            guard let self else { return }
            self.progress = DownloadProgress(response: response)
            self.buffer = Data()
            self.observer.notifyReceiveResponse()
        }
    }

    func receive(data: Data) {
        Task { @DownloadTaskActor [weak self] in
            guard let self else { return }
            self.buffer?.append(data)
            self.observer.notifyReceiveData(data)
            self.observer.notifyReportProgress(self.progress?.percentage)
        }
    }

    func downloadProgress(received: Int64, expected: Int64) {
        Task { @DownloadTaskActor [weak self] in
            guard let self else { return }
            if self.progress == nil {
                self.progress = DownloadProgress()
            }

            self.progress?.totalBytesReceived = received
            self.progress?.totalBytesExpected = expected
            self.observer.notifyReportProgress(self.progress?.percentage)
        }
    }

    @DownloadTaskActor
    private var progress: DownloadProgress?

    @DownloadTaskActor
    private var buffer: Data?
}


extension DownloadTask : CustomStringConvertible {

    var description: String {
        "<DownloadTask \(Unmanaged.passUnretained(self).toOpaque()): download=\(download)>"
    }
}
