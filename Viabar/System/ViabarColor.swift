import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// 品牌色板 —— 统一维护，全局引用
enum ViabarColor {
    // MARK: 主色调

    /// 主色 · 深蓝（默认项目进度色）
    static let primary = Color(hex: "#0085ff")
    /// 深紫（备用主色 / 强调）
    static let primaryDark = Color(hex: "#006fff")
    /// 中蓝（次级主色）
    static let primaryMedium = Color(hex: "#69b4ff")
    /// 浅蓝（辅助色）
    static let primaryLight = Color(hex: "#00BFFF")
    /// 极浅蓝（背景 / 卡片底色）
    static let primaryPale = Color(hex: "#e0ffff")
    /// 近白蓝（大面积背景）
    static let primaryGhost = Color(hex: "#F3FDFF")

    /// 主面板背景色；浅色维持系统窗口底色，深色使用自定义面板色。
#if os(macOS)
    static let mainPanelBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.20, alpha: 0.95)
            : NSColor.windowBackgroundColor
    })

    /// 备忘录区域保留原浅色底，并在深色时与主面板统一。
    static let mainPanelMemoBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.20, alpha: 0.95)
            : NSColor(calibratedWhite: 0.94, alpha: 1)
    })

    /// 输入与搜索控件底色；浅色继续使用系统控件背景。
    static let panelInputBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 11 / 255, green: 24 / 255, blue: 44 / 255, alpha: 1)
            : NSColor.controlBackgroundColor
    })
#else
    static let mainPanelBackground = Color(uiColor: .systemBackground)
    static let mainPanelMemoBackground = Color(uiColor: .secondarySystemBackground)
    static let panelInputBackground = Color(uiColor: .tertiarySystemBackground)
#endif

    // MARK: 状态色

    /// 危险 / 删除
    static let danger = Color(hex: "#FF4B41")
    /// 警告 / 提醒
    static let warning = Color(hex: "#FFBF00")
    /// 成功 / 100% 完成
    static let success = Color(hex: "#09CC9B")
    /// 提示 / 信息
    static let info = Color(hex: "#2BB7FD")
}

// MARK: - 项目可选主题色

extension ViabarColor {
    /// 新建项目时可选的背景色
    static let palette: [(hex: String, name: LocalizedStringKey)] = [
        ("#009AFF", "蓝"),
        ("#f94144", "红"),
        ("#FF6299", "粉"),
        ("#f9844a", "橙"),
        ("#f8961e", "橙"),
        ("#f9c74f", "黄"),
        ("#90be6d", "绿"),
        ("#43aa8b", "绿"),
        ("#577590", "紫"),
        ("#7678ed", "紫"),
    ]
}

// MARK: - Project SF Symbol Candidates

let commonSymbols: [String] = [
    "bookmark.fill", "circle.dashed", "circle.fill", "checkmark.circle.fill", "xmark.circle.fill",
    "star.fill", "star.leadinghalf.filled", "heart.fill", "heart.circle.fill",
    "flame.fill", "bolt.fill", "bolt.circle.fill", "shield.fill",
    "flag.fill", "flag.checkered", "tag.fill", "pin.fill",
    "mappin.circle.fill", "location.fill", "paperclip",
    "doc.fill", "doc.text.fill", "folder.fill", "tray.full.fill",
    "archivebox.fill", "list.bullet.clipboard.fill", "chart.bar.fill",
    "chart.pie.fill", "tablecells.fill",
    "hammer.fill", "wrench.fill", "gearshape.fill", "gearshape.2.fill",
    "pencil.tip", "pencil.circle.fill", "keyboard.fill", "printer.fill",
    "scanner.fill", "display", "laptopcomputer", "keyboard",
    "cube.fill", "puzzlepiece.fill", "lightbulb.fill", "sparkles",
    "crown.fill", "rosette", "medal.fill", "graduationcap.fill",
    "building.columns.fill", "building.2.fill", "house.fill", "storefront.fill",
    "leaf.fill", "camera.macro", "tree.fill", "sun.max.fill",
    "moon.fill", "moon.stars.fill", "cloud.fill", "cloud.rain.fill",
    "snowflake", "wind", "tornado", "drop.fill",
    "car.fill", "bus.fill", "tram.fill", "bicycle",
    "airplane", "ferry.fill", "fuelpump.fill", "figure.walk",
    "message.fill", "bubble.left.fill", "bubble.right.fill", "envelope.fill",
    "phone.fill", "phone.down.fill", "video.fill", "mic.fill",
    "at.circle.fill", "link.circle.fill", "person.fill", "person.2.fill",
    "person.3.fill", "figure.mind.and.body",
    "play.fill", "pause.fill", "stop.fill", "backward.fill",
    "forward.fill", "shuffle", "repeat", "music.note",
    "music.mic", "guitars.fill", "tv.fill", "film.fill",
    "gamecontroller.fill", "paintpalette.fill", "camera.fill", "photo.fill",
    "cart.fill", "basket.fill", "creditcard.fill", "dollarsign.circle.fill",
    "yensign.circle.fill", "eurosign.circle.fill", "sterlingsign.circle.fill",
    "gift.fill", "bag.fill",
    "heart.text.square.fill", "cross.case.fill", "pills.fill", "bandage.fill",
    "stethoscope", "syringe.fill", "ear.fill", "eye.fill", "brain.head.profile",
    "clock.fill", "alarm.fill", "stopwatch", "timer",
    "calendar", "calendar.badge.clock", "hourglass.bottomhalf.filled",
    "globe", "network", "wifi", "antenna.radiowaves.left.and.right",
    "bell.fill", "ticket.fill", "key.fill",
    "lock.fill", "lock.open.fill", "hand.thumbsup.fill", "hand.thumbsdown.fill",
    "eye.slash.fill", "hand.raised.fill", "exclamationmark.triangle.fill",
    "info.circle.fill", "questionmark.circle.fill", "plus.circle.fill",
    "minus.circle.fill", "arrow.up.circle.fill", "arrow.down.circle.fill",
]

// MARK: - Hex String Convenience

extension ViabarColor {
    static let primaryHex = "#0085ff"
    static let successHex = "#09CC9B"
    static let dangerHex = "#FF4B41"
    static let warningHex = "#FFBF00"
    static let infoHex = "#2BB7FD"
}
