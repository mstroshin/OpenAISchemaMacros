import Foundation
import OpenAISchemaMacros

@SchemaObject()
struct Person: Codable {
    @SchemaField(description: "Full name of the person")
    let name: String

    @SchemaField(description: "Age in years")
    let age: Int

    @SchemaField(description: "Email address")
    let email: String?
}
