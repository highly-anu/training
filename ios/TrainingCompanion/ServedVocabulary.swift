import Foundation

/// What the athlete's own methods add to the vocabulary (a package's
/// `vocabulary.yaml`, docs/roadmap.md 21.5): modalities and equipment the
/// commons lack, which no build has compiled in. The phone reads them from
/// the same routes the web does and keeps the modalities where the widgets
/// read too (`ClientVocab.remember`); the equipment is offered by the pickers
/// under its own heading.
enum ServedVocabulary {
    /// The pickers' heading for equipment a method brings.
    static let equipmentGroup = "From your methods"

    /// `GET /api/modalities` → id → display, for each modality a package
    /// brings (one of the commons' is already in `ClientVocab.modalities`).
    static func modalityDisplays(from data: Data) -> [String: [String: Any]] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
        var out: [String: [String: Any]] = [:]
        for modality in list {
            guard let id = modality["id"] as? String, ClientVocab.modalities[id] == nil,
                  let display = modality["display"] as? [String: Any] else { continue }
            out[id] = display
        }
        return out
    }

    /// `GET /api/equipment` → the items a package brings (those with a
    /// `package`), each once, in the order served.
    static func equipment(from data: Data) -> [EquipmentItem] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let known = Set(EquipmentItem.all.map(\.id))
        var seen = Set<String>()
        return list.compactMap { item in
            guard let id = item["id"] as? String, item["package"] is String, !known.contains(id),
                  seen.insert(id).inserted else { return nil }
            return EquipmentItem(id: id, label: (item["label"] as? String) ?? id, group: equipmentGroup)
        }
    }
}
