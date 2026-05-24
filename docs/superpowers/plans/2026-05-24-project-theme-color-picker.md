# Project Theme Color Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the selectable project theme palette with the approved nine colors and add a native custom color picker that persists and recalls custom hex values.

**Architecture:** Keep `Project.accentColor` and `NewProjectView.selectedColorHex` as the single persistence and selection representation. Update the shared palette data, add a small AppKit-backed `Color` serialization helper for `#RRGGBB`, and compose a final custom picker control beside the existing preset circles.

**Tech Stack:** SwiftUI, AppKit `NSColor`, SwiftData model already storing hex strings.

---

## Constraints

- The revised preset display order starts with `#009AFF`, followed by `#00AB74`, `#00CBCF`, `#FFCB24`, `#00CD69`, `#FF4846`, `#FFBF00`, `#FF6299`, and `#642FFF`.
- The user explicitly approved static verification only and instructed that the app must not be compiled unless separately requested. Running XCTest or Swift Testing would build the app target, so this plan does not run automated tests.
- No model migration or persistence changes are needed because custom colors remain normalized hex strings in `Project.accentColor`.

## File Structure

- Modify `Viabar/System/ViabarColor.swift`: replace the palette values and names in display order.
- Modify `Viabar/Views/Component/Color+Hex.swift`: convert a selected SwiftUI `Color` to a normalized `#RRGGBB` string on macOS.
- Modify `Viabar/Views/Component/NewProjectView.swift`: add custom picker state bridging and render a final circular custom color picker with the correct selected state.

### Task 1: Replace The Project Theme Presets

**Files:**
- Modify: `Viabar/System/ViabarColor.swift`

- [x] **Step 1: Replace the preset palette data**

```swift
static let palette: [(hex: String, name: String)] = [
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
```

- [x] **Step 2: Inspect the palette order statically**

Run:

```bash
sed -n '36,46p' Viabar/System/ViabarColor.swift
```

Expected: nine matches in exactly the revised order, with `#009AFF` first.

### Task 2: Insert Newly Created Projects At The Top

**Files:**
- Modify: `Viabar/Services/ProjectService.swift`

- [x] **Step 1: Normalize active order around project creation**

Replace the creation implementation with a placement-aware insert that retains
the explicit `orderIndex` parameter while making the default value insert at the
top:

```swift
func createProject(title: String, hideCompleted: Bool = true, orderIndex: Int = 0) -> Project {
    let activeProjects = allActiveProjects()
    let insertionIndex = min(max(orderIndex, 0), activeProjects.count)

    for (index, existingProject) in activeProjects.enumerated() {
        existingProject.orderIndex = index < insertionIndex ? index : index + 1
    }

    let project = Project(title: title, hideCompleted: hideCompleted, orderIndex: insertionIndex)
    modelContext.insert(project)
    save()
    return project
}
```

- [x] **Step 2: Inspect creation and restoration behavior statically**

Run:

```bash
sed -n '110,128p' Viabar/Services/ProjectService.swift
sed -n '246,258p' Viabar/Services/ProjectService.swift
```

Expected: creation shifts existing active projects around index `0` by default,
while `unarchiveProject` still assigns `allActiveProjects().count`.

### Task 3: Serialize System Picker Values As Hex

**Files:**
- Modify: `Viabar/Views/Component/Color+Hex.swift`

- [x] **Step 1: Add AppKit support and a normalized output property**

```swift
import AppKit
import SwiftUI

extension Color {
    var hexRGB: String? {
        guard let rgbColor = NSColor(self).usingColorSpace(.sRGB) else { return nil }

        return String(
            format: "#%02X%02X%02X",
            Int((rgbColor.redComponent * 255).rounded()),
            Int((rgbColor.greenComponent * 255).rounded()),
            Int((rgbColor.blueComponent * 255).rounded())
        )
    }
}
```

Keep the existing `init(hex:)` and `overlayTextColor` behavior unchanged.

- [x] **Step 2: Inspect the conversion contract statically**

Run:

```bash
rg -n 'import AppKit|var hexRGB|usingColorSpace\\(\\.sRGB\\)|#%02X%02X%02X' Viabar/Views/Component/Color+Hex.swift
```

Expected: each required conversion element is present once.

### Task 4: Add The Native Custom Color Control

**Files:**
- Modify: `Viabar/Views/Component/NewProjectView.swift`

- [x] **Step 1: Add computed selection helpers**

Add helpers beside `projectService`:

```swift
private var isUsingCustomColor: Bool {
    !ViabarColor.palette.contains { $0.hex.caseInsensitiveCompare(selectedColorHex) == .orderedSame }
}

private var customColorBinding: Binding<Color> {
    Binding(
        get: { Color(hex: selectedColorHex) },
        set: { newColor in
            if let hex = newColor.hexRGB {
                selectedColorHex = hex
            }
        }
    )
}
```

- [x] **Step 2: Keep preset selection comparisons case-insensitive**

Update the preset `ColorCircle` invocation:

```swift
isSelected: selectedColorHex.caseInsensitiveCompare(item.hex) == .orderedSame,
```

- [x] **Step 3: Append a native color picker control after the presets**

Add after the `ForEach`:

```swift
CustomColorCircle(
    color: customColorBinding,
    isSelected: isUsingCustomColor
)
```

Add the small focused view below `ColorCircle`. Its native picker remains the
interactive control, while the overlay supplies the circular appearance:

```swift
struct CustomColorCircle: View {
    @Binding var color: Color
    let isSelected: Bool

    var body: some View {
        ZStack {
            ColorPicker("自定义颜色", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .opacity(0.01)

            Circle()
                .fill(
                    isSelected
                        ? AnyShapeStyle(color)
                        : AnyShapeStyle(
                            AngularGradient(
                                colors: [.red, .yellow, .green, .blue, .purple, .red],
                                center: .center
                            )
                        )
                )
                .allowsHitTesting(false)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption2).bold()
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 28, height: 28)
        .contentShape(Circle())
        .help("自定义颜色")
    }
}
```

- [x] **Step 4: Inspect all UI state paths statically**

Run:

```bash
rg -n 'isUsingCustomColor|customColorBinding|CustomColorCircle|ColorPicker|caseInsensitiveCompare|hexRGB' Viabar/Views/Component/NewProjectView.swift
```

Expected: preset selection, custom selection, picker binding, and hex update are all connected.

### Task 5: Final Non-Build Verification

**Files:**
- Verify: `Viabar/System/ViabarColor.swift`
- Verify: `Viabar/Services/ProjectService.swift`
- Verify: `Viabar/Views/Component/Color+Hex.swift`
- Verify: `Viabar/Views/Component/NewProjectView.swift`

- [x] **Step 1: Check for whitespace and patch-format errors**

Run:

```bash
git diff --check
```

Expected: exit code `0` and no output.

- [x] **Step 2: Review the changed code without compiling**

Run:

```bash
git diff -- Viabar/System/ViabarColor.swift Viabar/Services/ProjectService.swift Viabar/Views/Component/Color+Hex.swift Viabar/Views/Component/NewProjectView.swift
```

Expected: changes are limited to the approved palette, project insertion order, custom picker UI, and hex conversion helper.

- [x] **Step 3: Report the verification boundary**

State explicitly that static verification ran successfully and that build/test execution was intentionally not performed because the user instructed not to compile.
