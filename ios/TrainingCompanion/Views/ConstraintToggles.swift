import SwiftUI

/// The equipment and injury toggles a program is built for (design-system
/// §6.38). The builder, the Program settings sheet and the preview's Adjust
/// each wrote the same two `ForEach` loops; one component keeps them one.
/// Profile ▸ Equipment is the profile's own screen and keeps its tiles.
struct EquipmentToggleSection: View {
    @Binding var selection: [String]
    var title = "Equipment"

    var body: some View {
        Section(title) {
            ForEach(EquipmentItem.all) { item in
                Toggle(item.label, isOn: Binding(
                    get: { selection.contains(item.id) },
                    set: { on in
                        if on { if !selection.contains(item.id) { selection.append(item.id) } }
                        else { selection.removeAll { $0 == item.id } }
                    }
                ))
            }
        }
    }
}

struct InjuryToggleSection: View {
    @Binding var selection: [String]
    @EnvironmentObject var appState: AppState
    var title = "Active Injuries"

    var body: some View {
        Section(title) {
            ForEach(appState.injuryFlagDefs) { flag in
                Toggle(flag.name, isOn: Binding(
                    get: { selection.contains(flag.id) },
                    set: { on in
                        if on { if !selection.contains(flag.id) { selection.append(flag.id) } }
                        else { selection.removeAll { $0 == flag.id } }
                    }
                ))
            }
        }
    }
}
