import Foundation

/// Оператор подписки. Определяется по названию подписки.
enum Operator: String, CaseIterable {
    case tv24 = "24TV"
    case moovi = "Moovi"
    case smotreshka = "Smotreshka"

    /// 24TV — если в названии есть «24TV»; Moovi — «moovi» или «муки»;
    /// всё остальное — Smotreshka.
    static func of(subscriptionName name: String) -> Operator {
        let lower = name.lowercased()
        if lower.contains("24tv") { return .tv24 }
        if lower.contains("moovi") || lower.contains("муки") { return .moovi }
        return .smotreshka
    }
}

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
    /// Записи, у которых есть подписка данного оператора.
    /// У одного абонента может быть несколько операторов — он учитывается в каждом.
    let byOperator: [Operator: Int]

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

    /// Операторы, у которых есть хотя бы одна подписка у записи.
    static func operators(of record: UserRecord) -> Set<Operator> {
        Set((record.subscriptions ?? []).map { Operator.of(subscriptionName: $0.name) })
    }

    /// Группирует записи по населённому пункту и считает показатели.
    static func build(_ records: [UserRecord]) -> [SettlementReport] {
        let groups = Dictionary(grouping: records) { settlement(from: $0.address) }

        return groups
            .map { name, items in
                var byOperator: [Operator: Int] = [:]
                for op in Operator.allCases {
                    byOperator[op] = items.filter { operators(of: $0).contains(op) }.count
                }
                return SettlementReport(
                    settlement: name,
                    total: items.count,
                    unblocked: items.filter { $0.blocked != "1" }.count,
                    subscribers: items.filter { !($0.subscriptions ?? []).isEmpty }.count,
                    byOperator: byOperator
                )
            }
            .sorted { $0.settlement.localizedStandardCompare($1.settlement) == .orderedAscending }
    }

    /// CSV с разделителем «;». Последняя строка «Итого».
    /// «Итого» по абонентам считается по записям, а не сложением строк:
    /// у одного абонента может быть несколько операторов.
    static func csv(_ rows: [SettlementReport], records: [UserRecord]) -> String {
        var header = ["Населенный пункт", "Количество", "Не заблокированы", "С подпиской"]
        header += Operator.allCases.map { $0.rawValue }
        header += Operator.allCases.map { "% \($0.rawValue)" }
        header += ["Процент с подпиской"]

        var lines = [header.joined(separator: ";")]

        for row in rows {
            var cells = [
                escape(row.settlement),
                "\(row.total)",
                "\(row.unblocked)",
                "\(row.subscribers)"
            ]
            cells += Operator.allCases.map { "\(row.byOperator[$0] ?? 0)" }
            cells += Operator.allCases.map { percent(row.byOperator[$0] ?? 0, of: row.unblocked) }
            cells += [String(format: "%.2f", row.percent)]
            lines.append(cells.joined(separator: ";"))
        }

        // Итого: по всем записям, без двойного счёта
        let total = rows.reduce(0) { $0 + $1.total }
        let unblocked = rows.reduce(0) { $0 + $1.unblocked }
        let subscribers = rows.reduce(0) { $0 + $1.subscribers }
        let totalByOperator: [Operator: Int] = Dictionary(uniqueKeysWithValues: Operator.allCases.map { op in
            (op, records.filter { operators(of: $0).contains(op) }.count)
        })
        let totalPercent = unblocked == 0 ? 0 : Double(subscribers) / Double(unblocked) * 100

        var totalCells = ["Итого", "\(total)", "\(unblocked)", "\(subscribers)"]
        totalCells += Operator.allCases.map { "\(totalByOperator[$0] ?? 0)" }
        totalCells += Operator.allCases.map { percent(totalByOperator[$0] ?? 0, of: unblocked) }
        totalCells += [String(format: "%.2f", totalPercent)]
        lines.append(totalCells.joined(separator: ";"))

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Процент части от целого с двумя знаками; при нуле в знаменателе — 0.00.
    private static func percent(_ part: Int, of whole: Int) -> String {
        whole == 0 ? "0.00" : String(format: "%.2f", Double(part) / Double(whole) * 100)
    }

    private static func escape(_ field: String) -> String {
        let needsQuotes = field.contains(";") || field.contains("\"") || field.contains("\n") || field.contains("\r")
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
