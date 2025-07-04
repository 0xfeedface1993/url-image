//
//  URLImageInMemoryStore.swift
//  
//
//  Created by Dmytro Anokhin on 09/02/2021.
//

import Foundation
import URLImage
import Model

public final class URLImageInMemoryStore: Sendable {

    public init() {
    }

    // MARK: - Private

    private final class KeyWrapper: NSObject, Sendable {

        let key: URLImageKey

        init(key: URLImageKey) {
            self.key = key
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let wrapper = object as? KeyWrapper else {
                return false
            }

            return key == wrapper.key
        }

        override var hash: Int {
            key.hashValue
        }
    }

    @URLImageInMemoryStoreActor
    private final class ObjectWrapper {
        let image: Any

        let info: URLImageStoreInfo

        init(image: Any, info: URLImageStoreInfo) {
            self.image = image
            self.info = info
        }
    }

    @URLImageInMemoryStoreActor
    private let cache = NSCache<KeyWrapper, ObjectWrapper>()
}


extension URLImageInMemoryStore: URLImageInMemoryStoreType {

    public func removeAllImages() {
        Task { @URLImageInMemoryStoreActor in
            cache.removeAllObjects()
        }
    }

    public func removeImageWithURL(_ url: URL) {
        let key = URLImageKey.url(url)
        let keyWrapper = KeyWrapper(key: key)
        Task { @URLImageInMemoryStoreActor in
            cache.removeObject(forKey: keyWrapper)
        }
    }

    public func removeImageWithIdentifier(_ identifier: String) {
        let key = URLImageKey.identifier(identifier)
        let keyWrapper = KeyWrapper(key: key)
        Task { @URLImageInMemoryStoreActor in
            cache.removeObject(forKey: keyWrapper)
        }
    }

    public func getImage<T: Sendable>(_ keys: [URLImageKey]) -> T? {
        for key in keys.map({ KeyWrapper(key: $0) }) {
            guard let object = cache.object(forKey: key) else {
                continue
            }

            return object.image as? T
        }

        return nil
    }

    public func store<T>(_ image: T, info: URLImageStoreInfo) {
        let urlKey = URLImageKey.url(info.url)
        let urlKeyWrapper = KeyWrapper(key: urlKey)
        let imageWrapper = ObjectWrapper(image: image, info: info)
        cache.setObject(imageWrapper, forKey: urlKeyWrapper)
        
        if let identifier = info.identifier {
            let identifierKey = URLImageKey.identifier(identifier)
            let identifierKeyWrapper = KeyWrapper(key: identifierKey)
            cache.setObject(imageWrapper, forKey: identifierKeyWrapper)
        }
    }
}
