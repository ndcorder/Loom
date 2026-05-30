//
//  Item.swift
//  Loom
//
//  Created by Yaroslav Fairfieldd on 5/30/26.
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
