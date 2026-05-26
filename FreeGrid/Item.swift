//
//  Item.swift
//  FreeGrid
//
//  Created by coni on 2026/5/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
