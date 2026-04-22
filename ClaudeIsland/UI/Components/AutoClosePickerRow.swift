//
//  AutoClosePickerRow.swift
//  ClaudeIsland
//
//  Compact expandable menu row: picks how long a notification-opened
//  panel stays visible before auto-collapsing. Values come from
//  AppSettings.notificationAutoCloseOptions (0, 3, 5, 10, 30). 0 is the
//  "Off" sentinel — panel sticks until user dismisses.
//

import SwiftUI

struct AutoClosePickerRow: View {
    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var selected: Int = AppSettings.notificationAutoCloseSeconds

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 12))
                        .foregroundColor(textColor)
                        .frame(width: 16)

                    Text("Auto-close")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(textColor)

                    Spacer()

                    Text(displayValue(selected))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(AppSettings.notificationAutoCloseOptions, id: \.self) { seconds in
                        OptionRow(
                            label: displayValue(seconds),
                            isSelected: selected == seconds
                        ) {
                            selected = seconds
                            AppSettings.notificationAutoCloseSeconds = seconds
                        }
                    }
                }
                .padding(.leading, 28)
                .padding(.top, 4)
            }
        }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }

    private func displayValue(_ seconds: Int) -> String {
        seconds == 0 ? "Off" : "\(seconds)s"
    }
}

private struct OptionRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? TerminalColors.green : Color.white.opacity(0.2))
                    .frame(width: 6, height: 6)

                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.7))

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(TerminalColors.green)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
