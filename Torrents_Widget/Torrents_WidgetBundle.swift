//
//  Torrents_WidgetBundle.swift
//  Torrents_Widget
//
//  Created by Siyahul Haq on 05/11/24.
//  Copyright © 2024 Siyahul Haq. All rights reserved.
//

import WidgetKit
import SwiftUI

@main
struct Torrents_WidgetBundle: WidgetBundle {
    var body: some Widget {
        Torrents_Widget()
//        Torrents_WidgetControl()
        Torrents_WidgetLiveActivity()
    }
}
