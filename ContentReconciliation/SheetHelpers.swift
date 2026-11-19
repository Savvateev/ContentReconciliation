import Foundation
import CoreXLSX

/// Общие функции для чтения ячеек и заголовков xlsx.
enum SheetHelpers {

    /// Приводит заголовок или значение к виду для сравнения:
    /// неразрывные пробелы и переносы заменяются на пробел, лишние пробелы убираются, регистр не важен.
    static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    static func text(of cell: Cell, _ sharedStrings: SharedStrings?) -> String {
        if let sharedStrings, let s = cell.stringValue(sharedStrings) {
            return s
        }
        return cell.value ?? ""
    }

    static func value(in row: Row, column: String, _ sharedStrings: SharedStrings?) -> String {
        guard let cell = row.cells.first(where: { $0.reference.column.value == column }) else {
            return ""
        }
        return text(of: cell, sharedStrings).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
