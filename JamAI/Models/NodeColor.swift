//
//  NodeColor.swift
//  JamAI
//
//  Defines color palette for node organization with proper text contrast
//

import SwiftUI

struct NodeColor: Identifiable, Equatable {
    let id: String
    let name: String
    let color: Color
    let lightVariant: Color
    
    init(id: String, name: String, hex: String, lightHex: String) {
        self.id = id
        self.name = name
        self.color = Color(hex: hex)
        self.lightVariant = Color(hex: lightHex)
    }
    
    // Returns text color (white or black) that contrasts well with the background
    func textColor(for backgroundColor: Color) -> Color {
        // Use white text for darker colors, black for lighter colors
        let luminance = backgroundColor.luminance
        return luminance > 0.5 ? .black : .white
    }
    
    /// Whether this is a light color (high luminance) that needs dark UI elements for contrast
    var isLightColor: Bool {
        return color.luminance > 0.5
    }
    
    // Static color palette matching FigJam style
    static let palette: [[NodeColor]] = [
        // Row 1: Vibrant colors
        [
            NodeColor(id: "none", name: "None", hex: "#6B7280", lightHex: "#E5E7EB"),
            NodeColor(id: "gray", name: "Gray", hex: "#6B7280", lightHex: "#E5E7EB"),
            NodeColor(id: "red", name: "Red", hex: "#EF4444", lightHex: "#FEE2E2"),
            NodeColor(id: "orange", name: "Orange", hex: "#F97316", lightHex: "#FFEDD5"),
            NodeColor(id: "yellow", name: "Yellow", hex: "#EAB308", lightHex: "#FEF3C7"),
            NodeColor(id: "green", name: "Green", hex: "#10B981", lightHex: "#D1FAE5"),
            NodeColor(id: "teal", name: "Teal", hex: "#14B8A6", lightHex: "#CCFBF1"),
            NodeColor(id: "blue", name: "Blue", hex: "#3B82F6", lightHex: "#DBEAFE"),
            NodeColor(id: "purple", name: "Purple", hex: "#8B5CF6", lightHex: "#EDE9FE"),
            NodeColor(id: "pink", name: "Pink", hex: "#EC4899", lightHex: "#FCE7F3"),
            NodeColor(id: "white", name: "White", hex: "#FFFFFF", lightHex: "#F9FAFB")
        ],
        // Row 2: Pastel/Light variants
        [
            NodeColor(id: "lightGray", name: "Light Gray", hex: "#9CA3AF", lightHex: "#F3F4F6"),
            NodeColor(id: "cream", name: "Cream", hex: "#E7E5E4", lightHex: "#FAF9F8"),
            NodeColor(id: "peach", name: "Peach", hex: "#FED7AA", lightHex: "#FFF7ED"),
            NodeColor(id: "lightYellow", name: "Light Yellow", hex: "#FDE68A", lightHex: "#FEFCE8"),
            NodeColor(id: "beige", name: "Beige", hex: "#FEF3C7", lightHex: "#FFFBEB"),
            NodeColor(id: "mint", name: "Mint", hex: "#A7F3D0", lightHex: "#ECFDF5"),
            NodeColor(id: "lightTeal", name: "Light Teal", hex: "#99F6E4", lightHex: "#F0FDFA"),
            NodeColor(id: "lightBlue", name: "Light Blue", hex: "#BFDBFE", lightHex: "#EFF6FF"),
            NodeColor(id: "lavender", name: "Lavender", hex: "#DDD6FE", lightHex: "#F5F3FF"),
            NodeColor(id: "lightPink", name: "Light Pink", hex: "#FBCFE8", lightHex: "#FDF2F8"),
            NodeColor(id: "rainbow", name: "Rainbow", hex: "rainbow", lightHex: "rainbow") // Special case
        ]
    ]
    
    static let allColors = palette.flatMap { $0 }
    
    static func color(for id: String) -> NodeColor? {
        if let match = allColors.first(where: { $0.id == id }) {
            return match
        }
        if id.hasPrefix("#") {
            return NodeColor(id: id, name: "Custom", hex: id, lightHex: id)
        }
        return nil
    }
}

// MARK: - Color Extensions

extension Color {
    init(hex: String) {
        if hex == "rainbow" {
            // Special rainbow gradient color
            self = Color(red: 0.8, green: 0.4, blue: 0.8)
            return
        }
        
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    // Calculate relative luminance for contrast ratio
    // Based on WCAG contrast ratio formula
    var luminance: Double {
        let components = self.cgColor?.components ?? [0, 0, 0, 1]
        let r = components[0]
        let g = components[1]
        let b = components[2]
        
        func adjust(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        
        return 0.2126 * adjust(r) + 0.7152 * adjust(g) + 0.0722 * adjust(b)
    }
}
