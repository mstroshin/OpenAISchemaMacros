import Foundation

/// Schema wrapper for OpenAI Structured Outputs
public struct Schema {
    public let name: String
    public let schema: [String: Any]
    public let strict: Bool
    
    public init(name: String, schema: [String: Any], strict: Bool = true) {
        self.name = name
        self.schema = schema
        self.strict = strict
    }
}

/// Chat message for OpenAI API requests
public struct ChatRequestMessage: Codable {
    public let role: String
    public let content: String
    
    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// Text format configuration for Responses API
public struct TextFormat: Codable {
    public let type: String = "json_schema"
    public let name: String
    public let schema: [String: Any]
    public let strict: Bool
    
    public enum CodingKeys: String, CodingKey {
        case type, name, schema, strict
    }
    
    public init(schema: Schema) {
        self.name = schema.name
        self.schema = schema.schema
        self.strict = schema.strict
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        strict = try container.decode(Bool.self, forKey: .strict)
        
        let schemaContainer = try container.decode(AnyCodable.self, forKey: .schema)
        if let schemaDict = schemaContainer.value as? [String: Any] {
            schema = schemaDict
        } else {
            schema = [:]
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encode(strict, forKey: .strict)
        
        let schemaData = try JSONSerialization.data(withJSONObject: schema)
        let schemaContainer = try JSONDecoder().decode(AnyCodable.self, from: schemaData)
        try container.encode(schemaContainer, forKey: .schema)
    }
}

/// Text configuration for Responses API
public struct TextConfig: Codable {
    public let format: TextFormat
    
    public init(format: TextFormat) {
        self.format = format
    }
}

/// OpenAI Responses API request format
public struct ResponsesRequest: Codable {
    public let model: String
    public let input: [ChatRequestMessage]
    public let text: TextConfig
    
    public init(model: String, input: [ChatRequestMessage], text: TextConfig) {
        self.model = model
        self.input = input
        self.text = text
    }
}

/// JSON Schema format for OpenAI structured outputs
public struct JSONSchemaFormat: Codable {
    public let name: String
    public let schema: [String: Any]
    public let strict: Bool
    
    public enum CodingKeys: String, CodingKey {
        case name, schema, strict
    }
    
    public init(name: String, schema: [String: Any], strict: Bool = true) {
        self.name = name
        self.schema = schema
        self.strict = strict
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        strict = try container.decode(Bool.self, forKey: .strict)
        
        let schemaContainer = try container.decode(AnyCodable.self, forKey: .schema)
        if let schemaDict = schemaContainer.value as? [String: Any] {
            schema = schemaDict
        } else {
            schema = [:]
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(strict, forKey: .strict)
        
        let schemaData = try JSONSerialization.data(withJSONObject: schema)
        let schemaContainer = try JSONDecoder().decode(AnyCodable.self, from: schemaData)
        try container.encode(schemaContainer, forKey: .schema)
    }
}

/// Helper for encoding/decoding [String: Any] dictionaries
private struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodable($0) })
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
