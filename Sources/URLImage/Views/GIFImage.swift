//
//  SwiftUIView.swift
//  
//
//  Created by sonoma on 4/21/24.
//

import SwiftUI
import Model

#if os(iOS) || os(watchOS)
typealias PlatformView = UIView
typealias PlatformViewRepresentable = UIViewRepresentable
typealias PlatformImage = UIImage
typealias PlatformImageView = UIImageView
#elseif os(macOS)
typealias PlatformView = NSView
typealias PlatformImage = NSImage
typealias PlatformImageView = NSImageView
typealias PlatformViewRepresentable = NSViewRepresentable
#endif

@available(macOS 11.0, iOS 14.0, *)
public struct GIFWrapperImage: View {
    private let decoder: CGImageProxy
    
    init(decoder: CGImageProxy) {
        self.decoder = decoder
    }
    
    public var body: some View {
        GIFImage(source: decoder.decoder.imageSource)
    }
}


struct GIFImage: PlatformViewRepresentable {
    private var source: CGImageSource
    @State var image: PlatformImage?
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    init(source: CGImageSource) {
        self.source = source
    }
    
#if os(iOS) || os(watchOS)
    public func makeUIView(context: Context) -> UIGIFImage {
        UIGIFImage(source: image)
    }
    
    public func updateUIView(_ uiView: UIGIFImage, context: Context) {
        uiView.imageView.image = image
    }
#elseif os(macOS)
    func makeNSView(context: Context) -> UIGIFImage {
        UIGIFImage(source: image)
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
        nsView.imageView.image = image
        nsView.imageView.animates = true
    }
#endif
    
    public final class Coordinator {
        var imageView: GIFImage
        
        init(_ imageView: GIFImage) {
            self.imageView = imageView
            
            Task {
                await load()
            }
        }
        
        func load() async {
#if os(iOS) || os(watchOS)
            let data = await gif(imageView.source)
            Task { @MainActor in
                imageView.image = data
            }
#endif
        }
    }
}

class UIGIFImage: PlatformView {
    let imageView = PlatformImageView()
    private var source: PlatformImage?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    convenience init(source: PlatformImage?) {
        self.init()
        self.source = source
        initView()
    }

#if os(iOS) || os(watchOS)
    public override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        addSubview(imageView)
    }
#elseif os(macOS)
    override func layout() {
        super.layout()
        imageView.frame = bounds
        addSubview(imageView)
    }
#endif
    
    private func initView() {
#if os(iOS) || os(watchOS)
        imageView.contentMode = .scaleAspectFit
#elseif os(macOS)
        imageView.image = source
        imageView.animates = true
#endif
    }
    
}

#if os(iOS) || os(watchOS)
fileprivate func gifImage(_ source: CGImageSource) -> PlatformImage? {
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

fileprivate func gif(_ source: CGImageSource) async -> PlatformImage? {
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
    let defaultDelay = 1.0
    
    let cfProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
    let gifPropertiesPointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: 0)
    defer {
        gifPropertiesPointer.deallocate()
    }
    let unsafePointer = Unmanaged.passUnretained(kCGImagePropertyGIFDictionary).toOpaque()
    if CFDictionaryGetValueIfPresent(cfProperties, unsafePointer, gifPropertiesPointer) == false {
        return defaultDelay
    }
    let gifProperties = unsafeBitCast(gifPropertiesPointer.pointee, to: CFDictionary.self)
    var delayWrapper = unsafeBitCast(CFDictionaryGetValue(gifProperties,
                                                         Unmanaged.passUnretained(kCGImagePropertyGIFUnclampedDelayTime).toOpaque()),
                                    to: AnyObject.self)
    if delayWrapper.doubleValue == 0 {
        delayWrapper = unsafeBitCast(CFDictionaryGetValue(gifProperties,
                                                         Unmanaged.passUnretained(kCGImagePropertyGIFDelayTime).toOpaque()),
                                    to: AnyObject.self)
    }
    
    if let delay = delayWrapper as? Double,
       delay > 0 {
        return delay
    } else {
        return defaultDelay
    }
}
#endif

//@available(iOS 13.0, *)
//struct GIFImageTest: View {
//    @State private var imageData: Data? = nil
//    
//    var body: some View {
//        VStack {
//            GIFImage(name: "preview")
//                .frame(height: 300)
//            if let data = imageData {
//                GIFImage(data: data)
//                    .frame(width: 300)
//            } else {
//                Text("Loading...")
//                    .onAppear(perform: loadData)
//            }
//        }
//    }
//    
//    private func loadData() {
//        let task = URLSession.shared.dataTask(with: URL(string: "https://github.com/globulus/swiftui-webview/raw/main/Images/preview_macos.gif?raw=true")!) { data, response, error in
//            imageData = data
//        }
//        task.resume()
//    }
//}
//
//
//struct GIFImage_Previews: PreviewProvider {
//    static var previews: some View {
//        GIFImageTest()
//    }
//}
