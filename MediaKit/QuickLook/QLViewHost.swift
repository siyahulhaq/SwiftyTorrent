//
//  QLViewHost.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 01.07.2026.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import SwiftUI
#if canImport(QuickLook) && canImport(UIKit)
import QuickLook

class QLPreviewItemWrapper: NSObject, QLPreviewItem {

    var previewItemURL: URL? { _previewItemURL }
    var previewItemTitle: String? { _previewItemTitle }
    
    private var _previewItemURL: URL?
    private var _previewItemTitle: String?
    
    init(previewItem: PreviewItem) {
        _previewItemURL = previewItem.previewItemURL
        _previewItemTitle = previewItem.previewItemTitle
    }

}

public struct QLViewHost: UIViewControllerRepresentable {
    
    public var previewItem: PreviewItem
    
    public init(previewItem: PreviewItem) {
        self.previewItem = previewItem
    }

    public func makeCoordinator() -> QLViewHost.Coordinator {
        return Coordinator(previewItem: previewItem)
    }
    
    public typealias Context = UIViewControllerRepresentableContext<QLViewHost>
    public typealias Controller = QLPreviewController
    
    public func makeUIViewController(context: Context) -> Controller {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        return controller
    }
    
    public func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.dataSource = context.coordinator
        uiViewController.delegate = context.coordinator
    }

    public class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        
        var previewItem: PreviewItem
        
        init(previewItem: PreviewItem) {
            self.previewItem = previewItem
            super.init()
        }
        
        public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }
        
        public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return QLPreviewItemWrapper(previewItem: previewItem)
        }
        
    }
}

public struct QLPreviewModalView: View {
    public let previewItem: PreviewItem
    @Environment(\.dismiss) private var dismiss
    
    public init(previewItem: PreviewItem) {
        self.previewItem = previewItem
    }
    
    public var body: some View {
        NavigationStack {
            QLViewHost(previewItem: previewItem)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(previewItem.previewItemTitle ?? "Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Back")
                            }
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
    }
}
#elseif canImport(QuickLookUI) && canImport(AppKit)
import QuickLookUI
import AppKit

public struct QLViewHost: NSViewRepresentable {
    public var previewItem: PreviewItem
    
    public init(previewItem: PreviewItem) {
        self.previewItem = previewItem
    }
    
    public func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        if let url = previewItem.previewItemURL {
            view.previewItem = url as QLPreviewItem
        }
        return view
    }
    
    public func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if let url = previewItem.previewItemURL {
            nsView.previewItem = url as QLPreviewItem
        }
    }
}

public struct QLPreviewModalView: View {
    public let previewItem: PreviewItem
    @Environment(\.dismiss) private var dismiss
    
    public init(previewItem: PreviewItem) {
        self.previewItem = previewItem
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(previewItem.previewItemTitle ?? "Preview")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            QLViewHost(previewItem: previewItem)
                .frame(minWidth: 500, minHeight: 400)
        }
    }
}
#else
public struct QLPreviewModalView: View {
    public let previewItem: PreviewItem
    @Environment(\.dismiss) private var dismiss
    
    public init(previewItem: PreviewItem) {
        self.previewItem = previewItem
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            Text(previewItem.previewItemTitle ?? "Preview")
                .font(.headline)
            if let url = previewItem.previewItemURL {
                Text(url.lastPathComponent)
                    .foregroundColor(.secondary)
            }
            Button("Done") {
                dismiss()
            }
        }
        .padding()
    }
}
#endif
