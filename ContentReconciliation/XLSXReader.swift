import Foundation
import CoreXLSX

enum XLSXReader {

    /// Читает столбцы uid и login с первого листа. Шаги передаются в `progress`.
    static func readUIDLogin(from path: String, progress: (String) -> Void) throws -> [UserRecord] {
        progress("Открываю Excel-файл…")
        // XLSXFile(filepath:) возвращает опционал и не выбрасывает ошибку, поэтому без try
        guard let file = XLSXFile(filepath: path) else {
            throw ImportError.cannotOpen(path)
        }

        progress("Читаю общие строки и список листов…")
        let sharedStrings = try file.parseSharedStrings()

        guard let sheetPath = try file.parseWorksheetPaths().first else {
            throw ImportError.noSheets
        }

        progress("Читаю первый лист: \(sheetPath)")
        let worksheet = try file.parseWorksheet(at: sheetPath)
        guard let rows = worksheet.data?.rows, let header = rows.first else {
            throw ImportError.emptySheet
        }

        progress("Ищу столбцы uid и login в первой строке…")
        var uidColumn: String?
        var loginColumn: String?
        for cell in header.cells {
            let name = text(of: cell, sharedStrings)
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            if name == "uid"   { uidColumn = cell.reference.column.value }
            if name == "login" { loginColumn = cell.reference.column.value }
        }

        var missing: [String] = []
        if uidColumn == nil { missing.append("uid") }
        if loginColumn == nil { missing.append("login") }
        guard missing.isEmpty, let uidCol = uidColumn, let loginCol = loginColumn else {
            throw ImportError.columnsNotFound(missing)
        }
        progress("Найдены столбцы: uid → \(uidCol), login → \(loginCol)")

        progress("Читаю строки данных…")
        var records: [UserRecord] = []
        var skipped = 0
        for row in rows.dropFirst() {
            let uid = value(in: row, column: uidCol, sharedStrings)
            let login = value(in: row, column: loginCol, sharedStrings)
            if uid.isEmpty && login.isEmpty {
                skipped += 1
                continue
            }
            records.append(UserRecord(uid: uid, login: login))
        }

        progress("Прочитано записей: \(records.count), пустых строк пропущено: \(skipped)")
        return records
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
