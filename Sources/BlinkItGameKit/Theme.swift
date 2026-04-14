//
//  Theme.swift
//  recordGame
//
//  全 App 共用的亮色與卡片樣式。
//

import SwiftUI

enum Theme {
    static let accent = Color(red: 0.941, green: 0.725, blue: 0.035)
    static let textPrimary = Color(red: 0.118, green: 0.137, blue: 0.161)
    static let textSecondary = Color(red: 0.439, green: 0.478, blue: 0.541)
    static let divider = Color(red: 0.918, green: 0.925, blue: 0.933)
    static let surface = Color.white
    static let pageWash = Color(red: 0.973, green: 0.976, blue: 0.980)
    static let iconTintBg = Color(red: 1, green: 0.98, blue: 0.90)
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 14) -> some View {
        padding(14)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.surface)
                    .shadow(color: Color.black.opacity(0.07), radius: 14, x: 0, y: 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.divider, lineWidth: 1)
            )
    }
}
