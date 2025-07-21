# OpenAISchemaMacros

A Swift package that automatically generates OpenAI-compatible JSON schemas from Swift structs and enums using macros. Perfect for creating structured outputs with OpenAI's API while maintaining type safety in your Swift code.

## Features

- 🚀 **Automatic Schema Generation**: Convert Swift structs to JSON Schema with simple macro annotations
- 📝 **Rich Validation Support**: Built-in support for string length, numeric ranges, patterns, and format validation
- 🔄 **Bidirectional Conversion**: Generate schemas and parse JSON responses back to Swift objects
- 📚 **Enum Support**: First-class support for Swift enums with automatic string schema generation
- 🎯 **OpenAI Compatible**: Schemas follow OpenAI Structured Outputs specification
- 🛡️ **Type Safe**: Maintains Swift's type safety while working with dynamic JSON schemas
- 🏗️ **Nested Objects**: Support for complex nested object structures and arrays

## Requirements

- Swift 6.0+
- macOS 10.15+ / iOS 13.0+ / tvOS 13.0+ / watchOS 6.0+

## Installation

### Swift Package Manager

Add OpenAISchemaMacros to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mstroshin/OpenAISchemaMacros.git", from: "1.0.0")
]
```

Or add it through Xcode:
1. File → Add Package Dependencies
2. Enter the repository URL
3. Follow the prompts to add the package

## Quick Start

### Basic Usage

```swift
import OpenAISchemaMacros

@SchemaObject()
struct Person {
    @SchemaField(description: "Full name of the person")
    let name: String
    
    @SchemaField(description: "Age in years", minimum: 0, maximum: 150)
    let age: Int
    
    @SchemaField(description: "Email address", format: "email")
    let email: String?
}

// Generate JSON Schema
let schema = Person.generateOpenAISchema()
print(Person.generateOpenAISchemaString())

// Parse JSON response from OpenAI
let jsonResponse = """
{
    "name": "John Doe",
    "age": 30,
    "email": "john@example.com"
}
"""

let person = try Person.create(from: jsonResponse)
```

### Advanced Validation

```swift
@SchemaObject()
struct User {
    @SchemaField(
        description: "Username for the account",
        minLength: 3,
        maxLength: 20,
        pattern: "^[a-zA-Z0-9_]+$"
    )
    let username: String
    
    @SchemaField(
        description: "User's bio",
        maxLength: 500
    )
    let bio: String?
    
    @SchemaField(
        description: "Account balance",
        minimum: 0
    )
    let balance: Double
}
```

### Enums

```swift
@SchemaEnum()
enum Priority: String, Codable {
    case low
    case medium
    case high
    case urgent
}

@SchemaObject()
struct Task {
    @SchemaField(description: "Task title")
    let title: String
    
    @SchemaField(description: "Task priority level")
    let priority: Priority
}
```

### Nested Objects and Arrays

```swift
@SchemaObject()
struct Address {
    @SchemaField(description: "Street address")
    let street: String
    
    @SchemaField(description: "City name")
    let city: String
    
    @SchemaField(description: "ZIP/Postal code")
    let zipCode: String
}

@SchemaObject()
struct Company {
    @SchemaField(description: "Company name")
    let name: String
    
    @SchemaField(description: "Company address")
    let address: Address
    
    @SchemaField(description: "List of employee names")
    let employees: [String]
}
```

## API Reference

### Macros

#### `@SchemaObject()`
Converts a Swift struct into a JSON Schema generator. Automatically adds:
- `generateOpenAISchema()` - Returns schema as dictionary
- `generateOpenAISchemaString()` - Returns formatted JSON string
- `create(from:)` - Creates object from JSON string
- `Decodable` conformance

#### `@SchemaField(parameters...)`
Defines schema properties and validation for struct fields.

**Parameters:**
- `description: String?` - Human-readable field description
- `isRequired: Bool = true` - Whether field is required (overridden by optional types)
- `minLength: Int?` - Minimum string length
- `maxLength: Int?` - Maximum string length
- `minimum: Double?` - Minimum numeric value
- `maximum: Double?` - Maximum numeric value
- `pattern: String?` - Regular expression pattern
- `format: String?` - Format hint (email, uri, date-time, etc.)
- `example: String?` - Example value

#### `@SchemaEnum()`
Generates JSON Schema for String-based enums. Creates:
- `generateEnumSchema()` - Returns enum schema with all possible values
- `CaseIterable` and `RawRepresentable` conformance

### Generated Schema Example

For the `Person` struct above, the generated schema would be:

```json
{
  "type": "object",
  "properties": {
    "name": {
      "type": "string",
      "description": "Full name of the person"
    },
    "age": {
      "type": "integer",
      "description": "Age in years",
      "minimum": 0,
      "maximum": 150
    },
    "email": {
      "type": "string",
      "description": "Email address",
      "format": "email"
    }
  },
  "required": ["name", "age"],
  "additionalProperties": false
}
```

## Use Cases

### OpenAI Function Calling

```swift
@SchemaObject()
struct WeatherQuery {
    @SchemaField(description: "City name")
    let city: String
    
    @SchemaField(description: "Temperature unit")
    let unit: TemperatureUnit
}

@SchemaEnum()
enum TemperatureUnit: String, Codable {
    case celsius
    case fahrenheit
}

// Use the schema with OpenAI Function Calling
let functionSchema = WeatherQuery.generateOpenAISchema()
// Send to OpenAI API...
```

### Data Validation

```swift
@SchemaObject()
struct CreateUserRequest {
    @SchemaField(
        description: "User email address",
        format: "email",
        pattern: "^[\\w\\.-]+@[\\w\\.-]+\\.[a-zA-Z]{2,}$"
    )
    let email: String
    
    @SchemaField(
        description: "Password",
        minLength: 8,
        maxLength: 128
    )
    let password: String
}

// Validate incoming JSON matches expected structure
let user = try CreateUserRequest.create(from: requestBody)
```

## Best Practices

1. **Use Descriptive Field Descriptions**: AI models rely on descriptions to understand field purpose
2. **Leverage Validation Parameters**: Use `minLength`, `maximum`, etc. to constrain AI responses
3. **Optional vs Required**: Swift optional types (`String?`) are automatically non-required
4. **Enum for Constrained Choices**: Use `@SchemaEnum()` when you want to limit AI to specific values
5. **Nested Objects**: Break complex data into smaller, reusable `@SchemaObject()` structs

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with Swift Macros
- Compatible with OpenAI Structured Outputs
- Inspired by the need for type-safe AI integration in Swift applications 