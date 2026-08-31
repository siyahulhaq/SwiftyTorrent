//
//  AppIntent.swift
//  Torrents_Widget
//
//  Created by Siyahul Haq on 05/11/24.
//  Copyright © 2024 Siyahul Haq. All rights reserved.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Configuration" }
    static var description: IntentDescription { "This is an example widget." }

    // An example configurable parameter.
    @Parameter(title: "Favorite Emoji", default: "😃")
    var favoriteEmoji: String
}
