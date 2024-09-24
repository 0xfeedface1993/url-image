//
//  SwiftUIView.swift
//
//
//  Created by sonoma on 4/21/24.
//

import SwiftUI
import Model

#if os(iOS) || os(watchOS)
public typealias PlatformView = UIView
public typealias PlatformViewRepresentable = UIViewRepresentable
public typealias PlatformImage = UIImage
public typealias PlatformImageView = UIImageView
#elseif os(macOS)
public typealias PlatformView = NSView
public typealias PlatformImage = NSImage
public typealias PlatformImageView = NSImageView
public typealias PlatformViewRepresentable = NSViewRepresentable
#endif

@available(macOS 12.0, iOS 15.0, *)
public struct GIFImage<Empty, InProgress, Failure, Content> : View where Empty : View,
                                                                         InProgress : View,
                                                                         Failure : View,
                                                                         Content : View {
    @Environment(\.urlImageService) var urlImageService
    @Environment(\.urlImageOptions) var options
    
    var url: URL
    
    private let empty: () -> Empty
    private let inProgress: (_ progress: Float?) -> InProgress
    private let failure: (_ error: Error, _ retry: @escaping () -> Void) -> Failure
    private let content: (_ image: GIFImageView) -> Content
    
    public init(_ url: URL,
                 @ViewBuilder empty: @escaping () -> Empty,
                 @ViewBuilder inProgress: @escaping (_ progress: Float?) -> InProgress,
                 @ViewBuilder failure: @escaping (_ error: Error, _ retry: @escaping () -> Void) -> Failure,
                 @ViewBuilder content: @escaping (_ transientImage: GIFImageView) -> Content) {
        
        self.url = url
        self.empty = empty
        self.inProgress = inProgress
        self.failure = failure
        self.content = content
    }
    
    public var body: some View {
        InstalledRemoteView(service: urlImageService, url: url, identifier: nil, options: options) { remoteImage in
            RemoteGIFImageView(remoteImage: remoteImage,
                               loadOptions: options.loadOptions,
                               empty: empty,
                               inProgress: inProgress,
                               failure: failure,
                               content: content)
        }
    }
}

@available(macOS 11.0, iOS 14.0, *)
public struct GIFImageView: View {
    var image: PlatformImage
    @Environment(\.imageConfigures) var imageConfigures
    
    init(image: PlatformImage) {
        self.image = image
    }
    
    public var body: some View {
        if imageConfigures.resizeble, let aspectRatio = imageConfigures.aspectRatio {
            GIFRepresentView(image: image)
                .aspectRatio(aspectRatio, contentMode: imageConfigures.contentMode == .fit ? .fit:.fill)
        }   else    {
            GIFRepresentView(image: image)
                .frame(width: image.size.width, height: image.size.height)
        }
    }
}

public extension View {
    func aspectResizeble(ratio: CGFloat, contentMode: ContentMode = .fit) -> some View {
        self.environment(\.imageConfigures, ImageConfigures(aspectRatio: ratio, contentMode: contentMode, resizeble: true))
    }
}

@available(macOS 11.0, iOS 14.0, *)
struct GIFRepresentView: PlatformViewRepresentable {
    var image: PlatformImage
    @Environment(\.imageConfigures) var imageConfigures
    
#if os(iOS) || os(watchOS)
    public func makeUIView(context: Context) -> UIGIFImage {
        UIGIFImage(source: image)
    }
    
    public func updateUIView(_ uiView: UIGIFImage, context: Context) {
        
    }
#elseif os(macOS)
    public func makeNSView(context: Context) -> UIGIFImage {
        UIGIFImage(source: image)
    }
    
    public func updateNSView(_ nsView: NSViewType, context: Context) {
        
    }
#endif
}

public final class UIGIFImage: PlatformView {
    let imageView = PlatformImageView()
    var source: PlatformImage?
    var imageConfigures: ImageConfigures?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    convenience init(source: PlatformImage) {
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
    public override func layout() {
        super.layout()
        imageView.frame = bounds
        addSubview(imageView)
    }
#endif
    
    private func initView() {
#if os(iOS) || os(watchOS)
        imageView.contentMode = imageConfigures?.contentMode == .fit ? .scaleAspectFit:.scaleAspectFill
        imageView.image = source
#elseif os(macOS)
        imageView.imageScaling = imageConfigures?.contentMode == .fit ? .scaleAxesIndependently:.scaleProportionallyUpOrDown
        imageView.image = source
        imageView.animates = true
#endif
    }
}


public struct Scenes {
    public init() {
        
    }
    
#if os(iOS) || os(watchOS)
    @MainActor func keyScreen() -> UIScreen {
        UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: {
                $0.activationState == .foregroundActive
            })?.screen ?? UIScreen.main
    }
    
    @MainActor public func nativeScale() -> CGFloat {
        keyScreen().nativeScale
    }
#elseif os(macOS)
    public func nativeScale() -> CGFloat {
        NSScreen.main?.backingScaleFactor ?? 1
    }
#endif
}

public enum ContentMode {
    case fit
    case fill
}

struct ImageConfigures {
    var aspectRatio: CGFloat?
    var contentMode: ContentMode
    var resizeble: Bool
    
    func aspectRatio(_ aspectRatio: CGFloat) -> ImageConfigures {
        var configures = self
        configures.aspectRatio = aspectRatio
        return configures
    }

    func contentMode(_ contentMode: ContentMode) -> ImageConfigures {
        var configures = self
        configures.contentMode = contentMode
        return configures
    }
}

struct ImageConfiguresEnvironmentKey: @preconcurrency EnvironmentKey {
    @MainActor static var defaultValue = ImageConfigures(aspectRatio: nil, contentMode: .fit, resizeble: false)
}

extension EnvironmentValues {
    var imageConfigures: ImageConfigures {
        get { self[ImageConfiguresEnvironmentKey.self] }
        set { self[ImageConfiguresEnvironmentKey.self] = newValue }
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

