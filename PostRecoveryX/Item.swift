//
//  Item.swift
//  PostRecoveryX
//
//  Created by Nicola Spieser on 10.07.2025.
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
