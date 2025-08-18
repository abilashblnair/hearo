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
            print("[TutorialViewModel] Error: tutorial_pages.json not found in main bundle.")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([TutorialPage].self, from: data)
            self.pages = decoded
        } catch {
            print("[TutorialViewModel] Error loading or decoding tutorial_pages.json: \(error)")
        }
    }
}
