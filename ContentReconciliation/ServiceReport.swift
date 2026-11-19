import Foundation

/// Отчёт по сервису за квартал: строка на населённый пункт.
enum ServiceReport {

    struct Row {
        let settlement: String
        /// Абоненты за минусом удалённых и заблокированных.
        let subscribers: Int
        /// Из них с подпиской.
        let withSubscriptions: Int
        /// Заявки, созданные в квартале.
        let requests: Int

        var subscriptionPercent: Double { percent(withSubscriptions, of: subscribers) }
        var requestPercent: Double { percent(requests, of: subscribers) }

        private func percent(_ part: Int, of whole: Int) -> Double {
            whole == 0 ? 0 : Double(part) / Double(whole) * 100
        }
    }

    /// Третий квартал 2026: с 01.07.2026 по 30.09.2026 включительно.
    static let quarterStart = DateComponents(calendar: .current, timeZone: .current, year: 2026, month: 7, day: 1).date!
    static let quarterEnd = DateComponents(calendar: .current, timeZone: .current, year: 2026, month: 10, day: 1).date!

    /// Дата создания заявки: «dd.MM.yyyy HH:mm» (как в выгрузке).
    static func createdDate(_ text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "dd.MM.yyyy HH:mm"
        return f.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Типы заявок, которые не входят в отчёт.
    static let excludedTypes: Set<String> = ["си подключение"]

    static func isExcludedType(_ type: String) -> Bool {
        let normalized = type
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
        return excludedTypes.contains(normalized)
    }

    static func inQuarter(_ request: ServiceRequest) -> Bool {
        guard let date = createdDate(request.createdAt) else { return false }
        return date >= quarterStart && date < quarterEnd && !isExcludedType(request.type)
    }

    /// Абонент учитывается, если он не удалён и не заблокирован.
    static func isCounted(_ record: UserRecord) -> Bool {
        AnalysisReport.isActive(record) && record.blocked != "1"
    }

    /// Ключ группировки: регистр не важен, латинская «c» — это кириллическая «с»,
    /// пробелы убираются, а пробел после сокращения типа («с. Визинга» и «с.Визинга») не учитывается.
    /// Одинаковые по ключу названия считаются одним населённым пунктом.
    static func key(_ settlement: String) -> String {
        var fixed = settlement
            .replacingOccurrences(of: "c", with: "с")
            .replacingOccurrences(of: "C", with: "с")
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        // «город Черемхово (МС)» — это то же самое, что «г. Черемхово»
        fixed = fixed.replacingOccurrences(of: " (мс)", with: "")
        if fixed.hasPrefix("город ") {
            fixed = "г." + fixed.dropFirst("город".count)
        }
        return fixed.replacingOccurrences(of: ". ", with: ".")
    }

    static func build(records: [UserRecord], requests: [ServiceRequest]) -> [Row] {
        let counted = records.filter { isCounted($0) }
        let quarterRequests = requests.filter { inQuarter($0) }

        // Группировка — по ключу; название в строке — самое частое написание в данных
        var spellings: [String: [String: Int]] = [:]
        for name in counted.map({ AnalysisReport.settlement(from: $0.address) })
            + quarterRequests.map({ AnalysisReport.settlement(from: $0.address) }) {
            spellings[key(name), default: [:]][name, default: 0] += 1
        }
        let display: [String: String] = spellings.mapValues { variants in
            variants.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }!.key
        }

        let subsByKey = Dictionary(grouping: counted) { key(AnalysisReport.settlement(from: $0.address)) }
        let reqByKey = Dictionary(grouping: quarterRequests) { key(AnalysisReport.settlement(from: $0.address)) }

        return display
            .map { k, name in
                let subs = subsByKey[k] ?? []
                return Row(
                    settlement: name,
                    subscribers: subs.count,
                    withSubscriptions: subs.filter { !($0.subscriptions ?? []).isEmpty }.count,
                    requests: (reqByKey[k] ?? []).count
                )
            }
            .sorted { $0.settlement.localizedStandardCompare($1.settlement) == .orderedAscending }
    }

    /// CSV с разделителем «;», строка «Итого» внизу.
    static func csv(_ rows: [Row]) -> String {
        var lines = ["Населенный пункт;Количество абонентов;Абоненты с подпиской;Процент с подпиской;Количество сервисных заявок;Процент сервисных заявок"]

        for r in rows {
            lines.append([
                escape(r.settlement),
                "\(r.subscribers)",
                "\(r.withSubscriptions)",
                String(format: "%.2f", r.subscriptionPercent),
                "\(r.requests)",
                String(format: "%.2f", r.requestPercent),
            ].joined(separator: ";"))
        }

        let subscribers = rows.reduce(0) { $0 + $1.subscribers }
        let withSubs = rows.reduce(0) { $0 + $1.withSubscriptions }
        let requests = rows.reduce(0) { $0 + $1.requests }
        let total = Row(settlement: "Итого", subscribers: subscribers, withSubscriptions: withSubs, requests: requests)
        lines.append([
            "Итого",
            "\(total.subscribers)",
            "\(total.withSubscriptions)",
            String(format: "%.2f", total.subscriptionPercent),
            "\(total.requests)",
            String(format: "%.2f", total.requestPercent),
        ].joined(separator: ";"))

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func escape(_ field: String) -> String {
        let needsQuotes = field.contains(";") || field.contains("\"") || field.contains("\n") || field.contains("\r")
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
