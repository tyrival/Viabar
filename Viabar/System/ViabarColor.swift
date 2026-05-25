import SwiftUI

/// 品牌色板 —— 统一维护，全局引用
enum ViabarColor {
    // MARK: 主色调

    /// 主色 · 深蓝（默认项目进度色）
    static let primary = Color(hex: "#0161F7")
    /// 深紫（备用主色 / 强调）
    static let primaryDark = Color(hex: "#40285F")
    /// 中蓝（次级主色）
    static let primaryMedium = Color(hex: "#4189FF")
    /// 浅蓝（辅助色）
    static let primaryLight = Color(hex: "#4CC1FF")
    /// 极浅蓝（背景 / 卡片底色）
    static let primaryPale = Color(hex: "#D5F7FF")
    /// 近白蓝（大面积背景）
    static let primaryGhost = Color(hex: "#F3FDFF")

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
        ("#00AB74", "绿"),
        ("#00CBCF", "蓝"),
        ("#FFCB24", "黄"),
        ("#00CD69", "绿"),
        ("#FF4846", "红"),
        ("#FFBF00", "橙"),
        ("#FF6299", "粉"),
        ("#642FFF", "紫"),
    ]
}

// MARK: - Hex String Convenience

extension ViabarColor {
    static let primaryHex = "#0161F7"
    static let successHex = "#09CC9B"
    static let dangerHex = "#FF4B41"
    static let warningHex = "#FFBF00"
    static let infoHex = "#2BB7FD"
}
