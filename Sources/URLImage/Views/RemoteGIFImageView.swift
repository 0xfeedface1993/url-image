//
//  SwiftUIView.swift
//  
//
//  Created by sonoma on 4/24/24.
//

import SwiftUI
import Model

@available(macOS 12.0, iOS 15.0, tvOS 14.0, watchOS 7.0, *)
struct RemoteGIFImageView<Empty, InProgress, Failure, Content> : View where Empty : View,
                                                                         InProgress : View,
                                                                         Failure : View,
                                                                         Content : View {
    @ObservedObject private var remoteImage: RemoteImage
    @Environment(\.urlImageService) var urlImageService
    @Environment(\.urlImageOptions) var options
    @State private var image: PlatformImage?
    @State var animateState: RemoteImageLoadingState = .initial

    let loadOptions: URLImageOptions.LoadOptions

    let empty: () -> Empty
    let inProgress: (_ progress: Float?) -> InProgress
    let failure: (_ error: Error, _ retry: @escaping () -> Void) -> Failure
    let content: (_ value: GIFImageView) -> Content

    init(remoteImage: RemoteImage,
         loadOptions: URLImageOptions.LoadOptions,
         @ViewBuilder empty: @escaping () -> Empty,
         @ViewBuilder inProgress: @escaping (_ progress: Float?) -> InProgress,
         @ViewBuilder failure: @escaping (_ error: Error, _ retry: @escaping () -> Void) -> Failure,
         @ViewBuilder content: @escaping (_ value: GIFImageView) -> Content) {

        self.remoteImage = remoteImage
        self.loadOptions = loadOptions

        self.empty = empty
        self.inProgress = inProgress
        self.failure = failure
        self.content = content

//        if loadOptions.contains(.loadImmediately) {
//            remoteImage.load()
//        }
    }
    
    var body: some View {
        ZStack {
            switch animateState {
            case .initial:
                empty()
                
            case .inProgress(let progress):
                inProgress(progress)
                
            case .success(_):
                if let image = image {
                    content(
                        GIFImageView(image: image)
                    )
                }   else    {
                    inProgress(1.0)
                }
            case .failure(let error):
                failure(error, {
                    remoteImage.load()
                })
            }
        }
        .onAppear {
            if loadOptions.contains(.loadOnAppear), !remoteImage.slowLoadingState.value.isSuccess {
                remoteImage.load()
            }
            Task {
                await prepare(self.animateState)
            }
        }
        .onDisappear {
            if loadOptions.contains(.cancelOnDisappear) {
                remoteImage.cancel()
            }
//            image = nil
        }
        .onReceive(remoteImage.slowLoadingState) { newValue in
            Task {
                await prepare(newValue)
            }
            animateState = newValue
        }
    }
    
    private func prepare(_ state: RemoteImage.LoadingState) async {
        if case .success(_) = state {
            if let image = await loadMemoryStore(options.maxPixelSize) {
                self.image = image
                return
            }
            await load(options.maxPixelSize)
        }
    }
    
    private func load(_ maxPixelSize: CGSize?) async {
        guard let fileStore = urlImageService.fileStore else {
            print("fileStore missing")
            return
        }
        
        do {
            let value = try await fileStore.getImage([.url(remoteImage.download.url)], maxPixelSize: maxPixelSize)
            guard let value else {
                return
            }
            let data = await gif(value, maxSize: options.maxPixelSize)
            image = data
        } catch {
            print("retrive image with \(remoteImage.download.url) failed. \(error)")
        }
    }
    
    private func loadMemoryStore(_ maxPixelSize: CGSize?) async -> PlatformImage? {
        guard let memoryStore = urlImageService.inMemoryStore else {
            print("memory store missing")
            return nil
        }
        
        guard let value: TransientImage = await memoryStore.getImage([.url(remoteImage.download.url)]) else {
            print("\(remoteImage.download.url) not cached in memory store")
            return nil
        }
        
        return await gif(value, maxSize: options.maxPixelSize)
    }
}

#if os(iOS) || os(watchOS)
@available(iOS 14.0, *)
fileprivate func gifImage(_ image: TransientImage, maxSize: CGSize?) async -> PlatformImage? {
    let decoder = image.proxy.decoder
    let count = decoder.frameCount
    var delays = [Int]()
    for delay in 0..<count {
        delays.append(Int((decoder.frameDuration(at: delay) ?? 0) * 1000))
    }
    let duration = delays.reduce(0, +)
    let gcd = delays.reduce(0, gcd)
    
    var frames = [PlatformImage]()
    for i in 0..<count {
        if let cgImage = decoder.createFrameImage(at: i, decodingOptions: .init(mode: .asynchronous, sizeForDrawing: maxSize)) {
            let frame = PlatformImage(cgImage: cgImage)
            let frameCount = delays[i] / gcd
            
            for _ in 0..<frameCount {
                frames.append(frame)
            }
        } else {
            return nil
        }
    }
    
    return PlatformImage.animatedImage(with: frames,
                                 duration: Double(duration) / 1000.0)
}
#elseif os(macOS)
@available(macOS 11.0, *)
fileprivate func gifImage(_ source: TransientImage, maxSize: CGSize?) async -> PlatformImage? {
    switch source.presentation {
    case .data(let data):
        return PlatformImage(data: data)
    case .file(let path):
        let image = PlatformImage(contentsOfFile: path)
        if let image {
            print("cache image file \(image) load from \(path)")
        } else {
            print("cache image file nil load from \(path)")
        }
        return image
    }
}

extension NSImage: @unchecked Sendable {
    
}
#endif

//fileprivate func gifCacheImageData(_ source: Imaged) -> PlatformImage? {
//    
//}

@available(macOS 11.0, iOS 14.0, *)
fileprivate func gif(_ source: TransientImage, maxSize: CGSize?) async -> PlatformImage? {
    await gifImage(source, maxSize: maxSize)
}

fileprivate func gcd(_ a: Int, _ b: Int) -> Int {
    let absB = abs(b)
    let r = abs(a) % absB
    if r != 0 {
        return gcd(absB, r)
    } else {
        return absB
    }
}

fileprivate func delayForImage(at index: Int, source: CGImageSource) -> Double {
    var delay = 0.1
    
    // Get dictionaries
    let cfProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
    let gifPropertiesPointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: 0)
    if CFDictionaryGetValueIfPresent(cfProperties, Unmanaged.passUnretained(kCGImagePropertyGIFDictionary).toOpaque(), gifPropertiesPointer) == false {
        return delay
    }
    
    let gifProperties:CFDictionary = unsafeBitCast(gifPropertiesPointer.pointee, to: CFDictionary.self)
    
    // Get delay time
    var delayObject: AnyObject = unsafeBitCast(CFDictionaryGetValue(gifProperties, Unmanaged.passUnretained(kCGImagePropertyGIFUnclampedDelayTime).toOpaque()), to: AnyObject.self)
    if delayObject.doubleValue == 0 {
        delayObject = unsafeBitCast(CFDictionaryGetValue(gifProperties, Unmanaged.passUnretained(kCGImagePropertyGIFDelayTime).toOpaque()), to: AnyObject.self)
    }
    
    delay = delayObject as! Double
    
    if delay < 0.1 {
        delay = 0.1 // Make sure they're not too fast
    }
    
    return delay
}


//#Preview {
//    RemoteGIFImageView()
//}
