// MachineSelector.swift
// SwiftUI machine picker — shown on first launch and from the Machine menu.

import SwiftUI

struct MachineSelectorView: View {
    @Bindable var model: VICEPreferenceModel
    var onSelect: (MachineModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("c=foundation")
                    .font(.system(.title, design: .monospaced, weight: .bold))
                Spacer()
            }
            .padding()

            Divider()

            // Machine list
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(MachineModel.allCases) { machine in
                        MachineRow(
                            machine: machine,
                            isSelected: model.machineModel == machine
                        )
                        .onTapGesture {
                            model.machineModel = machine
                            model.save()
                            onSelect(machine)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") { onSelect(model.machineModel) }
                    .keyboardShortcut(.cancelAction)
                Button("Select") { onSelect(model.machineModel) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 340)
    }
}

struct MachineRow: View {
    let machine: MachineModel
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .blue : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(machine.displayName)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text(machine.shortName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
    }
}
