import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Main macro implementation for generating JSON Schema objects compatible with OpenAI Structured Outputs
///
/// This macro processes structs annotated with `@SchemaObject()` and generates:
/// 1. JSON Schema generation methods (`generateOpenAISchema`, `generateOpenAISchemaString`)
/// 2. Object creation from JSON (`create(from:)`)
/// 3. Protocol conformances (`JSONSchemaGenerator`, `Decodable`)
///
/// The generated schema follows OpenAI Structured Outputs specification:
/// - Uses `"type": "object"` for struct types
/// - Includes `properties` with type information and descriptions
/// - Properly handles `required` fields (excludes optional types)
/// - Sets `"additionalProperties": false` for strict validation
public struct AutoSchemaMacro: ExtensionMacro {
    
    public static func expansion(
        of node: SwiftSyntax.AttributeSyntax,
        attachedTo declaration: some SwiftSyntax.DeclGroupSyntax,
        providingExtensionsOf type: some SwiftSyntax.TypeSyntaxProtocol,
        conformingTo protocols: [SwiftSyntax.TypeSyntax],
        in context: some SwiftSyntaxMacros.MacroExpansionContext
    ) throws -> [SwiftSyntax.ExtensionDeclSyntax] {
        
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.invalidDeclaration("AutoSchema can only be applied to structs")
        }
        
        // Extract all stored properties (exclude computed properties and methods)
        let properties = try extractStoredProperties(from: structDecl)
        
        // Generate the complete extension with all required methods
        let extensionDecl = try DeclSyntax("""
            extension \(type.trimmed): JSONSchemaGenerator, Decodable {
                
                /// Generates OpenAI-compatible JSON Schema as a dictionary
                /// 
                /// Returns a complete JSON Schema following OpenAI Structured Outputs specification:
                /// - type: "object"
                /// - properties: detailed field definitions with types and descriptions
                /// - required: array of non-optional field names
                /// - additionalProperties: false (strict validation)
                static func generateOpenAISchema() -> [String: Any] {
                    return [
                        "type": "object",
                        "properties": [
                            \(raw: generateSchemaProperties(from: properties))
                        ],
                        "required": [\(raw: generateRequiredFields(from: properties))],
                        "additionalProperties": false
                    ]
                }
                
                /// Generates OpenAI-compatible JSON Schema as a formatted JSON string
                /// 
                /// This method returns the schema in a format ready to use with OpenAI API.
                /// The JSON is pretty-printed for better readability.
                static func generateOpenAISchemaString() -> String {
                    let schema = generateOpenAISchema()
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys])
                        return String(data: jsonData, encoding: .utf8) ?? "{}"
                    } catch {
                        return "{}"
                    }
                }
                
                /// Creates an instance from JSON string using standard JSONDecoder
                /// 
                /// This method uses JSONDecoder with ISO8601 date decoding strategy
                /// to parse JSON responses from OpenAI API.
                /// 
                /// - Parameter jsonString: Valid JSON string matching the schema
                /// - Returns: Decoded instance of the struct
                /// - Throws: DecodingError if JSON is invalid or doesn't match expected structure
                static func create(from jsonString: String) throws -> Self {
                    guard let data = jsonString.data(using: .utf8) else {
                        throw DecodingError.dataCorrupted(
                            DecodingError.Context(codingPath: [], debugDescription: "Invalid UTF-8 string")
                        )
                    }
                    
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    return try decoder.decode(Self.self, from: data)
                }
            }
            """)
        
        guard let extensionDecl = extensionDecl.as(ExtensionDeclSyntax.self) else {
            throw MacroError.invalidGeneration("Failed to generate extension")
        }
        
