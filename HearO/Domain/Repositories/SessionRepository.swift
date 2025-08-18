import Foundation

protocol SessionRepository {
    func create(_ session: Session) async throws
    func update(_ session: Session) async throws
    func delete(id: UUID) async throws
    func fetchAll() async throws -> [Session]
    func fetch(id: UUID) async throws -> Session?
}
