import Foundation

protocol Module {
    var id: String { get }
    var title: String { get }
    var icon: String { get }
    var defaultEnabled: Bool { get }
}
