// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation

@attached(extension, conformances: JSONSchemaGenerator, names: named(generateOpenAISchema), named(generateOpenAISchemaString))
public macro AutoSchema(name: String? = nil, strict: Bool = true) = #externalMacro(module: "AIDescriptionMacros", type: "AutoSchemaMacro")

@attached(peer)
public macro SchemaField(description: String? = nil, example: String? = nil, isRequired: Bool = true) = #externalMacro(module: "AIDescriptionMacros", type: "SchemaFieldMacro")

public protocol JSONSchemaGenerator {
    static func generateOpenAISchema() -> [String: Any]
    static func generateOpenAISchemaString() -> String
}
