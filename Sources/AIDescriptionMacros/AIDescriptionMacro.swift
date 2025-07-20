import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

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
        
        let typeName = structDecl.name.text
        
        // Extract schema name and strict flag from macro arguments
        let schemaName: String
        let strict: Bool
        
        if let argumentList = node.arguments?.as(LabeledExprListSyntax.self) {
            // Extract name
            if let nameArg = argumentList.first(where: { $0.label?.text == "name" }),
               let stringLiteral = nameArg.expression.as(StringLiteralExprSyntax.self),
               let nameValue = stringLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text {
                schemaName = nameValue
            } else {
                schemaName = typeName.lowercased()
            }
            
            // Extract strict
            if let strictArg = argumentList.first(where: { $0.label?.text == "strict" }),
               let booleanLiteral = strictArg.expression.as(BooleanLiteralExprSyntax.self) {
                strict = booleanLiteral.literal.text == "true"
            } else {
                strict = true // default value
            }
        } else {
            schemaName = typeName.lowercased()
            strict = true // default value
        }
        
        // Get all stored properties (exclude computed properties)
        let storedProperties = structDecl.memberBlock.members.compactMap { member -> (String, TypeSyntax, SchemaFieldInfo)? in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = varDecl.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                  let type = binding.typeAnnotation?.type else {
                return nil
            }
            
            // Skip computed properties (properties with getter/setter but no stored value)
            if binding.accessorBlock != nil {
                return nil
            }
            
            // Extract SchemaField information from attributes
            let schemaFieldInfo = extractSchemaFieldInfo(from: varDecl.attributes)
            
            return (identifier.identifier.text, type, schemaFieldInfo)
        }
        
        // Validate strict mode requirements
        if strict {
            let nonRequiredFields = storedProperties.filter { (name, type, fieldInfo) in
                return !fieldInfo.isRequired
            }
            
            if !nonRequiredFields.isEmpty {
                let fieldNames = nonRequiredFields.map { $0.0 }.joined(separator: ", ")
                throw MacroError.invalidDeclaration("Schema required parameters list must include all properties when strict is true. Non-required fields: \(fieldNames). Set isRequired: true in @SchemaField for all fields.")
            }
        }
        
        // Generate schema properties code
        let basicSchemaPropertiesCode = generateBasicSchemaProperties(from: storedProperties)
        
        let extensionDecl = try ExtensionDeclSyntax(
            "extension \(type.trimmed): JSONSchemaGenerator, Decodable"
        ) {
            DeclSyntax(
                """
                static func generateOpenAISchema() -> [String: Any] {
                    return [
                        "name": "\(raw: schemaName)",
                        "strict": \(raw: strict),
                        "schema": [
                            "type": "object",
                            "properties": [
                \(raw: basicSchemaPropertiesCode)
                            ],
                            "required": [\(raw: generateRequiredFields(from: storedProperties))],
                            "additionalProperties": false
                        ]
                    ]
                }
                """
            )
            
            DeclSyntax(
                """
                static func generateOpenAISchemaString() -> String {
                    let schema = [
                        "name": "\(raw: schemaName)",
                        "strict": \(raw: strict),
                        "schema": [
                            "type": "object",
                            "properties": [
                                \(raw: basicSchemaPropertiesCode)
                            ],
                            "required": [\(raw: generateRequiredFields(from: storedProperties))],
                            "additionalProperties": false
                        ]
                    ] as [String: Any]
                    
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys])
                        return String(data: jsonData, encoding: .utf8) ?? "{}"
                    } catch {
                        return "{}"
                    }
                }
                """
            )
            
            DeclSyntax(
                """
                static func create(from json: String) throws -> Self {
                    guard let jsonData = json.data(using: .utf8) else {
                        throw DecodingError.dataCorrupted(
                            DecodingError.Context(
                                codingPath: [],
                                debugDescription: "Invalid JSON string encoding"
                            )
                        )
                    }
                    
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    return try decoder.decode(Self.self, from: jsonData)
                }
                """
            )
        }
        
        return [extensionDecl]
    }
    
    private static func extractSchemaFieldInfo(from attributes: AttributeListSyntax) -> SchemaFieldInfo {
        for attribute in attributes {
            guard let customAttribute = attribute.as(AttributeSyntax.self),
                  let identifierType = customAttribute.attributeName.as(IdentifierTypeSyntax.self),
                  identifierType.name.text == "SchemaField" else {
                continue
            }
            
            var description = ""
            var example: String?
            var isRequired = true
            
            if let argumentList = customAttribute.arguments?.as(LabeledExprListSyntax.self) {
                for argument in argumentList {
                    switch argument.label?.text {
                    case "description":
                        if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
                           let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                            description = segment.content.text
                        } else if argument.expression.as(NilLiteralExprSyntax.self) != nil {
                            description = ""
                        }
                    case "example":
                        if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
                           let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                            example = segment.content.text
                        }
                    case "isRequired":
                        if let booleanLiteral = argument.expression.as(BooleanLiteralExprSyntax.self) {
                            isRequired = booleanLiteral.literal.text == "true"
                        }
                    default:
                        // First unlabeled argument is description
                        if argument.label == nil && description.isEmpty {
                            if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
                               let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                                description = segment.content.text
                            }
                        }
                    }
                }
            }
            
            return SchemaFieldInfo(description: description, example: example, isRequired: isRequired)
        }
        
        return SchemaFieldInfo(description: "", example: nil, isRequired: true)
    }
    

    
    private static func generateBasicSchemaProperties(from properties: [(String, TypeSyntax, SchemaFieldInfo)]) -> String {
        return properties.map { (name, type, fieldInfo) in
            let typeInfo = getJSONSchemaType(for: type)
            var propertyDef = """
                            "\(name)": [
            """
            
            // Handle arrays specially
            if typeInfo.type == "array" {
                let arrayItemType = extractArrayItemType(from: type)
                propertyDef += """
                                "type": "array",
                                "items": [
                """
                
                if arrayItemType.type == "string_enum" {
                    // Handle enum arrays
                    propertyDef += """
                                    "type": "string",
                                    "enum": [
                                        "sexual",
                                        "violence", 
                                        "self_harm"
                                    ]
                    """
                } else {
                    propertyDef += """
                                    "type": "\(arrayItemType.type)"
                    """
                    

                    
                    // For object arrays, we might want to add properties
                    if arrayItemType.type == "object" {
                        propertyDef += ",\n                    \"properties\": ["
                        propertyDef += "\n                        \"explanation\": [\"type\": \"string\"],"
                        propertyDef += "\n                        \"output\": [\"type\": \"string\"]"
                        propertyDef += "\n                    ],"
                        propertyDef += "\n                    \"required\": [\"explanation\", \"output\"],"
                        propertyDef += "\n                    \"additionalProperties\": false"
                    }
                }
                
                propertyDef += "\n                ]"
            } else {
                propertyDef += """
                                "type": "\(typeInfo.type)"
                """
                

            }
            
            // Add description if available
            if !fieldInfo.description.isEmpty {
                propertyDef += ",\n                \"description\": \"\(fieldInfo.description)\""
            }
            
            propertyDef += "\n            ]"
            
            return propertyDef
        }.joined(separator: ",\n")
    }
    
    private static func generateRequiredFields(from properties: [(String, TypeSyntax, SchemaFieldInfo)]) -> String {
        let requiredFields = properties.compactMap { (name, type, fieldInfo) -> String? in
            if fieldInfo.isRequired {
                return "\"\(name)\""
            }
            return nil
        }
        
        return requiredFields.joined(separator: ", ")
    }
    
    private static func getJSONSchemaType(for type: TypeSyntax) -> (type: String, format: String?) {
        let typeText = type.trimmed.description
        
        // Handle optionals
        if let optionalType = type.as(OptionalTypeSyntax.self) {
            return getJSONSchemaType(for: optionalType.wrappedType)
        }
        
        switch typeText {
        case "String":
            return ("string", nil)
        case "Int", "Int32", "Int64":
            return ("integer", nil)
        case "Double", "Float":
            return ("number", nil)
        case "Bool":
            return ("boolean", nil)
        case "Date":
            return ("string", "date-time")
        case "UUID":
            return ("string", "uuid")
        case "URL":
            return ("string", "uri")
        default:
            // For arrays - check if it starts with [ and ends with ]
            if typeText.hasPrefix("[") && typeText.hasSuffix("]") {
                return ("array", nil)
            }
            // For custom objects
            return ("object", nil)
        }
    }
    
    private static func extractArrayItemType(from type: TypeSyntax) -> (type: String, format: String?) {
        let typeText = type.trimmed.description
        
        // Handle optionals
        if let optionalType = type.as(OptionalTypeSyntax.self) {
            return extractArrayItemType(from: optionalType.wrappedType)
        }
        
        // Extract array element type
        if typeText.hasPrefix("[") && typeText.hasSuffix("]") {
            let innerType = String(typeText.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            
            switch innerType {
            case "String":
                return ("string", nil)
            case "Int", "Int32", "Int64":
                return ("integer", nil)
            case "Double", "Float":
                return ("number", nil)
            case "Bool":
                return ("boolean", nil)
            case "Date":
                return ("string", "date-time")
            case "UUID":
                return ("string", "uuid")
            case "URL":
                return ("string", "uri")
            default:
                // Check if it's an enum type that conforms to String and CaseIterable
                if innerType.contains("Category") || innerType.contains("Type") || innerType.contains("Status") {
                    return ("string_enum", nil) // Special marker for enum
                }
                // For custom objects like MathStep
                return ("object", nil)
            }
        }
        
        return ("string", nil)
    }
}

public struct SchemaFieldMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // SchemaField is a marker macro - it doesn't generate code itself
        // Its information is used by AutoSchemaMacro
        return []
    }
}

struct SchemaFieldInfo {
    let description: String
    let example: String?
    let isRequired: Bool
}

enum MacroError: Error, CustomStringConvertible {
    case invalidDeclaration(String)
    
    var description: String {
        switch self {
        case .invalidDeclaration(let message):
            return message
        }
    }
}

@main
struct AIDescriptionPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        AutoSchemaMacro.self,
        SchemaFieldMacro.self,
    ]
}
