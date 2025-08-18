import Foundation
import SwiftUI

final class Router: ObservableObject {
    @Published var path: [Route] = []
    func push(_ r: Route) { path.append(r) }
    func pop() { _ = path.popLast() }
}