        return [extensionDecl]
    }
    
    /// Extracts all stored properties from a struct declaration
    /// 
    /// This method processes the struct's member list and extracts:
    /// - Property name
    /// - Property type (including optional types)
    /// - @SchemaField attribute information
    /// 
    /// Only stored properties (let/var with explicit types) are included.
    /// Computed properties and methods are excluded.
    private static func extractStoredProperties(from structDecl: StructDeclSyntax) throws -> [(String, TypeSyntax, SchemaFieldInfo)] {
        var properties: [(String, TypeSyntax, SchemaFieldInfo)] = []
        
        for member in structDecl.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self),
               let binding = varDecl.bindings.first,
               let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
               let typeAnnotation = binding.typeAnnotation {
                
                let fieldInfo = extractSchemaFieldInfo(from: varDecl.attributes)
                properties.append((identifier.identifier.text, typeAnnotation.type, fieldInfo))
            }
        }
        
        return properties
    }
    
    /// Extracts @SchemaField attribute information from property attributes
    /// 
    /// Parses @SchemaField parameters to extract:
    /// - description: Human-readable field description
    /// - isRequired: Whether field should be in required array
    /// - Validation parameters (minLength, maxLength, minimum, maximum, etc.)
    private static func extractSchemaFieldInfo(from attributes: AttributeListSyntax) -> SchemaFieldInfo {
        for attribute in attributes {
            if let customAttribute = attribute.as(AttributeSyntax.self),
               let identifierType = customAttribute.attributeName.as(IdentifierTypeSyntax.self),
               identifierType.name.text == "SchemaField" {
                
                var info = SchemaFieldInfo()
                
                if let arguments = customAttribute.arguments?.as(LabeledExprListSyntax.self) {
                    for argument in arguments {
                        guard let label = argument.label?.text else { continue }
                        
                        switch label {
                        case "description":
                            if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
                               let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                                info.description = segment.content.text
                            }
                        case "isRequired":
                            if let boolLiteral = argument.expression.as(BooleanLiteralExprSyntax.self) {
                                info.isRequired = boolLiteral.literal.text == "true"
                            }
                        case "minLength":
                            if let intLiteral = argument.expression.as(IntegerLiteralExprSyntax.self) {
                                info.minLength = Int(intLiteral.literal.text)
                            }
                        case "maxLength":
                            if let intLiteral = argument.expression.as(IntegerLiteralExprSyntax.self) {
                                info.maxLength = Int(intLiteral.literal.text)
                            }
                        case "minimum":
                            if let floatLiteral = argument.expression.as(FloatLiteralExprSyntax.self) {
                                info.minimum = Double(floatLiteral.literal.text)
                            } else if let intLiteral = argument.expression.as(IntegerLiteralExprSyntax.self) {
                                info.minimum = Double(intLiteral.literal.text) ?? 0
                            }
                        case "maximum":
                            if let floatLiteral = argument.expression.as(FloatLiteralExprSyntax.self) {
                                info.maximum = Double(floatLiteral.literal.text)
                            } else if let intLiteral = argument.expression.as(IntegerLiteralExprSyntax.self) {
                                info.maximum = Double(intLiteral.literal.text) ?? 0
                            }
                        case "pattern":
                            if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
                               let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                                info.pattern = segment.content.text
                            }
                        case "format":
                            if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
                               let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                                info.format = segment.content.text
                            }
                        case "example":
                            if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
                               let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                                info.example = segment.content.text
                            }
                        default:
                            break
                        }
                    }
                }
                
                return info
            }
        }
        
        return SchemaFieldInfo() // Default values if no @SchemaField attribute
    }
    
    /// Generates the properties section of JSON Schema
    /// 
    /// Creates a properly formatted string for the "properties" object in JSON Schema.
    /// Each property includes:
    /// - type: JSON Schema type (string, integer, number, boolean, array, object)
    /// - description: Human-readable description from @SchemaField
    /// - Validation constraints when applicable
    /// - For nested SchemaObject types: embedded complete schema
    private static func generateSchemaProperties(from properties: [(String, TypeSyntax, SchemaFieldInfo)]) -> String {
        let propertiesCode = properties.map { (name, type, fieldInfo) in
            let typeInfo = getJSONSchemaType(for: type)
            var propertyDict: [String] = []
            
            // Handle nested SchemaObject types
            if typeInfo.isNestedSchemaObject {
                // Generate code that will check at runtime if type conforms to JSONSchemaGenerator
                // and if so, embed its schema directly
                propertyDict.append("""
                    (\(typeInfo.typeName).self as? any JSONSchemaGenerator.Type)?.generateOpenAISchema() ?? ["type": "object"]
                    """)
            } else if typeInfo.type == "array" {
                if typeInfo.isArrayOfSchemaObjects {
                    // For arrays of SchemaObjects, create schema with nested object definition
                    propertyDict.append("\"type\": \"array\"")
                    propertyDict.append("""
                        "items": (\(typeInfo.arrayElementTypeName).self as? any JSONSchemaGenerator.Type)?.generateOpenAISchema() ?? ["type": "object"]
                        """)
                } else {
                    // Regular array handling
                    propertyDict.append("\"type\": \"array\"")
                    propertyDict.append("\"items\": \(typeInfo.itemsSchema)")
                }
            } else {
                propertyDict.append("\"type\": \"\(typeInfo.type)\"")
            }
            
            // Add description if provided (only for non-nested objects to avoid conflicts)
            if let description = fieldInfo.description, !typeInfo.isNestedSchemaObject {
                if !propertyDict.isEmpty && !propertyDict[0].contains("JSONSchemaGenerator") {
                    propertyDict.append("\"description\": \"\(description)\"")
                }
            }
            
            // Add validation constraints based on type (only for primitive types)
            if !typeInfo.isNestedSchemaObject && !typeInfo.isArrayOfSchemaObjects {
                if typeInfo.type == "string" || (typeInfo.type == "array" && typeInfo.itemsSchema.contains("string")) {
                    if let minLength = fieldInfo.minLength {
                        propertyDict.append("\"minLength\": \(minLength)")
                    }
                    if let maxLength = fieldInfo.maxLength {
                        propertyDict.append("\"maxLength\": \(maxLength)")
                    }
                    if let pattern = fieldInfo.pattern {
                        propertyDict.append("\"pattern\": \"\(pattern)\"")
                    }
                    if let format = fieldInfo.format {
                        propertyDict.append("\"format\": \"\(format)\"")
                    }
                }
                
                if typeInfo.type == "integer" || typeInfo.type == "number" {
                    if let minimum = fieldInfo.minimum {
                        propertyDict.append("\"minimum\": \(minimum)")
                    }
                    if let maximum = fieldInfo.maximum {
                        propertyDict.append("\"maximum\": \(maximum)")
                    }
                }
                
                if let example = fieldInfo.example {
                    propertyDict.append("\"example\": \"\(example)\"")
                }
            }
            
            // Format the property definition
            if typeInfo.isNestedSchemaObject {
                return "\"\(name)\": \(propertyDict[0])"
            } else if typeInfo.isArrayOfSchemaObjects {
                return "\"\(name)\": [\(propertyDict.joined(separator: ", "))]"
            } else {
                let propertyDefinition = propertyDict.joined(separator: ", ")
                return "\"\(name)\": [\(propertyDefinition)]"
            }
        }
        
        return propertiesCode.joined(separator: ",\n            ")
    }
    
    /// Generates the required fields array for JSON Schema
    /// 
    /// Determines which fields should be included in the "required" array:
    /// - Fields with isRequired: true in @SchemaField
    /// - BUT excludes Swift optional types (String?, Int?, etc.) regardless of isRequired setting
    /// 
    /// This ensures that optional Swift types are never required in the schema,
    /// which aligns with OpenAI's expectations for structured outputs.
    private static func generateRequiredFields(from properties: [(String, TypeSyntax, SchemaFieldInfo)]) -> String {
        let requiredFields = properties.compactMap { (name, type, fieldInfo) -> String? in
            // Check if this is an optional Swift type (String?, Int?, etc.)
            let isOptionalType = type.as(OptionalTypeSyntax.self) != nil
            
            // Field is required only if:
            // 1. Explicitly marked as required in @SchemaField (default: true)
            // 2. AND it's not an optional Swift type
            if fieldInfo.isRequired && !isOptionalType {
                return "\"\(name)\""
            }
            return nil
        }
        
        return requiredFields.joined(separator: ", ")
    }
    
    /// Maps Swift types to JSON Schema types with comprehensive support
    /// 
    /// Handles the mapping between Swift type system and JSON Schema types:
    /// - Swift String → JSON Schema "string"
    /// - Swift Int/Int32/Int64 → JSON Schema "integer"  
    /// - Swift Float/Double → JSON Schema "number"
    /// - Swift Bool → JSON Schema "boolean"
    /// - Swift [T] → JSON Schema "array" with items schema
    /// - Custom structs → JSON Schema "object" (with nested schema support)
    /// - Optional types → same as wrapped type (optional handled in required array)
    /// 
    /// Returns tuple with:
    /// - type: JSON Schema type string
    /// - itemsSchema: Schema for array items (if array type)
    /// - isNestedSchemaObject: Whether this is a custom type that might implement JSONSchemaGenerator
    /// - isArrayOfSchemaObjects: Whether this is array of custom objects
    /// - typeName: Original Swift type name
    /// - arrayElementTypeName: Type name of array elements (if array)
    private static func getJSONSchemaType(for type: TypeSyntax) -> (type: String, itemsSchema: String, isNestedSchemaObject: Bool, isArrayOfSchemaObjects: Bool, typeName: String, arrayElementTypeName: String) {
        let typeString = type.trimmed.description
        
        // Handle optional types by unwrapping them
        if let optionalType = type.as(OptionalTypeSyntax.self) {
            return getJSONSchemaType(for: optionalType.wrappedType)
        }
        
        // Handle array types
        if let arrayType = type.as(ArrayTypeSyntax.self) {
            let elementTypeString = arrayType.element.trimmed.description
            let elementTypeInfo = getJSONSchemaType(for: arrayType.element)
            
            if elementTypeInfo.isNestedSchemaObject {
                // Array of custom objects that might be SchemaObjects
                return ("array", "[\"type\": \"object\"]", false, true, typeString, elementTypeString)
            } else {
                // Array of primitive types
                return ("array", "[\"type\": \"\(elementTypeInfo.type)\"]", false, false, typeString, elementTypeString)
            }
        }
        
        // Handle basic Swift types
        switch typeString {
        case "String":
            return ("string", "", false, false, typeString, "")
        case "Int", "Int32", "Int64", "UInt", "UInt32", "UInt64":
            return ("integer", "", false, false, typeString, "")
        case "Float", "Double":
            return ("number", "", false, false, typeString, "")
        case "Bool":
            return ("boolean", "", false, false, typeString, "")
        default:
            // Custom types - assume they might be SchemaObjects
            return ("object", "", true, false, typeString, "")
        }
    }
}

