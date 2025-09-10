//
//  TutorialViewModel.swift
//  HearO
//
//  Created by Abilash Balasubramanian on 12/08/25.
//
import Foundation

struct TutorialPage: Identifiable, Codable {
    let id: UUID = UUID()
    let imageName: String
    let title: String
    let description: String

    private enum CodingKeys: String, CodingKey {
        case imageName, title, description
    }
}

class TutorialViewModel: ObservableObject {
    @Published var pages: [TutorialPage] = []
    init() {
        loadPages()
    }
    private func loadPages() {
        guard let url = Bundle.main.url(forResource: "tutorial_pages", withExtension: "json") else {
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([TutorialPage].self, from: data)
            self.pages = decoded
        } catch {
        }
    }
}
