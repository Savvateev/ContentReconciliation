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
    @Published var requests: [ServiceRequest] = []
    @Published var showRequestsImporter = false
    @Published var isFetchingTokens = false
    @Published var isFetchingData = false

    init() {
        log("Запуск приложения")
        do {
            records = try DataStore.load()
            log("Загружен файл данных: \(records.count) записей")
            log("Путь к файлу данных: \(DataStore.fileURL.path)")
            removeDuplicateUIDs()
        } catch {
            log("Ошибка чтения файла данных: \(error.localizedDescription)")
        }
        do {
            requests = try DataStore.loadRequests()
            log("Загружены заявки: \(requests.count)")
        } catch {
            log("Ошибка чтения файла заявок: \(error.localizedDescription)")
        }
    }

    /// Импорт сервисных заявок из первого листа файла. Заявка с тем же номером заменяется.
    func importRequests(_ url: URL) {
        log("Выбран файл заявок: \(url.lastPathComponent)")

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let imported = try ServiceRequestReader.read(from: url.path) { message in
                self.log(message)
            }

            // Новый файл полностью заменяет прежний набор заявок: обновляются все поля,
            // заявки, которых нет в файле, убираются. Повторы номера внутри файла сохраняются.
            let previousCount = requests.count
            let removed = requests.filter { old in !imported.contains(where: { $0.number == old.number }) }.count
            try DataStore.saveRequests(imported)
            requests = imported
            log("Заявки: записано \(imported.count), было \(previousCount), убрано отсутствующих в файле \(removed)")
        } catch {
            log("Ошибка импорта заявок: \(error.localizedDescription)")
        }
    }

    /// Оставляет одну запись на каждый uid: первую. Пустые поля первой записи
    /// заполняются значениями из дубликатов, чтобы не потерять токен или подписки.
    /// Файл перезаписывается только если дубли были.
    private func removeDuplicateUIDs() {
        var result: [UserRecord] = []
        var indexByUID: [String: Int] = [:]
        var removed = 0

        for record in records {
            guard let index = indexByUID[record.uid] else {
                indexByUID[record.uid] = result.count
                result.append(record)
                continue
            }
            removed += 1
            result[index] = Self.merge(keep: result[index], extra: record)
        }

        guard removed > 0 else { return }

        do {
            try DataStore.save(result)
            records = result
            log("Очистка uid: удалено дублей \(removed), осталось записей \(result.count)")
        } catch {
            log("Ошибка сохранения после очистки дублей: \(error.localizedDescription)")
        }
    }

    /// Берёт поля из keep; если поле пустое, берёт его из extra.
    private static func merge(keep: UserRecord, extra: UserRecord) -> UserRecord {
        var out = keep
        if out.login.isEmpty { out.login = extra.login }
        if out.status == nil { out.status = extra.status }
        if out.token == nil { out.token = extra.token }
        if out.user == nil { out.user = extra.user }
        if out.fio == nil { out.fio = extra.fio }
        if out.phone == nil { out.phone = extra.phone }
        if out.address == nil { out.address = extra.address }
        if out.mobTel == nil { out.mobTel = extra.mobTel }
        if out.smsTel == nil { out.smsTel = extra.smsTel }
        if out.activated == nil { out.activated = extra.activated }
        if out.blocked == nil { out.blocked = extra.blocked }
        if out.password == nil { out.password = extra.password }
        if out.subscriptions == nil { out.subscriptions = extra.subscriptions }
        return out
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

            log("Проверяю уникальность uid и сохраняю записи…")
            var added = 0
            var updated = 0
            var skippedDuplicates = 0
            var seenInFile = Set<String>()
            var merged = records
            // Индекс по uid. Если в data.json уже есть дубли, не падаем: берём первую запись
            var indexByUID: [String: Int] = [:]
            for (index, record) in merged.enumerated() where indexByUID[record.uid] == nil {
                indexByUID[record.uid] = index
            }

            for item in imported {
                // Повтор uid внутри самого файла: берём первую строку
                if !seenInFile.insert(item.uid).inserted {
                    skippedDuplicates += 1
                    continue
                }
                if let index = indexByUID[item.uid] {
                    // Существующая запись: обновляем данные из файла, поля из API не трогаем
                    merged[index].login = item.login
                    merged[index].status = item.status
                    updated += 1
                } else {
                    indexByUID[item.uid] = merged.count
                    merged.append(item)
                    added += 1
                }
            }

            try DataStore.save(merged)
            records = merged
            log("Добавлено: \(added), обновлено: \(updated), повторов uid в файле пропущено: \(skippedDuplicates)")
            log("Готово. Всего записей в файле данных: \(merged.count)")
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

    /// Строит отчёт по населённым пунктам и сохраняет его в Загрузки/analiz.csv.
    /// На экран отчёт не выводится; в журнале пишутся только шаги и итоги.
    /// Отчёт по сервису за 3 квартал 2026 в «Загрузки/service_report_q3_2026.csv».
    func exportServiceReport() {
        guard !records.isEmpty else {
            log("Нет записей: сначала выполните импорт")
            return
        }

        let rows = ServiceReport.build(records: records, requests: requests)
        let csv = ServiceReport.csv(rows)
        let quarterRequests = requests.filter { ServiceReport.inQuarter($0) }.count
        let noDate = requests.filter { ServiceReport.createdDate($0.createdAt) == nil }.count
        log("Отчёт по сервису, 3 кв. 2026: населённых пунктов \(rows.count), заявок в квартале \(quarterRequests)")
        if noDate > 0 {
            log("Внимание: у \(noDate) заявок нет даты создания. Загрузите файл заявок заново, чтобы даты подтянулись")
        }

        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            log("Ошибка отчёта: папка «Загрузки» не найдена")
            return
        }
        let fileURL = downloads.appendingPathComponent("service_report_q3_2026.csv")

        do {
            var data = Data([0xEF, 0xBB, 0xBF])
            data.append(Data(csv.utf8))
            try data.write(to: fileURL, options: .atomic)
            log("Отчёт сохранён: \(fileURL.path)")
        } catch {
            log("Ошибка сохранения отчёта: \(error.localizedDescription)")
        }
    }

    func analyze() {
        guard !records.isEmpty else {
            log("Нет записей: сначала выполните импорт")
            return
        }

        let withData = records.filter { $0.address != nil || $0.subscriptions != nil }.count
        log("Экспорт статистики: записей \(records.count), с данными из cabinet/user: \(withData)")
        if withData < records.count {
            log("Внимание: у \(records.count - withData) записей нет данных, нажмите «Получить данные»")
        }

        let rows = AnalysisReport.build(records)
        let csv = AnalysisReport.csv(rows, records: records)

        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            log("Ошибка анализа: папка «Загрузки» не найдена")
            return
        }
        let fileURL = downloads.appendingPathComponent("analiz.csv")

        do {
            // BOM в начале файла: Excel читает кириллицу в UTF-8 без искажений
            var data = Data([0xEF, 0xBB, 0xBF])
            data.append(Data(csv.utf8))
            try data.write(to: fileURL, options: .atomic)
            log("Отчёт сохранён: \(fileURL.path). Населённых пунктов: \(rows.count)")
        } catch {
            log("Ошибка сохранения отчёта: \(error.localizedDescription)")
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
