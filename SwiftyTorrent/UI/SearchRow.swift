//
//  SearchRow.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 30.06.2026.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import SwiftUI

struct SearchRow: View {
    
    var model: SearchDataItem
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading) {
                Text(model.title)
                    .font(Font.headline)
                    .bold()
                    .lineLimit(2)
                Spacer(minLength: 5)
                Text("\(model.size), \(model.details)")
                    .font(Font.subheadline)
            }
        }
    }
    
}
