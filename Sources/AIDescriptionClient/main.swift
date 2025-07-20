import AIDescription
import Foundation

@AutoSchema(name: "Person", strict: false)
struct Person {
    @SchemaField(description: "Full name of the person")
    let name: String
    
    @SchemaField(description: "Age in years")
    let age: Int
    
    @SchemaField(description: "Email address", isRequired: false)
    let email: String?
}

// Example usage of create(from json:) function
let jsonString = """
{
    "name": "John Doe",
    "age": 30,
    "email": "john@example.com"
}
"""

do {
    let person = try Person.create(from: jsonString)
    print("Created person: \(person.name), age \(person.age)")
    if let email = person.email {
        print("Email: \(email)")
    }
} catch {
    print("Failed to create person: \(error)")
}

