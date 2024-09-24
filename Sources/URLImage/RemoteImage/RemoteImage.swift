//
//  RemoteImage.swift
//  
//
//  Created by Dmytro Anokhin on 25/08/2020.
//

import SwiftUI
import Combine
import Model
import DownloadManager
import ImageDecoder
import Log

let queue = DispatchQueue(label: "com.url.image.workitem")

@available(macOS 11.0, *)
final class RemoteImageWrapper: ObservableObject {
    @Published var remote: RemoteImage?
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public final class RemoteImage : ObservableObject, @unchecked Sendable {

    /// Reference to URLImageService used to download and store the image.
    unowned let service: URLImageService

    /// Download object describes how the image should be downloaded.
    let download: Download

    let identifier: String?

    let options: URLImageOptions
    
    var stateCancellable: AnyCancellable?
    var downloadTask: Task<Void, Never>?

    init(service: URLImageService, download: Download, identifier: String?, options: URLImageOptions) {
        self.service = service
        self.download = download
        self.identifier = identifier
        self.options = options
        self.stateCancellable = loadingStatePublisher
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] state in
                self?.slowLoadingState = state
            })

        log_debug(nil, #function, download.url.absoluteString)
        
    }

    deinit {
        stateCancellable?.cancel()
//        downloadTask?.cancel()
        log_debug(nil, #function, download.url.absoluteString, detail: log_detailed)
    }

    public typealias LoadingState = RemoteImageLoadingState

    /// External loading state used to update the view
//    @Published public private(set) var loadingState: LoadingState = .initial {
//        willSet {
//            log_debug(self, #function, "\(download.url) will transition from \(loadingState) to \(newValue)", detail: log_detailed)
//        }
//    }
    
    private(set) var loadingState = CurrentValueSubject<LoadingState, Never>(.initial)
    
    @Published public private(set) var slowLoadingState: LoadingState = .initial
    
    private var progressStatePublisher: AnyPublisher<RemoteImageLoadingState, Never> {
        loadingState
            .filter({ $0.isInProgress })
            .collect(.byTime(queue, .milliseconds(100)))
            .compactMap(\.last)
            .eraseToAnyPublisher()
    }
    
    private var nonProgressStatePublisher: AnyPublisher<RemoteImageLoadingState, Never> {
        loadingState
            .filter({ !$0.isInProgress })
            .eraseToAnyPublisher()
    }
    
    private var loadingStatePublisher: AnyPublisher<RemoteImageLoadingState, Never> {
        nonProgressStatePublisher
            .merge(with: progressStatePublisher)
            .scan(LoadingState.initial, { current, next in
                next.isInProgress && current.isComplete ? current:next
            })
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

//    public func load() {
//        guard !isLoading else {
//            return
//        }
//        
//        log_debug(self, #function, "Start load for: \(download.url)", detail: log_normal)
//        
//        isLoading = true
//        
//        switch options.fetchPolicy {
//        case .returnStoreElseLoad(let downloadDelay):
//            guard !isLoadedSuccessfully else {
//                // Already loaded
//                isLoading = false
//                return
//            }
//            
//            guard !loadFromInMemoryStore() else {
//                // Loaded from the in-memory store
//                isLoading = false
//                return
//            }
//            
//            // Disk lookup
//            //                scheduleReturnStored(afterDelay: nil) { [weak self] success in
//            //                    guard let self = self else { return }
//            //
//            //                    if !success {
//            //                        self.scheduleDownload(afterDelay: downloadDelay, secondStoreLookup: true)
//            //                    }
//            //                }
//            Task {
//                let success = await scheduleReturnStored(afterDelay: nil)
//                if !success {
//                    self.scheduleDownload(afterDelay: downloadDelay, secondStoreLookup: true)
//                }
//            }
//            
//        case .returnStoreDontLoad:
//            guard !isLoadedSuccessfully else {
//                // Already loaded
//                isLoading = false
//                return
//            }
//            
//            guard !loadFromInMemoryStore() else {
//                // Loaded from the in-memory store
//                isLoading = false
//                return
//            }
//            
//            // Disk lookup
//            //                scheduleReturnStored(afterDelay: nil) { [weak self] success in
//            //                    guard let self = self else { return }
//            //
//            //                    if !success {
//            //                        // Complete
//            //                        self.loadingState = .initial
//            //                        self.isLoading = false
//            //                    }
//            //                }
//            Task {
//                let success = await scheduleReturnStored(afterDelay: nil)
//                if !success {
//                    await updateLoadingState(.initial)
//                    await updateIsLoading(false)
//                }
//            }
//        }
//    }
    public func load() async {
        guard !isLoading else {
            return
        }
        
        log_debug(self, #function, "Start load for: \(download.url)", detail: log_normal)
        
        await updateIsLoading(true)
        
        switch options.fetchPolicy {
        case .returnStoreElseLoad(let downloadDelay):
            guard !isLoadedSuccessfully else {
                // Already loaded
                await updateIsLoading(false)
                return
            }
            
            guard !loadFromInMemoryStore() else {
                // Loaded from the in-memory store
                await updateIsLoading(false)
                return
            }
            
            let success = await scheduleReturnStored(afterDelay: nil)
            if !success {
                self.scheduleDownload(afterDelay: downloadDelay, secondStoreLookup: true)
            }
        case .returnStoreDontLoad:
            guard !isLoadedSuccessfully else {
                // Already loaded
                await updateIsLoading(false)
                return
            }
            
            guard !loadFromInMemoryStore() else {
                // Loaded from the in-memory store
                await updateIsLoading(false)
                return
            }
            
            let success = await scheduleReturnStored(afterDelay: nil)
            if !success {
                updateLoadingState(.initial)
                await updateIsLoading(false)
            }
        }
    }

    public func cancel() {
        guard isLoading else {
            return
        }

        log_debug(self, #function, "Cancel load for: \(download.url)", detail: log_normal)

        isLoading = false

        // Cancel publishers
        for cancellable in cancellables {
            cancellable.cancel()
        }

        cancellables.removeAll()

        delayedReturnStored?.cancel()
        delayedReturnStored = nil

        delayedDownload?.cancel()
        delayedDownload = nil
        
//        downloadTask?.cancel()
        downloadTask?.cancel()
        downloadTask = nil
    }

    /// Internal loading state
    private var isLoading: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private var delayedReturnStored: DispatchWorkItem?
    private var delayedDownload: DispatchWorkItem?
}


@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension RemoteImage {

    private var isLoadedSuccessfully: Bool {
        switch loadingState.value {
            case .success:
                return true
            default:
                return false
        }
    }

    /// Rerturn an image from the in memory store.
    ///
    /// Sets `loadingState` to `.success` if an image is in the in-memory store and returns `true`. Otherwise returns `false` without changing the state.
//    private func loadFromInMemoryStore() -> Bool {
//        guard let store = service.inMemoryStore else {
//            log_debug(self, #function, "Not using in memory store for \(download.url)", detail: log_normal)
//            return false
//        }
//
//        guard let transientImage: TransientImage = store.getImage(keys) else {
//            log_debug(self, #function, "Image for \(download.url) not in the in memory store", detail: log_normal)
//            return false
//        }
//
//        // Complete
//        self.loadingState = .success(transientImage)
//        log_debug(self, #function, "Image for \(download.url) is in the in memory store", detail: log_normal)
//
//        return true
//    }
    
    private func loadFromInMemoryStore() -> Bool {
        guard let store = service.inMemoryStore else {
            log_debug(self, #function, "Not using in memory store for \(download.url)", detail: log_normal)
            return false
        }

        guard let transientImage: TransientImage = store.getImage(keys) else {
            log_debug(self, #function, "Image for \(download.url) not in the in memory store", detail: log_normal)
            return false
        }

        // Complete
        self.updateLoadingState(.success(transientImage))
        log_debug(self, #function, "Image for \(download.url) is in the in memory store", detail: log_normal)

        return true
    }

//    private func scheduleReturnStored(afterDelay delay: TimeInterval?, completion: @escaping (_ success: Bool) -> Void) {
//        guard let delay = delay else {
//            // Read from store immediately if no delay needed
//            returnStored(completion)
//            return
//        }
//
//        delayedReturnStored?.cancel()
//        delayedReturnStored = DispatchWorkItem { [weak self] in
//            guard let self = self else { return }
//            self.returnStored(completion)
//        }
//
//        queue.asyncAfter(deadline: .now() + delay, execute: delayedReturnStored!)
//    }
    
    private func scheduleReturnStored(afterDelay delay: TimeInterval?) async -> Bool {
        guard let delay = delay else {
            // Read from store immediately if no delay needed
            return await returnStored()
        }
        
        if #available(iOS 16.0, macOS 13, *) {
            try? await Task.sleep(for: .seconds(delay))
        } else {
            // Fallback on earlier versions
            try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 * delay))
        }
        
        return await returnStored()
    }

    // Second store lookup is necessary for a case if the same image was downloaded by another instance of RemoteImage
//    private func scheduleDownload(afterDelay delay: TimeInterval? = nil, secondStoreLookup: Bool = false) {
//        guard let delay = delay else {
//            // Start download immediately if no delay needed
//            startDownload()
//            return
//        }
//
//        delayedDownload?.cancel()
//        delayedDownload = DispatchWorkItem { [weak self] in
//            guard let self = self else { return }
//
//            if secondStoreLookup {
//                self.returnStored { [weak self] success in
//                    guard let self = self else { return }
//
//                    if !success {
//                        self.startDownload()
//                    }
//                }
//            }
//            else {
//                self.startDownload()
//            }
//        }
//
//        queue.asyncAfter(deadline: .now() + delay, execute: delayedDownload!)
//    }
    
    private func scheduleDownload(afterDelay delay: TimeInterval? = nil, secondStoreLookup: Bool = false) {
        guard let _ = delay else {
            // Start download immediately if no delay needed
            Task {
                await startDownload()
            }
            return
        }
        
        if secondStoreLookup {
            Task {
                let success = await returnStored()
                if !success {
                    await startDownload()
                }
            }
        } else {
            Task {
                await startDownload()
            }
        }
    }

//    private func startDownload() {
//        loadingState = .inProgress(nil)
//
//        service.downloadManager.publisher(for: download)
//            .sink { [weak self] result in
//                guard let self = self else {
//                    return
//                }
//
//                switch result {
//                    case .finished:
//                        break
//
//                    case .failure(let error):
//                        // This route happens when download fails
//                        self.updateLoadingState(.failure(error))
//                }
//            }
//            receiveValue: { [weak self] info in
//                guard let self = self else {
//                    return
//                }
//
//                switch info {
//                    case .progress(let progress):
//                        self.updateLoadingState(.inProgress(progress))
//                    case .completion(let result):
//                        do {
//                            let transientImage = try self.service.decode(result: result,
//                                                                         download: self.download,
//                                                                         identifier: self.identifier,
//                                                                         options: self.options)
//                            self.updateLoadingState(.success(transientImage))
//                        }
//                        catch {
//                            // This route happens when download succeeds, but decoding fails
//                            self.updateLoadingState(.failure(error))
//                        }
//                }
//            }
//            .store(in: &cancellables)
//    }
    private func startDownload() async {
        updateLoadingState(.inProgress(nil))
        
        let infos = service.downloadManager.download(for: download)
        for await update in infos {
            switch update {
            case .success(let info):
                switch info {
                    case .progress(let progress):
                        updateLoadingState(.inProgress(progress))
                    case .completion(let result):
                        do {
                            let transientImage = try service.decode(result: result,
                                                                         download: download,
                                                                         identifier: identifier,
                                                                         options: options)
                            updateLoadingState(.success(transientImage))
                        } catch {
                            // This route happens when download succeeds, but decoding fails
                            updateLoadingState(.failure(error))
                        }
                }
            case .failure(let error):
                updateLoadingState(.failure(error))
            }
        }
    }

//    private func returnStored(_ completion: @escaping (_ success: Bool) -> Void) {
//        Task { @MainActor in
//            loadingState = .inProgress(nil)
//        }
//
//        guard let store = service.fileStore else {
//            completion(false)
//            return
//        }
//
//        store.getImagePublisher(keys, maxPixelSize: options.maxPixelSize)
//            .receive(on: DispatchQueue.main)
//            .catch { _ in
//                Just(nil)
//            }
//            .sink { [weak self] in
//                guard let self = self else {
//                    return
//                }
//
//                if let transientImage = $0 {
//                    log_debug(self, #function, "Image for \(self.download.url) is in the disk store", detail: log_normal)
//                    // Store in memory
//                    let info = URLImageStoreInfo(url: self.download.url,
//                                                 identifier: self.identifier,
//                                                 uti: transientImage.uti)
//
//                    self.service.inMemoryStore?.store(transientImage, info: info)
//
//                    // Complete
//                    self.loadingState = .success(transientImage)
//                    completion(true)
//                }
//                else {
//                    log_debug(self, #function, "Image for \(self.download.url) not in the disk store", detail: log_normal)
//                    completion(false)
//                }
//            }
//            .store(in: &cancellables)
//    }
    
    @MainActor
    private func returnStored() async -> Bool {
        loadingState.send(.inProgress(nil))

        guard let store = service.fileStore else {
            return false
        }

        let transientImage = try? await store.getImage(keys, maxPixelSize: options.maxPixelSize)
        guard let transientImage else {
            log_debug(self, #function, "Image for \(download.url) not in the disk store", detail: log_normal)
            return false
        }
        
        log_debug(self, #function, "Image for \(self.download.url) is in the disk store", detail: log_normal)
        // Store in memory
        let info = URLImageStoreInfo(url: download.url, identifier: identifier, uti: transientImage.uti)

        service.inMemoryStore?.store(transientImage, info: info)

        // Complete
        self.loadingState.send(.success(transientImage))
        return true
    }
    
    private func updateLoadingState(_ loadingState: LoadingState) {
        self.loadingState.send(loadingState)
    }
    
    @MainActor
    private func updateIsLoading(_ loading: Bool) {
        self.isLoading = loading
    }

    /// Helper to return `URLImageStoreKey` objects based on `URLImageOptions` and `Download` properties
    private var keys: [URLImageKey] {
        var keys: [URLImageKey] = []

        // Identifier must precede URL
        if let identifier = identifier {
            keys.append(.identifier(identifier))
        }

        keys.append(.url(download.url))

        return keys
    }
}
