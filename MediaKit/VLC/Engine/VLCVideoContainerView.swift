import UIKit

public final class VLCVideoContainerView: UIView {
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = .black
        clipsToBounds = true
        autoresizingMask = []
    }
    
    public func attach(playerView: UIView) {
        playerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    public func applyAspectRatio(_ ratio: VideoAspectRatio, nativeVideoSize: CGSize, in screenBounds: CGRect, animated: Bool = true) {
        guard screenBounds.width > 0 && screenBounds.height > 0 else { return }
        
        let apply = {
            self.transform = .identity
            
            let videoAR: CGFloat
            if nativeVideoSize.width > 0 && nativeVideoSize.height > 0 {
                videoAR = nativeVideoSize.width / nativeVideoSize.height
            } else {
                videoAR = 16.0 / 9.0
            }
            
            switch ratio {
            case .fit:
                self.frame = self.fitRect(videoAR: videoAR, in: screenBounds)
                
            case .fill:
                self.frame = self.fillRect(videoAR: videoAR, in: screenBounds)
                
            case .stretch:
                self.frame = screenBounds
                
            case .sixteenNine:
                let targetAR: CGFloat = 16.0 / 9.0
                let fitFrame = self.fitRect(videoAR: targetAR, in: screenBounds)
                self.frame = fitFrame
                if videoAR != targetAR {
                    let scaleX = fitFrame.width / self.fitRect(videoAR: videoAR, in: fitFrame).width
                    let scaleY = fitFrame.height / self.fitRect(videoAR: videoAR, in: fitFrame).height
                    self.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
                }
                
            case .fourThree:
                let targetAR: CGFloat = 4.0 / 3.0
                let fitFrame = self.fitRect(videoAR: targetAR, in: screenBounds)
                self.frame = fitFrame
                if videoAR != targetAR {
                    let scaleX = fitFrame.width / self.fitRect(videoAR: videoAR, in: fitFrame).width
                    let scaleY = fitFrame.height / self.fitRect(videoAR: videoAR, in: fitFrame).height
                    self.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
                }
                
            case .cinemascope:
                let targetAR: CGFloat = 2.35
                let fitFrame = self.fitRect(videoAR: targetAR, in: screenBounds)
                self.frame = fitFrame
                if videoAR != targetAR {
                    let scaleX = fitFrame.width / self.fitRect(videoAR: videoAR, in: fitFrame).width
                    let scaleY = fitFrame.height / self.fitRect(videoAR: videoAR, in: fitFrame).height
                    self.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
                }
            }
        }
        
        if animated {
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85,
                           initialSpringVelocity: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                apply()
            }
        } else {
            apply()
        }
    }
    
    private func fitRect(videoAR: CGFloat, in container: CGRect) -> CGRect {
        guard container.width > 0 && container.height > 0, videoAR > 0 else {
            return container
        }
        let containerAR = container.width / container.height
        var fitSize: CGSize
        if videoAR > containerAR {
            fitSize = CGSize(width: container.width, height: container.width / videoAR)
        } else {
            fitSize = CGSize(width: container.height * videoAR, height: container.height)
        }
        let origin = CGPoint(
            x: container.midX - fitSize.width / 2,
            y: container.midY - fitSize.height / 2
        )
        return CGRect(origin: origin, size: fitSize)
    }
    
    private func fillRect(videoAR: CGFloat, in container: CGRect) -> CGRect {
        guard container.width > 0 && container.height > 0, videoAR > 0 else {
            return container
        }
        let containerAR = container.width / container.height
        var fillSize: CGSize
        if videoAR > containerAR {
            fillSize = CGSize(width: container.height * videoAR, height: container.height)
        } else {
            fillSize = CGSize(width: container.width, height: container.width / videoAR)
        }
        let origin = CGPoint(
            x: container.midX - fillSize.width / 2,
            y: container.midY - fillSize.height / 2
        )
        return CGRect(origin: origin, size: fillSize)
    }
}

public typealias KSVideoContainerView = VLCVideoContainerView

