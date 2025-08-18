import Foundation
import SwiftData

final class LocalDataManager {
    static let shared = LocalDataManager()
    let modelContainer: ModelContainer

    private init() {
        let schema = Schema([
            Recording.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        self.modelContainer = try! ModelContainer(for: schema, configurations: [config])
    }
}
