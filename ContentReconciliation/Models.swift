//
//  UserRecord.swift
//  ContentReconciliation
//
//  Created by Pavel Savvateev on 10.11.2026.
//


import Foundation

struct UserRecord: Codable, Hashable {
    let uid: String
    let login: String
    var token: String? = nil
}

enum ImportError: LocalizedError {
    case cannotOpen(String)
    case noSheets
    case emptySheet
    case sheetNotFound(String)
    case columnsNotFound([String])

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let path):
            return "Не удалось открыть файл: \(path)"
        case .noSheets:
            return "В файле нет листов"
        case .emptySheet:
            return "Первый лист пуст"
        case .sheetNotFound(let name):
            return "В файле нет листа «\(name)»"
        case .columnsNotFound(let names):
            return "Не найдены столбцы: \(names.joined(separator: ", "))"
        }
    }
}


/// Файл данных: JSON в Application Support/UIDLoginImporter/data.json
enum DataStore {
    static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UIDLoginImporter", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("data.json")
    }

    static func load() throws -> [UserRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([UserRecord].self, from: data)
    }

    static func save(_ records: [UserRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}
