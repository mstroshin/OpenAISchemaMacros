// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation

/// Macro for creating JSON Schema objects compatible with OpenAI Structured Outputs
///
/// This macro automatically generates:
/// - `generateOpenAISchema()` method - returns dictionary with JSON Schema
/// - `generateOpenAISchemaString()` method - returns JSON Schema as string
/// - `create(from:)` method - creates object from JSON string
/// - Conformance to `JSONSchemaGenerator` and `Decodable` protocols
///
/// Example usage:
/// ```swift
/// @SchemaObject()
/// struct Person {
///     @SchemaField(description: "Full name of the person")
///     let name: String
///     
///     @SchemaField(description: "Age in years")
///     let age: Int
///     
///     @SchemaField(description: "Email address")
///     let email: String?
/// }
/// ```
///
/// Generated schema will be:
/// ```json
/// {
///   "type": "object",
///   "properties": {
///     "name": {"type": "string", "description": "Full name of the person"},
///     "age": {"type": "integer", "description": "Age in years"},
///     "email": {"type": "string", "description": "Email address"}
///   },
///   "required": ["name", "age"],
///   "additionalProperties": false
/// }
/// ```
@attached(extension, conformances: JSONSchemaGenerator, Decodable, names: named(generateOpenAISchema), named(generateOpenAISchemaString), named(create))
public macro SchemaObject() = #externalMacro(module: "AIDescriptionMacros", type: "AutoSchemaMacro")

/// Macro for defining schema properties with validation and metadata
///
/// This macro defines how a property should appear in the generated JSON Schema.
/// It supports comprehensive validation parameters following OpenAI Structured Outputs specification.
///
/// Parameters:
/// - **description**: Human-readable description of the field. Used by AI to understand field purpose.
/// - **isRequired**: Whether field is required in the schema. Default: `true`.
///   Note: Optional Swift types (`String?`, `Int?`) are automatically treated as non-required.
/// - **minLength**: Minimum string length (for string fields only)
/// - **maxLength**: Maximum string length (for string fields only)
/// - **minimum**: Minimum numeric value (for numeric fields only)
/// - **maximum**: Maximum numeric value (for numeric fields only)
/// - **pattern**: Regular expression pattern for string validation
/// - **format**: String format hint (e.g., "email", "uri", "date-time")
/// - **example**: Example value for documentation purposes
///
/// Example usage:
/// ```swift
/// @SchemaObject()
/// struct User {
///     @SchemaField(
///         description: "User's email address",
///         format: "email",
///         pattern: "^[\\w\\.-]+@[\\w\\.-]+\\.[a-zA-Z]{2,}$"
///     )
///     let email: String
///     
///     @SchemaField(
///         description: "User's age",
///         minimum: 0,
///         maximum: 150
///     )
///     let age: Int
///     
///     @SchemaField(
///         description: "User's bio",
///         maxLength: 500
///     )
///     let bio: String?
/// }
/// ```
///
/// Field Requirements Logic:
/// - `let field: String` + `@SchemaField()` → required: true
/// - `let field: String?` + `@SchemaField()` → required: false (optional type overrides)
/// - `let field: String` + `@SchemaField(isRequired: false)` → required: false
/// - `let field: String?` + `@SchemaField(isRequired: true)` → required: false (optional type wins)
@attached(peer)
public macro SchemaField(
    description: String? = nil,
    isRequired: Bool = true,
    minLength: Int? = nil,
    maxLength: Int? = nil,
    minimum: Double? = nil,
    maximum: Double? = nil,
    pattern: String? = nil,
    format: String? = nil,
    example: String? = nil
) = #externalMacro(module: "AIDescriptionMacros", type: "SchemaFieldMacro")

/// Macro for creating enum schemas compatible with OpenAI Structured Outputs
///
/// This macro automatically generates JSON Schema for Swift enums with string raw values.
/// Perfect for defining constrained choice fields in AI responses.
///
/// Requirements:
/// - Enum must have `String` raw type
/// - Enum should conform to `Codable`
/// - All cases must have explicit or implicit string values
///
/// Generated schema includes:
/// - `type: "string"`
/// - `enum: [...]` array with all possible values
/// - Automatic conformance to `CaseIterable` and `RawRepresentable`
///
/// Example usage:
/// ```swift
/// @SchemaEnum()
/// enum Priority: String, Codable {
///     case low
///     case medium
///     case high
///     case urgent
/// }
/// 
/// @SchemaEnum()
/// enum TaskStatus: String, Codable {
///     case pending
///     case inProgress = "in_progress"
///     case completed
///     case cancelled
/// }
/// ```
///
/// Generated schema for Priority:
/// ```json
/// {
///   "type": "string",
///   "enum": ["low", "medium", "high", "urgent"]
/// }
/// ```
///
/// Generated schema for TaskStatus:
/// ```json
/// {
///   "type": "string", 
///   "enum": ["pending", "in_progress", "completed", "cancelled"]
/// }
/// ```
@attached(extension, conformances: CaseIterable, RawRepresentable, names: named(generateEnumSchema))
public macro SchemaEnum() = #externalMacro(module: "AIDescriptionMacros", type: "SchemaEnumMacro")

/// Protocol for objects that can generate JSON Schema
///
/// This protocol is automatically implemented by the `@SchemaObject()` macro.
/// It provides the interface for generating OpenAI-compatible JSON schemas.
public protocol JSONSchemaGenerator {
    /// Generates JSON Schema as a dictionary
    /// - Returns: Dictionary representation of JSON Schema
    static func generateOpenAISchema() -> [String: Any]
    
    /// Generates JSON Schema as a JSON string
    /// - Returns: Pretty-printed JSON string of the schema
    static func generateOpenAISchemaString() -> String
    
    /// Creates an instance from JSON string
    /// - Parameter jsonString: JSON string to decode
    /// - Returns: Decoded instance
    /// - Throws: Decoding errors if JSON is invalid or doesn't match schema
    static func create(from jsonString: String) throws -> Self
}
