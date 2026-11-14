import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var vm = ImportViewModel()

    private let xlsxType = UTType(filenameExtension: "xlsx") ?? .data

    private var isBusy: Bool { vm.isFetchingTokens || vm.isFetchingData }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Button("Импорт UID Login…") {
                    vm.showImporter = true
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(isBusy)

                Button("Получить токены") {
                    Task { await vm.fetchTokens() }
                }
                .disabled(vm.records.isEmpty || isBusy)

                Button("Получить данные") {
                    Task { await vm.fetchData() }
                }
                .disabled(vm.records.isEmpty || isBusy)

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Text("Записей: \(vm.records.count)")
                    .foregroundStyle(.secondary)
            }

            GroupBox("Данные") {
                List(Array(vm.records.enumerated()), id: \.offset) { _, record in
                    RecordRow(record: record)
                }
                .frame(minHeight: 200)
            }

            GroupBox("Журнал") {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(vm.logs.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                        .padding(4)
                    }
                    .onChange(of: vm.logs.count) { _ in
                        if let last = vm.logs.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
                .frame(minHeight: 180)
            }
        }
        .padding()
        .frame(minWidth: 700, minHeight: 600)
        .fileImporter(
            isPresented: $vm.showImporter,
            allowedContentTypes: [xlsxType],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    vm.importFile(url)
                }
            case .failure(let error):
                vm.log("Выбор файла отменён или с ошибкой: \(error.localizedDescription)")
            }
        }
    }
}

private struct RecordRow: View {
    let record: UserRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("uid \(record.uid) · login \(record.login)")

            let contacts = [record.fio, record.phone, record.mobTel, record.smsTel]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            if !contacts.isEmpty {
                Text(contacts.joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }

            if let address = record.address, !address.isEmpty {
                Text(address)
                    .foregroundStyle(.secondary)
            }

            if let subs = record.subscriptions, !subs.isEmpty {
                Text("Подписки: " + subs.map { "\($0.name) — \(String(format: "%.2f", $0.price))" }.joined(separator: "; "))
            }

            Text("Токен: " + (record.token.map { String($0.prefix(24)) + "…" } ?? "нет"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .textSelection(.enabled)
    }
}
