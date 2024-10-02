//
//  URLImageFileStoreType+Combine.swift
//  
//
//  Created by Dmytro Anokhin on 09/02/2021.
//

import Foundation
import CoreGraphics
import Model

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension URLImageFileStoreType {
    func getImage(_ keys: [URLImageKey], maxPixelSize: CGSize?) async throws -> TransientImage? {
        try await withCheckedThrowingContinuation { continuation in
            getImage(keys) { location -> TransientImage? in
                guard let transientImage = TransientImage(location: location, maxPixelSize: maxPixelSize) else {
                    throw URLImageError.decode
                }
                return transientImage
            } completion: { result in
                switch result {
                case .success(let image):
                    continuation.resume(returning: image)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
