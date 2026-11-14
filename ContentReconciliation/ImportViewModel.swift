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
    @Published var isFetchingData = false

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

    /// Запрашивает cabinet/user для первой записи с токеном и пишет ответ с именами полей в Downloads/export.txt.
    func exportUserInfo() async {
        guard let record = records.first(where: { $0.token != nil }),
              let token = record.token else {
            log("Нет токена: сначала нажмите «Получить токены»")
            return
        }

        isFetchingData = true
        defer { isFetchingData = false }

        log("Экспорт: запрашиваю данные uid \(record.uid)…")
        do {
            let raw = try await CabinetService.fetchRaw(token: token)
            let text = try UserInfoExport.makeText(uid: record.uid, login: record.login, raw: raw)

            guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                log("Ошибка экспорта: папка «Загрузки» не найдена")
                return
            }
            let fileURL = downloads.appendingPathComponent("export.txt")
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            log("Экспорт сохранён: \(fileURL.path)")
        } catch {
            log("Ошибка экспорта: \(error.localizedDescription)")
        }
    }

    /// Получает данные пользователя по токену для каждой записи и сохраняет их в файл данных.
    /// Персональные данные в журнал не пишутся.
    func fetchData() async {
        guard !records.isEmpty else {
            log("Нет записей: сначала выполните импорт")
            return
        }

        let indices = records.indices.filter { records[$0].token != nil }
        guard !indices.isEmpty else {
            log("Нет токенов: сначала нажмите «Получить токены»")
            return
        }

        isFetchingData = true
        defer { isFetchingData = false }

        log("Получаю данные для \(indices.count) пользователей…")
        var ok = 0
        var failed = 0

        for index in indices {
            let uid = records[index].uid
            guard let token = records[index].token else { continue }
            do {
                let info = try await CabinetService.fetchUser(token: token)
                records[index].user = info.user
                records[index].fio = info.fio
                records[index].phone = info.phone
                records[index].address = info.address
                records[index].mobTel = info.mobTel
                records[index].smsTel = info.smsTel
                records[index].activated = info.activated
                records[index].blocked = info.blocked
                records[index].password = info.password
                records[index].subscriptions = info.subscriptions
                ok += 1
                log("uid \(uid): данные получены, подписок: \(info.subscriptions.count)")
            } catch {
                failed += 1
                log("uid \(uid): ошибка, \(error.localizedDescription)")
            }
        }

        do {
            try DataStore.save(records)
            log("Данные сохранены в файл данных. Успешно: \(ok), с ошибкой: \(failed)")
        } catch {
            log("Ошибка сохранения файла данных: \(error.localizedDescription)")
        }
    }
}
