import Foundation
import UIKit

protocol AdManagerProtocol {
    var isAdReady: Bool { get }
    var isAdLoading: Bool { get }
    func preloadAd()
    func presentInterstitial(from rootViewController: UIViewController, onDismissed: @escaping (Bool) -> Void)
}
