# Overview Card Opaque Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `OverviewProjectCard` into two layers — project icon/title on liquid glass, all other content on an opaque card overlaid near the bottom.

**Architecture:** Single-file change in `ContentView.swift`. Restructure the `VStack` inside `OverviewProjectCard.body` to wrap milestone/subtask/reminder/progress content in a `VStack` with `ViabarColor.mainPanelBackground` fill, inset from the glass edges.

**Tech Stack:** SwiftUI, AppKit (NSVisualEffectView)

---

### Task 1: Restructure OverviewProjectCard.body to add opaque card layer

**Files:**
- Modify: `Viabar/ContentView.swift:1068-1225` (`OverviewProjectCard.body`)

- [ ] **Step 1: Replace the body computed property**

The current body is a single `VStack` containing all content. Replace with a layered structure:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 0) {
        // Header: project icon + title + favorite (stays on liquid glass)
        HStack(spacing: 8) {
            Image(systemName: project.sfSymbolName)
                .font(.title3)
                .foregroundStyle(accentColor)
            Text(project.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(colorScheme == .dark ? ViabarColor.primaryPale : ViabarColor.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if project.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(ViabarColor.warning)
            }
        }

        // Opaque card: task/subtask, reminder, progress
        VStack(alignment: .leading, spacing: 0) {
            if let milestone = topMilestone {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.gray.opacity(0.55))
                        .frame(width: 16, alignment: .center)
                    Text(milestone.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(milestoneTitleColor(milestone.markerColor))
                        .lineLimit(1)
                }
                .padding(.leading, taskRowIndent)

                if let subtask = milestone.subtasks.first(where: { !$0.isCompleted }) {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.gray.opacity(0.55))
                            .frame(width: 16, alignment: .center)
                        Text(subtask.title)
                            .font(.system(size: 12))
                            .foregroundStyle(subtaskTitleColor(subtask.markerColor))
                            .lineLimit(1)
                    }
                    .padding(.leading, taskRowIndent + subtaskExtraIndent)
                    .padding(.top, 10)
                }
            }

            Spacer(minLength: 0)

            HStack(alignment: .bottom) {
                if let reminderDate, displayedMilestoneReminder != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "alarm.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(reminderForegroundColor)
                        Text(AppDateFormatter.string(from: reminderDate, pattern: savedDateFormat))
                            .font(.system(size: 11))
                            .foregroundStyle(reminderForegroundColor)
                    }
                    .padding(.leading, 8)
                    .offset(y: -5)
                }

                Spacer(minLength: 8)

                progressRing
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ViabarColor.mainPanelBackground)
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .padding(.top, 8)
    }
    .padding(.top, 12)
    .frame(height: 150)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    stops: colorScheme == .dark
                        ? [
                            .init(color: .clear, location: 0.0),
                            .init(color: Color.white.opacity(0.24), location: 0.15),
                            .init(color: Color.white.opacity(0.24), location: 0.85),
                            .init(color: .clear, location: 1.0)
                          ]
                        : [
                            .init(color: .clear, location: 0.0),
                            .init(color: Color.black.opacity(0.10), location: 0.15),
                            .init(color: Color.black.opacity(0.10), location: 0.85),
                            .init(color: .clear, location: 1.0)
                          ],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                ),
                lineWidth: colorScheme == .dark ? 0.8 : 0.7
            )
    )
    .background {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(colorScheme == .dark ? Color.black.opacity(0.01) : Color.white)
                .shadow(
                    color: colorScheme == .dark
                        ? Color.black.opacity(isHovering ? 0.65 : 0.40)
                        : Color(hex: "#0F172A").opacity(isHovering ? 0.10 : 0.05),
                    radius: isHovering ? 15 : 6,
                    x: 0,
                    y: isHovering ? 7 : 2.5
                )

            LightGlassView()
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.05 : 0.02))
                    .allowsHitTesting(false)
            }
        }
    }
    .offset(y: isHovering ? -2 : 0)
    .animation(.easeOut(duration: hoverAnimationDuration), value: isHovering)
    .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    .onHover { isHovering = $0 }
    .onTapGesture(perform: onSelect)
    .contextMenu {
        Button {
            onEdit()
        } label: {
            Label("编辑", systemImage: "pencil")
        }
        Button {
            onArchive()
        } label: {
            Label("归档", systemImage: "archivebox")
        }
        Button {
            projectService?.toggleFavorite(project)
        } label: {
            if project.isFavorite {
                Label("取消收藏", systemImage: "star.slash")
            } else {
                Label("收藏", systemImage: "star")
            }
        }
        Divider()
        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("删除", systemImage: "trash")
        }
    }
}
```

**Key changes from original:**
1. Outer `VStack` padding reduced to just `.padding(.top, 12)`
2. Header row stays outside opaque card
3. All content below header wrapped in inner `VStack` with `.background(RoundedRectangle(...).fill(ViabarColor.mainPanelBackground))`
4. Opaque card has its own internal padding and is inset via `.padding(.horizontal, 10)`, `.padding(.bottom, 10)`, `.padding(.top, 8)`
5. Glass border overlay and glass background remain on the outer card

- [ ] **Step 2: Build and verify compilation**

```bash
cd /Users/tyrival/workspace/Viabar && xcodebuild -project Viabar.xcodeproj -scheme Viabar -configuration Debug build 2>&1 | tail -20
```

- [ ] **Step 3: Run the app and visually verify**

Launch Viabar and check:
- Cards show two-layer effect (glass + opaque)
- Opaque card uses page background color
- Dark/light mode switching works correctly
- Hover effects still work
- Context menu still works
- Card height looks balanced
