import Foundation

public struct Tracks: Identifiable, Hashable {
    public var id: Int32 { index }
    public let index: Int32
    public let name: String
    
    public init(index: Int32, name: String) {
        self.index = index
        self.name = name
    }
}
