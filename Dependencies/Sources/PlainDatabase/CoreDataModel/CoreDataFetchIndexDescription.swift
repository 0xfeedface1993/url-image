//
//  CoreDataFetchIndexDescription.swift
//  
//
//  Created by Dmytro Anokhin on 08/09/2020.
//

import CoreData


/// Describes `NSFetchIndexDescription`
@available(iOS 14.0, tvOS 14.0, macOS 11.0, watchOS 7.0, *)
public struct CoreDataFetchIndexDescription: Sendable {

    /// Describes `NSFetchIndexElementDescription`
    public struct Element: Sendable {

        public enum Property: Sendable {

            case property(name: String)
        }

        public static func property(name: String, type: NSFetchIndexElementType = .binary, ascending: Bool = true) -> Element {
            Element(property: .property(name: name), type: type, ascending: ascending)
        }

        public var property: Property

        public var type: NSFetchIndexElementType

        public var ascending: Bool
    }

    public static func index(name: String, elements: [Element]) -> CoreDataFetchIndexDescription {
        CoreDataFetchIndexDescription(name: name, elements: elements)
    }

    public var name: String

    public var elements: [Element]
}
