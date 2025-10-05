//
//  BooksTrackerWidgetsBundle.swift
//  BooksTrackerWidgets
//
//  Created by Justin Gardner on 10/4/25.
//

import WidgetKit
import SwiftUI
import BooksTrackerFeature

@main
struct BooksTrackerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BooksTrackerWidgets()
        BooksTrackerWidgetsControl()
        if #available(iOS 16.2, *) {
            CSVImportLiveActivity()
        }
    }
}
