public class Torrent {
    private let torrent: STTorrent
    
    public var size: Int64 {
        return torrent.size
    }
    
    // ... rest of the properties and methods
} 