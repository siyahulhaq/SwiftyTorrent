import Foundation

public enum HUDState: Equatable {
    case brightness(Float)
    case volume(Float)
    case seek(delta: Double, targetTime: String, totalTime: String, isForward: Bool)
}
