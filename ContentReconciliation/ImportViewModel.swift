//
//  ImportViewModel.swift
//  ContentReconciliation
//
//  Created by Pavel Savvateev on 10.11.2026.
//

import Foundation
import SwiftUI
import Combine


@MainActor
final class ImportViewModel: ObservableObject {
    @Published var records: [UserRecord] = []
    @Published var logs: [String] = []
    @Published var showImporter = false
    @Published var isFetchingTokens = false

    init() {
        log("Запуск приложения")
        do {
            records = try DataStore.load()
            log("Загружен файл данных: \(records.count) записей")
            log("Путь к файлу данных: \(DataStore.fileURL.path)")
        } catch {
            log("Ошибка чтения файла данных: \(error.localizedDescription)")
        }
    }

    func log(_ message: String) {
        let time = Date.now.formatted(date: .omitted, time: .standard)
        logs.append("[\(time)] \(message)")
    }

    func importFile(_ url: URL) {
        log("Выбран файл: \(url.lastPathComponent)")

        // Нужно для файлов, выбранных через fileImporter в песочнице
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let imported = try XLSXReader.readUIDLogin(from: url.path) { message in
                self.log(message)
            }

            log("Сохраняю \(imported.count) записей в файл данных…")
            let all = records + imported
            try DataStore.save(all)
            records = all
            log("Готово. Всего записей в файле данных: \(all.count)")
        } catch {
            log("Ошибка импорта: \(error.localizedDescription)")
        }
    }

    /// Запрашивает токен для каждой записи и сохраняет их в файл данных.
    /// В журнал токены не пишутся, только факт получения.
    func fetchTokens() async {
        guard !records.isEmpty else {
            log("Нет записей: сначала выполните импорт")
            return
        }

        isFetchingTokens = true
        defer { isFetchingTokens = false }

        log("Получаю токены для \(records.count) пользователей…")
        var ok = 0
        var failed = 0

        for index in records.indices {
            let uid = records[index].uid
            do {
                let token = try await TokenService.fetchToken(uid: uid)
                records[index].token = token
                ok += 1
                log("uid \(uid): токен получен")
            } catch {
                failed += 1
                log("uid \(uid): ошибка, \(error.localizedDescription)")
            }
        }

        do {
            try DataStore.save(records)
            log("Токены сохранены в файл данных. Успешно: \(ok), с ошибкой: \(failed)")
        } catch {
            log("Ошибка сохранения файла данных: \(error.localizedDescription)")
        }
    }
}
