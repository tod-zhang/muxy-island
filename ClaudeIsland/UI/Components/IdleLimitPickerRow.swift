//
//  IdleLimitPickerRow.swift
//  ClaudeIsland
//
//  Settings row for "how many idle/ready sessions to keep in the list".
//  Active sessions (processing / waitingForApproval / compacting) are
//  never trimmed so this only affects the sleepy tail of the list.
//

import SwiftUI

struct IdleLimitPickerRow: View {
    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var selected: Int = AppSettings.idleSessionLimit

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 12))
                        .foregroundColor(textColor)
                        .frame(width: 16)

                    Text("Idle sessions shown")
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
                    ForEach(AppSettings.idleSessionLimitOptions, id: \.self) { n in
                        OptionRow(
                            label: displayValue(n),
                            isSelected: selected == n
                        ) {
                            selected = n
                            AppSettings.idleSessionLimit = n
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

    private func displayValue(_ n: Int) -> String {
        n == 0 ? "All" : "\(n)"
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
