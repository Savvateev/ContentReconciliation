import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var vm = ImportViewModel()

    private let xlsxType = UTType(filenameExtension: "xlsx") ?? .data

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Button("Импорт UID Login…") {
                    vm.showImporter = true
                }
                .keyboardShortcut("o", modifiers: .command)

                Spacer()

                Text("Записей: \(vm.records.count)")
                    .foregroundStyle(.secondary)
            }

            GroupBox("Данные (uid / login)") {
                List(Array(vm.records.enumerated()), id: \.offset) { _, record in
                    HStack {
                        Text(record.uid)
                            .frame(width: 200, alignment: .leading)
                            .textSelection(.enabled)
                        Text(record.login)
                            .textSelection(.enabled)
                    }
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
