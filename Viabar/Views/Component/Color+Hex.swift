import SwiftUI

extension Color {
    /// 从十六进制字符串创建 Color。支持 `"#FF6B6B"` / `"FF6B6B"` / `"#FFF"` 格式。
    init(hex: String) {
        let trimmed = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        let scanner = Scanner(string: trimmed)
        var rgb: UInt64 = 0

        guard scanner.scanHexInt64(&rgb) else {
            self = .blue
            return
        }

        let r, g, b: Double
        if trimmed.count == 6 {
            r = Double((rgb >> 16) & 0xFF) / 255
            g = Double((rgb >> 8) & 0xFF) / 255
            b = Double(rgb & 0xFF) / 255
        } else if trimmed.count == 3 {
            r = Double((rgb >> 8) & 0xF) / 15
            g = Double((rgb >> 4) & 0xF) / 15
            b = Double(rgb & 0xF) / 15
        } else {
            self = .blue
            return
        }

        self.init(red: r, green: g, blue: b)
    }

    /// 返回适合叠加在自身之上的文本色（粗略判断明暗）
    var overlayTextColor: Color {
        // 简单起见统一用白色 + 阴影，保证可读性
        .white
    }
}
