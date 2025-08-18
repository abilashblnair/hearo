import Foundation

final class LocalSessionRepository: SessionRepository {
    private var sessions: [Session] = []

    func create(_ session: Session) async throws {
        sessions.append(session)
    }

    func update(_ session: Session) async throws {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        }
    }

    func delete(id: UUID) async throws {
        sessions.removeAll { $0.id == id }
    }

    func fetchAll() async throws -> [Session] {
        return sessions
    }

    func fetch(id: UUID) async throws -> Session? {
        return sessions.first { $0.id == id }
    }
}