/// Macro implementation for @SchemaField attribute
/// 
/// This is a peer macro that doesn't generate code but validates
/// that @SchemaField is only applied to stored properties.
/// The actual parameter processing happens in AutoSchemaMacro.
public struct SchemaFieldMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // This is a validation-only peer macro
        // The actual @SchemaField processing happens in AutoSchemaMacro
        // We just validate that it's applied to the correct declaration type
        
        guard declaration.is(VariableDeclSyntax.self) else {
            throw MacroError.invalidDeclaration("@SchemaField can only be applied to properties")
        }
        
        return [] // No additional code generation needed
    }
}

/// Macro implementation for generating enum schemas
/// 
/// This macro processes enums annotated with `@SchemaEnum()` and generates:
/// 1. Enum schema generation method (`generateEnumSchema`)
/// 2. Protocol conformances (`CaseIterable`, `RawRepresentable`)
/// 
/// Requirements:
/// - Enum must have String raw type
/// - All cases must have string values (explicit or implicit)
public struct SchemaEnumMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            throw MacroError.invalidDeclaration("@SchemaEnum can only be applied to enums")
        }
        
        // Extract all enum cases and their raw values
        let enumCases = try extractEnumCases(from: enumDecl)
        
        let extensionDecl = try DeclSyntax("""
            extension \(type.trimmed): CaseIterable, RawRepresentable {
                
                /// Generates JSON Schema for this enum type
                /// 
                /// Returns a JSON Schema with:
                /// - type: "string"
                /// - enum: array of all possible string values
                /// 
                /// This schema is compatible with OpenAI Structured Outputs
                /// and ensures the AI will only return valid enum values.
                static func generateEnumSchema() -> [String: Any] {
                    return [
                        "type": "string",
                        "enum": [\(raw: enumCases.map { "\"\($0)\"" }.joined(separator: ", "))]
                    ]
                }
            }
            """)
        
        guard let extensionDecl = extensionDecl.as(ExtensionDeclSyntax.self) else {
            throw MacroError.invalidGeneration("Failed to generate enum extension")
        }
        
        return [extensionDecl]
    }
    
    /// Extracts enum case names and their raw string values
    /// 
    /// For each enum case, determines the string value that will appear in JSON:
    /// - Explicit raw values: `case active = "is_active"` → "is_active"
    /// - Implicit raw values: `case pending` → "pending" 
    private static func extractEnumCases(from enumDecl: EnumDeclSyntax) throws -> [String] {
        var cases: [String] = []
        
        for member in enumDecl.memberBlock.members {
            if let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) {
                for element in caseDecl.elements {
                    if let rawValue = element.rawValue {
                        // Extract explicit raw value
                        if let stringLiteral = rawValue.value.as(StringLiteralExprSyntax.self),
                           let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                            cases.append(segment.content.text)
                        }
                    } else {
                        // Use case name as implicit raw value
                        cases.append(element.name.text)
                    }
                }
            }
        }
        
        return cases
    }
}

