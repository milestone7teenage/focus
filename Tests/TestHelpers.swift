import Foundation
import SwiftData
import focus

/// Shared in-memory ModelContainer factory for all tests.
/// Single definition to avoid redeclaration across test files.
public enum TestContainer {
    public static func make() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: SchemaV1.schema, configurations: config)
    }
}