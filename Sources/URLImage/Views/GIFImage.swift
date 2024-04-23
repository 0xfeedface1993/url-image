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
    private let decoder: TransientImage
    
    init(decoder: TransientImage) {
        self.decoder = decoder
    }
    
    public var body: some View {
        GIFImage(source: decoder)
    }
}

@available(macOS 11.0, iOS 14.0, *)
struct GIFImage: PlatformViewRepresentable {
    private var source: TransientImage
    
    public func makeCoordinator() -> Coordinator {
        Coordinator({ image in
            print("Oops!")
        }, source: source)
    }
    
    init(source: TransientImage) {
        self.source = source
    }
    
#if os(iOS) || os(watchOS)
    public func makeUIView(context: Context) -> UIGIFImage {
        let view = UIGIFImage(source: nil)
        context.coordinator.updateImage = { image in
            view.imageView.image = image
        }
        Task {
            await context.coordinator.load()
        }
        return view
    }
    
    public func updateUIView(_ uiView: UIGIFImage, context: Context) {
        
    }
#elseif os(macOS)
    func makeNSView(context: Context) -> UIGIFImage {
        let view = UIGIFImage(source: nil)
        context.coordinator.updateImage = { image in
            view.imageView.image = image
            view.imageView.animates = true
        }
        Task {
            await context.coordinator.load()
        }
        return view
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
        
    }
#endif
    
    public final class Coordinator {
        let source: TransientImage
        var updateImage: (PlatformImage?) -> Void
        
        init(_ updator: @escaping (PlatformImage?) -> Void, source: TransientImage) {
            self.updateImage = updator
            self.source = source
        }
        
        func load() async {
            let data = await gif(source)
            Task { @MainActor in
                updateImage(data)
            }
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
        return PlatformImage(contentsOfFile: path)
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
