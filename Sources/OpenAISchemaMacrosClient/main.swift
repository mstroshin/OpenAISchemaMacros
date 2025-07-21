import OpenAISchemaMacros
import Foundation

@SchemaObject()
struct Person {
    @SchemaField(description: "Full name of the person")
    let name: String
    
    @SchemaField(description: "Age in years")
    let age: Int
    
    @SchemaField(description: "Email address")
    let email: String?

    @SchemaField(description: "Work of the person")
    let work: Work
    
    @SchemaField(description: "List of skills")
    let skills: [Skill]
}

@SchemaObject()
struct Work {
    @SchemaField(description: "Title of the work")
    let title: String
    
    @SchemaField(description: "Company name")
    let company: String
}

@SchemaObject()
struct Skill {
    @SchemaField(description: "Name of the skill")
    let name: String
    
    @SchemaField(description: "Proficiency level from 1 to 10", minimum: 1, maximum: 10)
    let level: Int
}

print("=== Person Schema with nested objects ===")
print(Person.generateOpenAISchemaString())
print()

print("=== Individual Work Schema ===")
print(Work.generateOpenAISchemaString())
print()

print("=== Individual Skill Schema ===")
print(Skill.generateOpenAISchemaString())

let generatedPerson = """
{
  "name": "Алексей Смирнов",
  "age": 32,
  "email": "alexey.smirnov@example.com",
  "skills": [
    {
      "name": "Python",
      "level": 8
    },
    {
      "name": "Аналитика данных",
      "level": 7
    },
    {
      "name": "SQL",
      "level": 7
    },
    {
      "name": "Machine Learning",
      "level": 6
    }
  ],
  "work": {
    "company": "DataTech Solutions",
    "title": "Data Scientist"
  }
}
"""

let person = try? Person.create(from: generatedPerson)
print(person)