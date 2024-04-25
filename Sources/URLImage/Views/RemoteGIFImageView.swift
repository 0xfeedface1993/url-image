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
    @ObservedObject private(set) var remoteImage: RemoteImage
    @Environment(\.urlImageService) var urlImageService
    @Environment(\.urlImageOptions) var options
    @State private var image: PlatformImage?

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

        if loadOptions.contains(.loadImmediately) {
            remoteImage.load()
            prepare(remoteImage.loadingState)
        }
    }
    
    var body: some View {
        ZStack {
            switch remoteImage.loadingState {
            case .initial:
                empty()
                
            case .inProgress(let progress):
                inProgress(progress)
                
            case .success(let next):
                if let image = image {
                    content(
                        GIFImageView(image: image)
                    )
                    .aspectRatio(next.info.size, contentMode: .fit)
                }   else    {
                    inProgress(1.0)
                }
            case .failure(let error):
                failure(error) {
                    remoteImage.load()
                }
            }
        }
        .onAppear {
            if loadOptions.contains(.loadOnAppear) {
                remoteImage.load()
            }
        }
        .onDisappear {
            if loadOptions.contains(.cancelOnDisappear) {
                remoteImage.cancel()
            }
        }
        .onReceive(remoteImage.$loadingState, perform: prepare(_:))
    }
    
    private func prepare(_ state: RemoteImage.LoadingState) {
        if case .success(let next) = state {
            Task {
                await load(options.maxPixelSize)
            }
        }
    }
    
//    private func transientImage(_ pass: TransientImage) -> PlatformImage {
//        if options.maxPixelSize == nil {
//#if os(macOS)
//            return gifImage(pass) ?? PlatformImage(cgImage: pass.cgImage, size: pass.info.size)
//#else
//            return gifImage(pass) ?? PlatformImage(cgImage: pass.cgImage)
//#endif
//        }
//        let transient = TransientImage(decoder: pass.proxy.decoder, presentation: pass.presentation, maxPixelSize: options.maxPixelSize) ?? pass
//        
//#if os(macOS)
//        return gifImage(transient) ?? PlatformImage(cgImage: pass.cgImage, size: pass.info.size)
//#else
//        return gifImage(transient) ?? PlatformImage(cgImage: pass.cgImage)
//#endif
//    }
    
    private func load(_ maxPixelSize: CGSize?) async {
        guard let fileStore = urlImageService.fileStore else {
            print("fileStore missing")
            return
        }
        
        do {
            for try await value in fileStore.getImagePublisher([.url(remoteImage.download.url)], maxPixelSize: maxPixelSize).values {
                guard let value = value else {
                    continue
                }
                let data = await gif(value)
                image = data
            }
        } catch {
            print("retrive image with \(remoteImage.download.url) failed. \(error)")
        }
    }
}

#if os(iOS) || os(watchOS)
@available(iOS 14.0, *)
fileprivate func gifImage(_ image: TransientImage) -> PlatformImage? {
    let source = image.proxy.decoder.imageSource
    let count = CGImageSourceGetCount(source)
    let delays = (0..<count).map {
        // store in ms and truncate to compute GCD more easily
        Int(delayForImage(at: $0, source: source) * 1000)
    }
    let duration = delays.reduce(0, +)
    let gcd = delays.reduce(0, gcd)
    
    var frames = [PlatformImage]()
    for i in 0..<count {
        if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
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
fileprivate func gifImage(_ source: TransientImage) -> PlatformImage? {
    switch source.presentation {
    case .data(let data):
        return PlatformImage(data: data)
    case .file(let path):
        let image = PlatformImage(contentsOfFile: path)
        print("cache image file \(String(describing: image)) load from \(path)")
        return image
    }
}

extension NSImage: @unchecked Sendable {
    
}
#endif

@available(macOS 11.0, iOS 14.0, *)
fileprivate func gif(_ source: TransientImage) async -> PlatformImage? {
    gifImage(source)
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
