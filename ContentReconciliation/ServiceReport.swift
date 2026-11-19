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
        /// Заявки квартала, в типе которых есть «Проблемы с ТВ».
        let tvProblems: Int
        /// Заявки квартала, у которых логин встречается в этом пункте 2 и более раза.
        let repeatRequests: Int

        var subscriptionPercent: Double { percent(withSubscriptions, of: subscribers) }
        var requestPercent: Double { percent(requests, of: subscribers) }
        /// Проблемы с ТВ от абонентов с подпиской.
        var tvProblemPercent: Double { percent(tvProblems, of: withSubscriptions) }
        /// Повторные заявки от количества абонентов.
        var repeatPercent: Double { percent(repeatRequests, of: subscribers) }

        private func percent(_ part: Int, of whole: Int) -> Double {
            whole == 0 ? 0 : Double(part) / Double(whole) * 100
        }
    }

    /// Абонент с повторными заявками в пункте.
    struct RepeatSubscriber {
        let login: String
        let settlement: String
        let count: Int
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

    static func normalizedType(_ type: String) -> String {
        type
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    static func isExcludedType(_ type: String) -> Bool {
        excludedTypes.contains(normalizedType(type))
    }

    /// Тип заявки содержит «Проблемы с ТВ» (без учёта регистра и лишних пробелов).
    static func isTVProblem(_ type: String) -> Bool {
        normalizedType(type).contains("проблемы с тв")
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
    /// «город Черемхово (МС)» приравнивается к «г. Черемхово».
    static func key(_ settlement: String) -> String {
        var fixed = settlement
            .replacingOccurrences(of: "c", with: "с")
            .replacingOccurrences(of: "C", with: "с")
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        fixed = fixed.replacingOccurrences(of: " (мс)", with: "")
        if fixed.hasPrefix("город ") {
            fixed = "г." + fixed.dropFirst("город".count)
        }
        return fixed.replacingOccurrences(of: ". ", with: ".")
    }

    /// Название пункта для вывода: самое частое написание в данных, по ключу.
    static func displayNames(records: [UserRecord], requests: [ServiceRequest]) -> [String: String] {
        let counted = records.filter { isCounted($0) }
        let quarterRequests = requests.filter { inQuarter($0) }

        var spellings: [String: [String: Int]] = [:]
        for name in counted.map({ AnalysisReport.settlement(from: $0.address) })
            + quarterRequests.map({ AnalysisReport.settlement(from: $0.address) }) {
            spellings[key(name), default: [:]][name, default: 0] += 1
        }
        return spellings.mapValues { variants in
            variants.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }!.key
        }
    }

    /// Число заявок квартала по логину в каждом пункте (пустые логины пропускаются).
    private static func loginCounts(_ requests: [ServiceRequest]) -> [(settlementKey: String, login: String, count: Int)] {
        var counts: [String: Int] = [:]
        var sample: [String: (settlementKey: String, login: String)] = [:]
        for r in requests {
            let login = r.login.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !login.isEmpty else { continue }
            let sk = key(AnalysisReport.settlement(from: r.address))
            let id = sk + "|" + login.lowercased()
            counts[id, default: 0] += 1
            if sample[id] == nil { sample[id] = (sk, login) }
        }
        return counts.compactMap { id, n in
            guard let s = sample[id] else { return nil }
            return (s.settlementKey, s.login, n)
        }
    }

    static func build(records: [UserRecord], requests: [ServiceRequest]) -> [Row] {
        let counted = records.filter { isCounted($0) }
        let quarterRequests = requests.filter { inQuarter($0) }
        let display = displayNames(records: records, requests: requests)

        let subsByKey = Dictionary(grouping: counted) { key(AnalysisReport.settlement(from: $0.address)) }
        let reqByKey = Dictionary(grouping: quarterRequests) { key(AnalysisReport.settlement(from: $0.address)) }
        let repeatByKey = Dictionary(grouping: loginCounts(quarterRequests).filter { $0.count >= 2 }) { $0.settlementKey }

        return display
            .map { k, name in
                let subs = subsByKey[k] ?? []
                let reqs = reqByKey[k] ?? []
                return Row(
                    settlement: name,
                    subscribers: subs.count,
                    withSubscriptions: subs.filter { !($0.subscriptions ?? []).isEmpty }.count,
                    requests: reqs.count,
                    tvProblems: reqs.filter { isTVProblem($0.type) }.count,
                    repeatRequests: (repeatByKey[k] ?? []).reduce(0) { $0 + $1.count }
                )
            }
            .sorted { $0.settlement.localizedStandardCompare($1.settlement) == .orderedAscending }
    }

    /// Абоненты с повторными заявками: логин встречается 2 и более раза в пункте.
    static func repeatSubscribers(records: [UserRecord], requests: [ServiceRequest]) -> [RepeatSubscriber] {
        let quarterRequests = requests.filter { inQuarter($0) }
        let display = displayNames(records: records, requests: requests)

        return loginCounts(quarterRequests)
            .filter { $0.count >= 2 }
            .map { RepeatSubscriber(login: $0.login, settlement: display[$0.settlementKey] ?? $0.settlementKey, count: $0.count) }
            .sorted {
                if $0.settlement != $1.settlement {
                    return $0.settlement.localizedStandardCompare($1.settlement) == .orderedAscending
                }
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.login.localizedStandardCompare($1.login) == .orderedAscending
            }
    }

    /// CSV с разделителем «;». Таблица, строка «Итого», затем список абонентов с повторными заявками.
    static func csv(_ rows: [Row], repeats: [RepeatSubscriber]) -> String {
        var lines = ["Населенный пункт;Количество абонентов;Абоненты с подпиской;Процент с подпиской;Количество сервисных заявок;Процент сервисных заявок;Проблемы с ТВ;Процент проблем с ТВ;Повторные заявки;Процент повторных заявок"]

        for r in rows {
            lines.append([
                escape(r.settlement),
                "\(r.subscribers)",
                "\(r.withSubscriptions)",
                decimal(r.subscriptionPercent),
                "\(r.requests)",
                decimal(r.requestPercent),
                "\(r.tvProblems)",
                decimal(r.tvProblemPercent),
                "\(r.repeatRequests)",
                decimal(r.repeatPercent),
            ].joined(separator: ";"))
        }

        let subscribers = rows.reduce(0) { $0 + $1.subscribers }
        let withSubs = rows.reduce(0) { $0 + $1.withSubscriptions }
        let requests = rows.reduce(0) { $0 + $1.requests }
        let tv = rows.reduce(0) { $0 + $1.tvProblems }
        let repeatReqs = rows.reduce(0) { $0 + $1.repeatRequests }
        let total = Row(settlement: "Итого", subscribers: subscribers, withSubscriptions: withSubs,
                        requests: requests, tvProblems: tv, repeatRequests: repeatReqs)
        lines.append([
            "Итого",
            "\(total.subscribers)",
            "\(total.withSubscriptions)",
            decimal(total.subscriptionPercent),
            "\(total.requests)",
            decimal(total.requestPercent),
            "\(total.tvProblems)",
            decimal(total.tvProblemPercent),
            "\(total.repeatRequests)",
            decimal(total.repeatPercent),
        ].joined(separator: ";"))

        // Список абонентов с повторными заявками ниже таблицы
        lines.append("")
        lines.append("Абоненты с повторными заявками")
        lines.append("Логин;Город;Количество заявок")
        for s in repeats {
            lines.append([escape(s.login), escape(s.settlement), "\(s.count)"].joined(separator: ";"))
        }

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Дробное число с двумя знаками и запятой как десятичным разделителем: 12.5 → 12,50.
    static func decimal(_ value: Double) -> String {
        String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    private static func escape(_ field: String) -> String {
        let needsQuotes = field.contains(";") || field.contains("\"") || field.contains("\n") || field.contains("\r")
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
