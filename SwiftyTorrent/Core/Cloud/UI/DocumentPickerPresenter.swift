//
//  DocumentPickerPresenter.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit

public struct DocumentPickerPresenter: UIViewControllerRepresentable {
    public let contentTypes: [UTType]
    public let onPick: (URL) -> Void
    public let onCancel: () -> Void
    
    public init(
        contentTypes: [UTType] = [.folder],
        onPick: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.contentTypes = contentTypes
        self.onPick = onPick
        self.onCancel = onCancel
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }
    
    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    
    public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    public class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void
        
        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }
        
        public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let first = urls.first {
                onPick(first)
            }
        }
        
        public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
#elseif os(macOS)
import AppKit

public struct DocumentPickerPresenter: View {
    public let contentTypes: [UTType]
    public let onPick: (URL) -> Void
    public let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    public init(
        contentTypes: [UTType] = [.folder],
        onPick: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.contentTypes = contentTypes
        self.onPick = onPick
        self.onCancel = onCancel
    }
    
    public var body: some View {
        Color.clear
            .onAppear {
                let panel = NSOpenPanel()
                panel.canChooseFiles = contentTypes.contains(where: { $0 != .folder })
                panel.canChooseDirectories = contentTypes.contains(.folder)
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    onPick(url)
                } else {
                    onCancel()
                }
                dismiss()
            }
    }
}
#else
public struct DocumentPickerPresenter: View {
    public init(
        contentTypes: [UTType] = [.folder],
        onPick: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {}
    
    public var body: some View {
        Text("Document picker is not available on this platform")
    }
}
#endif