/// Data structure for storing @SchemaField attribute parameters
/// 
/// Holds all validation and metadata parameters that can be specified
/// in a @SchemaField attribute. Default values align with JSON Schema
/// and OpenAI Structured Outputs expectations.
struct SchemaFieldInfo {
    var description: String?     // Human-readable description for AI
    var isRequired: Bool = true  // Whether field is required (overridden by optional types)
    var minLength: Int?          // Minimum string length validation
    var maxLength: Int?          // Maximum string length validation  
    var minimum: Double?         // Minimum numeric value validation
    var maximum: Double?         // Maximum numeric value validation
    var pattern: String?         // Regular expression pattern for strings
    var format: String?          // Format hint (email, uri, date-time, etc.)
    var example: String?         // Example value for documentation
}

/// Custom error types for macro processing
/// 
/// Provides descriptive error messages when macros are applied incorrectly
/// or when code generation fails.
enum MacroError: Error, CustomStringConvertible {
    case invalidDeclaration(String)  // Macro applied to wrong declaration type
    case invalidGeneration(String)   // Code generation failed
    
    var description: String {
        switch self {
        case .invalidDeclaration(let message):
            return "Invalid declaration: \(message)"
        case .invalidGeneration(let message):
            return "Generation failed: \(message)"
        }
    }
}

/// Compiler plugin registration for all macros
/// 
/// Registers all macro implementations with the Swift compiler
/// so they can be used with their respective attributes.
@main
struct OpenAISchemaMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        AutoSchemaMacro.self,      // @SchemaObject()
        SchemaFieldMacro.self,     // @SchemaField(...)
        SchemaEnumMacro.self       // @SchemaEnum()
    ]
}
