//
//  BooksTrackerWidgetsBundle.swift
//  BooksTrackerWidgets
//
//  Created by Justin Gardner on 10/4/25.
//

import WidgetKit
import SwiftUI

@main
struct BooksTrackerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BooksTrackerWidgets()
        BooksTrackerWidgetsControl()
        BooksTrackerWidgetsLiveActivity()
    }
}
