//
//  FileRow.swift
//  SwiftyTorrent
//
//  Created by Danylo Kostyshyn on 7/16/19.
//  Copyright © 2019 Danylo Kostyshyn. All rights reserved.
//

import SwiftUI

struct FileRow: View {
    
    var model: FileRowModel
    
    var body: some View {
        HStack {
            Image(systemName: iconName)
                .resizable()
                .frame(width: 30, height: 30)
                .foregroundColor(iconColor)
                .padding(.trailing, 20)
            VStack(alignment: .leading) {
                Text(model.title)
                    .font(.headline)
                    .bold()
                    .lineLimit(2)
                if let deltails = model.sizeDetails {
                    Spacer(minLength: 5)
                    Text(deltails)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    private var iconName: String {
        if model.isDirectory {
            return "folder.fill"
        }
        if let file = model as? File {
            if file.isVideo {
                return "play.circle.fill"
            }
            if file.isImage {
                return "photo.circle.fill"
            }
        }
        return "doc.fill"
    }
    
    private var iconColor: Color {
        if model.isDirectory {
            return .blue
        }
        if let file = model as? File {
            if file.isVideo {
                return .red
            }
            if file.isImage {
                return .green
            }
            if file.isImage {
                return .green
            }
        }
        return .gray
    }
}
