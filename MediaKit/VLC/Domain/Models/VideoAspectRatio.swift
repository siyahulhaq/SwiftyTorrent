import Foundation

public enum VideoAspectRatio: String, CaseIterable, Identifiable {
    case fit = "Fit"
    case fill = "Fill"
    case stretch = "Stretch"
    case sixteenNine = "16:9"
    case fourThree = "4:3"
    case cinemascope = "2.35:1"
    
    public var id: String { rawValue }
    
    public var subtitle: String {
        switch self {
        case .fit: return "Letterboxed, original aspect"
        case .fill: return "Zoomed to fill screen"
        case .stretch: return "Stretched to fill screen"
        case .sixteenNine: return "Widescreen"
        case .fourThree: return "Standard"
        case .cinemascope: return "Ultra-widescreen"
        }
    }
    
    public var iconName: String {
        switch self {
        case .fit: return "arrow.down.right.and.arrow.up.left"
        case .fill: return "arrow.up.left.and.arrow.down.right"
        case .stretch: return "arrow.left.and.right"
        case .sixteenNine: return "rectangle.ratio.16.to.9"
        case .fourThree: return "rectangle.ratio.4.to.3"
        case .cinemascope: return "rectangle.expand.vertical"
        }
    }
}
