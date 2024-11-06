struct AlertInfo: Identifiable {
    enum AlertType {
        case one, two
    }
    
    let id: AlertType
    let deleteFile: Bool
    let title: String
    let message: String
    let torrent: Torrent
} 