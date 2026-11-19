import Foundation
import CoreXLSX

/// Сервисная заявка из файла импорта.
struct ServiceRequest: Codable, Hashable {
    let number: String
    let login: String
    let address: String
    let type: String
    let description: String
    let comment: String

    // Старые записи в service_requests.json не содержат description, поэтому читаем со значением по умолчанию
    init(number: String, login: String, address: String, type: String, description: String, comment: String) {
        self.number = number
        self.login = login
        self.address = address
        self.type = type
        self.description = description
        self.comment = comment
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = try c.decode(String.self, forKey: .number)
        login = try c.decode(String.self, forKey: .login)
        address = try c.decode(String.self, forKey: .address)
        type = try c.decode(String.self, forKey: .type)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        comment = try c.decode(String.self, forKey: .comment)
    }
}

/// Читает сервисные заявки с первого листа файла.
enum ServiceRequestReader {

    static let maxHeaderSearchRows = 50

    /// Нужные колонки и варианты их заголовков (без учёта регистра и лишних пробелов).
    static let columnTitles: [(key: String, titles: Set<String>)] = [
        ("number", ["номер заявки", "№ заявки"]),
        ("login", ["логин", "login"]),
        ("address", ["адрес"]),
        ("type", ["тип заявки"]),
        ("description", ["описание заявки"]),
        ("comment", ["комментарий при выполнении"]),
    ]

    static func read(from path: String, progress: (String) -> Void) throws -> [ServiceRequest] {
        progress("Открываю файл заявок…")
        guard let file = XLSXFile(filepath: path) else {
            throw ImportError.cannotOpen(path)
        }

        let sharedStrings = try file.parseSharedStrings()

        guard let worksheetPath = try file.parseWorksheetPaths().first else {
            throw ImportError.noSheets
        }
        progress("Читаю первый лист заявок: \(worksheetPath)")

        let worksheet = try file.parseWorksheet(at: worksheetPath)
        guard let rows = worksheet.data?.rows, !rows.isEmpty else {
            throw ImportError.emptySheet
        }

        progress("Ищу строку заголовков заявок…")
        var headerIndex: Int?
        var columns: [String: String] = [:]

        for (index, row) in rows.prefix(maxHeaderSearchRows).enumerated() {
            var found: [String: String] = [:]
            for cell in row.cells {
                let name = SheetHelpers.normalize(SheetHelpers.text(of: cell, sharedStrings))
                for (key, titles) in columnTitles where titles.contains(name) {
                    found[key] = cell.reference.column.value
                }
            }
            // Строка заголовков — та, где найдены все нужные колонки
            if found.count == columnTitles.count {
                headerIndex = index
                columns = found
                break
            }
        }

        guard let headerIndex else {
            // Показываем, что нашлось в первых строках, чтобы было видно, какого заголовка не хватает
            for (index, row) in rows.prefix(maxHeaderSearchRows).enumerated() {
                let names = row.cells
                    .map { SheetHelpers.normalize(SheetHelpers.text(of: $0, sharedStrings)) }
                    .filter { !$0.isEmpty }
                if !names.isEmpty {
                    progress("Строка \(index + 1): \(names.joined(separator: " | "))")
                }
            }
            let missing = columnTitles.filter { columns[$0.key] == nil }.map { $0.titles.first ?? $0.key }
            throw ImportError.columnsNotFound(missing)
        }
        progress("Строка заголовков заявок: \(headerIndex + 1)")

        var requests: [ServiceRequest] = []
        var skipped = 0
        for row in rows.dropFirst(headerIndex + 1) {
            let item = ServiceRequest(
                number: SheetHelpers.value(in: row, column: columns["number"]!, sharedStrings),
                login: SheetHelpers.value(in: row, column: columns["login"]!, sharedStrings),
                address: SheetHelpers.value(in: row, column: columns["address"]!, sharedStrings),
                type: SheetHelpers.value(in: row, column: columns["type"]!, sharedStrings),
                description: SheetHelpers.value(in: row, column: columns["description"]!, sharedStrings),
                comment: SheetHelpers.value(in: row, column: columns["comment"]!, sharedStrings)
            )
            // Пустую строку (без номера и логина) пропускаем
            if item.number.isEmpty && item.login.isEmpty {
                skipped += 1
                continue
            }
            requests.append(item)
        }

        progress("Прочитано заявок: \(requests.count), пустых строк пропущено: \(skipped)")
        return requests
    }
}
