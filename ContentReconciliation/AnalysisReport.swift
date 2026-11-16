import Foundation

/// Одна строка отчёта: данные по одному населённому пункту.
struct SettlementReport: Identifiable, Hashable {
    var id: String { settlement }
    let settlement: String
    /// Все записи в населённом пункте.
    let total: Int
    /// Записи, где blocked не равно "1".
    let unblocked: Int
    /// Записи с непустым списком подписок.
    let subscribers: Int

    /// Процент абонентов с подпиской от количества не заблокированных.
    var percent: Double {
        unblocked == 0 ? 0 : Double(subscribers) / Double(unblocked) * 100
    }
}

enum AnalysisReport {

    /// Населённый пункт — часть адреса до первой запятой. Если адреса нет, «не указан».
    static func settlement(from address: String?) -> String {
        let part = (address ?? "")
            .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        return part.isEmpty ? "не указан" : part
    }

    /// Группирует записи по населённому пункту и считает показатели.
    static func build(_ records: [UserRecord]) -> [SettlementReport] {
        let groups = Dictionary(grouping: records) { settlement(from: $0.address) }

        return groups
            .map { name, items in
                SettlementReport(
                    settlement: name,
                    total: items.count,
                    unblocked: items.filter { $0.blocked != "1" }.count,
                    subscribers: items.filter { !($0.subscriptions ?? []).isEmpty }.count
                )
            }
            .sorted { $0.settlement.localizedStandardCompare($1.settlement) == .orderedAscending }
    }
}
