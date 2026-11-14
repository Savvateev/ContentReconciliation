import Foundation
import CoreXLSX

enum XLSXReader {

    static let sheetName = "Лист1"
    static let maxHeaderSearchRows = 50

    /// Читает столбцы uid и login с листа «Лист1». Шаги передаются в `progress`.
    static func readUIDLogin(from path: String, progress: (String) -> Void) throws -> [UserRecord] {
        progress("Открываю Excel-файл…")
        // XLSXFile(filepath:) возвращает опционал и не выбрасывает ошибку, поэтому без try
        guard let file = XLSXFile(filepath: path) else {
            throw ImportError.cannotOpen(path)
        }

        progress("Читаю общие строки…")
        let sharedStrings = try file.parseSharedStrings()

        progress("Ищу лист «\(sheetName)»…")
        guard let workbook = try file.parseWorkbooks().first else {
            throw ImportError.noSheets
        }
        let sheets = try file.parseWorksheetPathsAndNames(workbook: workbook)
        let available = sheets.compactMap { $0.name?.trimmingCharacters(in: .whitespaces) }
        progress("Листы в файле: \(available.joined(separator: ", "))")

        guard let sheet = sheets.first(where: {
            $0.name?.trimmingCharacters(in: .whitespaces) == sheetName
        }) else {
            throw ImportError.sheetNotFound(sheetName)
        }

        progress("Читаю лист «\(sheetName)» (\(sheet.path))…")
        let worksheet = try file.parseWorksheet(at: sheet.path)
        guard let rows = worksheet.data?.rows, !rows.isEmpty else {
            throw ImportError.emptySheet
        }

        progress("Ищу строку заголовков с uid и login (первые \(maxHeaderSearchRows) строк)…")
        var headerIndex: Int?
        var uidCol: String?
        var loginCol: String?
        var sampleHeaders: [String] = []

        for (index, row) in rows.prefix(maxHeaderSearchRows).enumerated() {
            var uid: String?
            var login: String?
            var rowTexts: [String] = []

            for cell in row.cells {
                let raw = text(of: cell, sharedStrings)
                let name = normalize(raw)
                if !name.isEmpty {
                    rowTexts.append("\(cell.reference.column.value)=«\(name)»")
                }
                if name == "uid"   { uid = cell.reference.column.value }
                if name == "login" || name == "логин" { login = cell.reference.column.value }
            }

            if sampleHeaders.count < 5 && !rowTexts.isEmpty {
                sampleHeaders.append("строка \(index + 1): " + rowTexts.joined(separator: ", "))
            }

            if let uid, let login {
                headerIndex = index
                uidCol = uid
                loginCol = login
                break
            }
        }

        guard let headerIndex, let uidColumn = uidCol, let loginColumn = loginCol else {
            for line in sampleHeaders {
                progress("Непустые строки: \(line)")
            }
            var missing: [String] = []
            if uidCol == nil { missing.append("uid") }
            if loginCol == nil { missing.append("login") }
            throw ImportError.columnsNotFound(missing)
        }
        progress("Строка заголовков: \(headerIndex + 1). uid → \(uidColumn), login → \(loginColumn)")

        progress("Читаю строки данных…")
        var records: [UserRecord] = []
        var skipped = 0
        for row in rows.dropFirst(headerIndex + 1) {
            let uid = value(in: row, column: uidColumn, sharedStrings)
            let login = value(in: row, column: loginColumn, sharedStrings)
            if uid.isEmpty && login.isEmpty {
                skipped += 1
                continue
            }
            records.append(UserRecord(uid: uid, login: login))
        }

        progress("Прочитано записей: \(records.count), пустых строк пропущено: \(skipped)")
        return records
    }

    /// Приводит заголовок к виду для сравнения: без пробелов по краям, без переносов и неразрывных пробелов, в нижнем регистре.
    private static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    private static func text(of cell: Cell, _ sharedStrings: SharedStrings?) -> String {
        if let sharedStrings, let s = cell.stringValue(sharedStrings) {
            return s
        }
        return cell.value ?? ""
    }

    private static func value(in row: Row, column: String, _ sharedStrings: SharedStrings?) -> String {
        guard let cell = row.cells.first(where: { $0.reference.column.value == column }) else {
            return ""
        }
        return text(of: cell, sharedStrings).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
