//
//  RemoteImageView.swift
//  
//
//  Created by Dmytro Anokhin on 09/08/2020.
//

import SwiftUI
import Model


@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
struct RemoteImageView<Empty, InProgress, Failure, Content> : View where Empty : View,
                                                                         InProgress : View,
                                                                         Failure : View,
                                                                         Content : View {
    @ObservedObject var remoteImage: RemoteImage
    @Environment(\.urlImageOptions) var urlImageOptions

    let loadOptions: URLImageOptions.LoadOptions

    let empty: () -> Empty
    let inProgress: (_ progress: Float?) -> InProgress
    let failure: (_ error: Error, _ retry: @escaping () -> Void) -> Failure
    let content: (_ value: TransientImage) -> Content
    
    @Namespace var namespace
    @State var animateState: RemoteImageLoadingState = .initial

    init(remoteImage: RemoteImage,
         loadOptions: URLImageOptions.LoadOptions,
         @ViewBuilder empty: @escaping () -> Empty,
         @ViewBuilder inProgress: @escaping (_ progress: Float?) -> InProgress,
         @ViewBuilder failure: @escaping (_ error: Error, _ retry: @escaping () -> Void) -> Failure,
         @ViewBuilder content: @escaping (_ value: TransientImage) -> Content) {

        self.remoteImage = remoteImage
        self.loadOptions = loadOptions

        self.empty = empty
        self.inProgress = inProgress
        self.failure = failure
        self.content = content

//        if loadOptions.contains(.loadImmediately), !remoteImage.loadingState.isSuccess {
//            remoteImage.load()
//        }
    }
    
    var body: some View {
        ZStack {
            switch animateState {
            case .initial:
                empty()
                    .matchedGeometryEffect(id: remoteImage.download.url, in: namespace)
            case .inProgress(let progress):
                inProgress(progress)
                    .matchedGeometryEffect(id: remoteImage.download.url, in: namespace)
            case .success(let value):
                content(value)
                    .matchedGeometryEffect(id: remoteImage.download.url, in: namespace)
            case .failure(let error):
                failure(error) {
                    remoteImage.load()
                }
                .matchedGeometryEffect(id: remoteImage.download.url, in: namespace)
            }
        }
        .onAppear {
            if loadOptions.contains(.loadOnAppear), !remoteImage.slowLoadingState.value.isSuccess {
                remoteImage.load()
            }
        }
        .onDisappear {
            if loadOptions.contains(.cancelOnDisappear) {
                remoteImage.cancel()
            }
        }
        .onReceive(remoteImage.slowLoadingState) { newValue in
            guard urlImageOptions.loadingAnimated else {
                animateState = newValue
                return
            }
            
            withAnimation(.smooth) {
                animateState = newValue
            }
        }
    }
}
