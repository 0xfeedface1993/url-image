//
//  SwiftUIView.swift
//  
//
//  Created by sonoma on 4/21/24.
//

import SwiftUI
import Model

@available(iOS 14.0, *)
public struct GIFWrapperImage<Content: View>: View {
    private let decoder: CGImageProxy
    @State private var image: UIImage?
    
    var content: (Image) -> Content
    
    init(decoder: CGImageProxy, @ViewBuilder content: @escaping (Image) -> Content) {
        self.decoder = decoder
        self.content = content
    }
    
    public var body: some View {
//        GIFImage(source: decoder.decoder.imageSource)
        if let image = image {
            content(Image(uiImage: image))
        }   else    {
            Color.clear.onAppear(perform: {
                Task {
                    image = await UIImage.gif(decoder.decoder.imageSource)
                }
            })
        }
    }
}

public struct GIFImage: UIViewRepresentable {
    private var source: CGImageSource
    
    init(source: CGImageSource) {
        self.source = source
    }
    
    public func makeUIView(context: Context) -> UIGIFImage {
        UIGIFImage(source: source)
    }
    
    public func updateUIView(_ uiView: UIGIFImage, context: Context) {
        Task {
            await uiView.updateGIF(source: source)
        }
    }
}

public class UIGIFImage: UIView {
    private let imageView = UIImageView()
    private var source: CGImageSource?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    convenience init(source: CGImageSource) {
        self.init()
        self.source = source
        initView()
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        self.addSubview(imageView)
    }
    
    func updateGIF(source: CGImageSource) async {
        let image = UIImage.gifImage(source)
        await updateWithImage(image)
    }
    
    @MainActor
    private func updateWithImage(_ image: UIImage?) async {
        imageView.image = image
    }
    
    private func initView() {
        imageView.contentMode = .scaleAspectFit
    }
}

public extension UIImage {
    static func gifImage(_ source: CGImageSource) -> UIImage? {
        let count = CGImageSourceGetCount(source)
        let delays = (0..<count).map {
            // store in ms and truncate to compute GCD more easily
            Int(delayForImage(at: $0, source: source) * 1000)
        }
        let duration = delays.reduce(0, +)
        let gcd = delays.reduce(0, gcd)
        
        var frames = [UIImage]()
        for i in 0..<count {
            if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                let frame = UIImage(cgImage: cgImage)
                let frameCount = delays[i] / gcd
                
                for _ in 0..<frameCount {
                    frames.append(frame)
                }
            } else {
                return nil
            }
        }
        
        return UIImage.animatedImage(with: frames,
                                     duration: Double(duration) / 1000.0)
    }
    
    static func gif(_ source: CGImageSource) async -> UIImage? {
        gifImage(source)
    }
}

private func gcd(_ a: Int, _ b: Int) -> Int {
    let absB = abs(b)
    let r = abs(a) % absB
    if r != 0 {
        return gcd(absB, r)
    } else {
        return absB
    }
}

private func delayForImage(at index: Int, source: CGImageSource) -> Double {
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
