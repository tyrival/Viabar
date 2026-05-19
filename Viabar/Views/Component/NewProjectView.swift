import SwiftUI

// MARK: - NewProjectView

struct NewProjectView: View {
    @Environment(ServiceContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var projectName: String = ""
    @State private var selectedColorHex: String = ViabarColor.palette[0].hex
    @State private var selectedSymbol: String = commonSymbols[0]

    private var projectService: ProjectService? {
        container.projectService
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("新建项目").font(.title3).bold()
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(.borderless)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 20) {
                nameField
                templateSection
                iconAndColorRow
                symbolGridScroll
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("创建") { createProject() }
                    .buttonStyle(.borderedProminent)
                    .disabled(projectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 520, height: 620)
    }

    // MARK: - Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("项目名称").font(.headline)
            TextField("输入项目名称…", text: $projectName)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Template (placeholder)

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("模板").font(.headline)
            HStack {
                Image(systemName: "square.on.square")
                    .foregroundStyle(.tertiary)
                Text("暂无可选模板，后续版本将支持")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Icon & Color Row

    private var iconAndColorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("图标 & 主题色").font(.headline)
            HStack(spacing: 16) {
                // 当前选中图标
                Image(systemName: selectedSymbol)
                    .font(.title)
                    .frame(width: 40, height: 40)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                // 颜色圆形
                HStack(spacing: 10) {
                    ForEach(ViabarColor.palette, id: \.hex) { item in
                        ColorCircle(
                            hex: item.hex,
                            name: item.name,
                            isSelected: selectedColorHex == item.hex,
                            onSelect: { selectedColorHex = item.hex }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Symbol Grid Scroll

    private var symbolGridScroll: some View {
        ScrollView {
            symbolGridContent
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var symbolGridContent: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 10)

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(commonSymbols, id: \.self) { symbol in
                Button {
                    selectedSymbol = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.body)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .background(
                    selectedSymbol == symbol
                        ? Color.blue.opacity(0.15)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            selectedSymbol == symbol ? Color.blue : Color.clear,
                            lineWidth: 1.5
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(4)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Create

    private func createProject() {
        let name = projectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let svc = projectService else { return }
        let project = svc.createProject(title: name)
        project.accentColor = selectedColorHex
        project.sfSymbolName = selectedSymbol
        svc.updateProject(project)
        dismiss()
    }
}

// MARK: - ColorCircle

struct ColorCircle: View {
    let hex: String
    let name: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 28, height: 28)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2).bold()
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .help(name)
    }
}

// MARK: - SF Symbol List (100)

private let commonSymbols: [String] = [
    // 通用
    "circle.dashed", "circle.fill", "checkmark.circle.fill", "xmark.circle.fill",
    "star.fill", "star.leadinghalf.filled", "heart.fill", "heart.circle.fill",
    "flame.fill", "bolt.fill", "bolt.circle.fill", "shield.fill",
    // 标记
    "flag.fill", "flag.checkered", "bookmark.fill", "tag.fill", "pin.fill",
    "mappin.circle.fill", "location.fill", "paperclip",
    // 文件/文档
    "doc.fill", "doc.text.fill", "folder.fill", "tray.full.fill",
    "archivebox.fill", "list.bullet.clipboard.fill", "chart.bar.fill",
    "chart.pie.fill", "tablecells.fill",
    // 工具/开发
    "hammer.fill", "wrench.fill", "gearshape.fill", "gearshape.2.fill",
    "pencil.tip", "pencil.circle.fill", "keyboard.fill", "printer.fill",
    "scanner.fill", "display", "laptopcomputer", "keyboard",
    // 物体
    "cube.fill", "puzzlepiece.fill", "lightbulb.fill", "sparkles",
    "crown.fill", "rosette", "medal.fill", "graduationcap.fill",
    "building.columns.fill", "building.2.fill", "house.fill", "storefront.fill",
    // 自然/天气
    "leaf.fill", "camera.macro", "tree.fill", "sun.max.fill",
    "moon.fill", "moon.stars.fill", "cloud.fill", "cloud.rain.fill",
    "snowflake", "wind", "tornado", "drop.fill",
    // 交通/出行
    "car.fill", "bus.fill", "tram.fill", "bicycle",
    "airplane", "ferry.fill", "fuelpump.fill", "figure.walk",
    // 沟通/社交
    "message.fill", "bubble.left.fill", "bubble.right.fill", "envelope.fill",
    "phone.fill", "phone.down.fill", "video.fill", "mic.fill",
    "at.circle.fill", "link.circle.fill", "person.fill", "person.2.fill",
    "person.3.fill", "figure.mind.and.body",
    // 媒体/娱乐
    "play.fill", "pause.fill", "stop.fill", "backward.fill",
    "forward.fill", "shuffle", "repeat", "music.note",
    "music.mic", "guitars.fill", "tv.fill", "film.fill",
    "gamecontroller.fill", "paintpalette.fill", "camera.fill", "photo.fill",
    // 购物/金融
    "cart.fill", "basket.fill", "creditcard.fill", "dollarsign.circle.fill",
    "yensign.circle.fill", "eurosign.circle.fill", "sterlingsign.circle.fill",
    "gift.fill", "bag.fill",
    // 健康/医疗
    "heart.text.square.fill", "cross.case.fill", "pills.fill", "bandage.fill",
    "stethoscope", "syringe.fill", "ear.fill", "eye.fill", "brain.head.profile",
    // 时间/日历
    "clock.fill", "alarm.fill", "stopwatch", "timer",
    "calendar", "calendar.badge.clock", "hourglass.bottomhalf.filled",
    // 其他常用
    "globe", "network", "wifi", "antenna.radiowaves.left.and.right",
    "bell.fill", "ticket.fill", "key.fill",
    "lock.fill", "lock.open.fill", "hand.thumbsup.fill", "hand.thumbsdown.fill",
    "eye.slash.fill", "hand.raised.fill", "exclamationmark.triangle.fill",
    "info.circle.fill", "questionmark.circle.fill", "plus.circle.fill",
    "minus.circle.fill", "arrow.up.circle.fill", "arrow.down.circle.fill",
]

// MARK: - Preview

#Preview {
    NewProjectView()
        .environment(ServiceContainer())
}
