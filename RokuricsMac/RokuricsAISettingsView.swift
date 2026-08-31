import AppKit
import SwiftUI

// Rokurics uses the same provider-list/detail/config-file interaction as
// Intatis, backed by its own app-local configuration and credentials.
struct RokuricsAISettingsView: View {
    @ObservedObject var store: RokuricsAIConfigurationStore

    @Environment(\.colorScheme) private var colorScheme
    @State private var catalog: RokuricsAICatalog
    @State private var apiKeysByProviderID: [String: String] = [:]
    @State private var isConnectionExpanded = false
    @State private var isModelsExpanded = false
    @State private var isTesting = false
    @State private var saved = false
    @State private var message: String?
    @State private var messageIsSuccess = false

    init(store: RokuricsAIConfigurationStore) {
        self.store = store
        _catalog = State(initialValue: store.catalog)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    providerList
                        .frame(width: 220, alignment: .topLeading)
                    Divider().opacity(0.45)
                    providerDetail
                }

                VStack(alignment: .leading, spacing: 18) {
                    providerList
                    Divider().opacity(0.45)
                    providerDetail
                }
            }
            .padding(20)
            .macLiquidGlassCard(
                cornerRadius: 22,
                material: .thinMaterial,
                fillOpacity: 0.34,
                strokeOpacity: 0.34,
                shadowOpacity: 0.06,
                shadowRadius: 12,
                shadowY: 6
            )

            if let message {
                Label(
                    message,
                    systemImage: messageIsSuccess
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .font(MacTypography.body(size: 12, weight: .semibold))
                .foregroundStyle(messageIsSuccess ? MacTheme.leaf : MacTheme.coral)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if saved {
                    Label(RokuricsCopy.text("已保存", "Saved"), systemImage: "checkmark.circle.fill")
                        .font(MacTypography.body(size: 12, weight: .semibold))
                        .foregroundStyle(MacTheme.leaf)
                }

                Spacer(minLength: 0)

                Button(action: testProvider) {
                    Label(
                        isTesting ? RokuricsCopy.text("测试中", "Testing") : RokuricsCopy.text("测试服务", "Test Provider"),
                        systemImage: isTesting ? "hourglass" : "checkmark.seal"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(isTesting)

                Button(RokuricsCopy.text("保存", "Save"), action: save)
                    .buttonStyle(.borderedProminent)
            }

            Divider().opacity(0.45)

            DisclosureGroup {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(RokuricsCopy.text("配置文件", "Configuration"))
                            .font(MacTypography.body(size: 13, weight: .semibold))
                        Text(store.configurationURL.lastPathComponent)
                            .font(MacTypography.technical(size: 11, weight: .regular))
                            .foregroundStyle(MacTheme.softText(for: colorScheme))
                    }
                    Spacer(minLength: 12)
                    Button(action: openConfiguration) {
                        Label(RokuricsCopy.text("打开 Rokurics 配置", "Open Rokurics Config"), systemImage: "curlybraces")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 10)
            } label: {
                Label(RokuricsCopy.text("高级设置", "Advanced Settings"), systemImage: "slider.horizontal.3")
                    .font(MacTypography.body(size: 13, weight: .semibold))
            }
        }
        .onAppear {
            store.reload()
            catalog = store.catalog
            message = store.lastErrorMessage
            messageIsSuccess = false
        }
    }

    private var providerList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(RokuricsCopy.text("服务", "Providers"))
                    .font(MacTypography.body(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.softText(for: colorScheme))
                Spacer()
                Button(action: addProvider) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help(RokuricsCopy.text("添加服务", "Add provider"))
            }

            ForEach(catalog.providers) { provider in
                let isSelected = provider.id == catalog.selectedProviderID
                Button {
                    select(provider)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? MacTheme.aqua : MacTheme.softText(for: colorScheme))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(provider.title)
                                .font(MacTypography.body(size: 13, weight: .semibold))
                                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                            Text(provider.models.isEmpty
                                 ? RokuricsCopy.text("没有模型", "No models")
                                 : RokuricsCopy.text("\(provider.models.count) 个模型", "\(provider.models.count) models"))
                                .font(MacTypography.technical(size: 10, weight: .regular))
                                .foregroundStyle(MacTheme.softText(for: colorScheme))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(
                                isSelected ? MacTheme.aqua.opacity(0.5) : MacTheme.glassStroke(for: colorScheme).opacity(0.3),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var providerDetail: some View {
        if let providerIndex = selectedProviderIndex {
            VStack(alignment: .leading, spacing: 14) {
                field(
                    RokuricsCopy.text("服务名称", "Provider name"),
                    text: providerBinding(providerIndex, \.displayName),
                    placeholder: "OpenAI"
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("API key")
                        .font(MacTypography.body(size: 12, weight: .semibold))
                        .foregroundStyle(MacTheme.softText(for: colorScheme))
                    SecureField(
                        catalog.providers[providerIndex].credential.displayDescription,
                        text: apiKeyBinding(providerID: catalog.providers[providerIndex].id)
                    )
                    .textFieldStyle(.plain)
                    .macSettingsFieldChrome()
                }

                activeModelPicker(providerIndex: providerIndex)

                DisclosureGroup(isExpanded: $isConnectionExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        field(
                            "Base URL",
                            text: baseURLBinding(providerIndex: providerIndex),
                            placeholder: "https://api.openai.com/v1"
                        )
                        field(
                            "Chat endpoint",
                            text: providerBinding(providerIndex, \.chatEndpoint),
                            placeholder: "https://api.openai.com/v1/chat/completions"
                        )
                    }
                    .padding(.top, 10)
                } label: {
                    Text(RokuricsCopy.text("连接", "Connection"))
                        .font(MacTypography.body(size: 13, weight: .semibold))
                }

                modelManagement(providerIndex: providerIndex)

                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        removeSelectedProvider()
                    } label: {
                        Label(RokuricsCopy.text("移除服务", "Remove Provider"), systemImage: "trash")
                    }
                    .buttonStyle(.plain)
                    .disabled(catalog.providers.count <= 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(RokuricsCopy.text("添加服务后即可配置模型", "Add a provider to configure models"))
                .foregroundStyle(MacTheme.softText(for: colorScheme))
        }
    }

    private func activeModelPicker(providerIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(RokuricsCopy.text("当前模型", "Active model"))
                .font(MacTypography.body(size: 12, weight: .semibold))
                .foregroundStyle(MacTheme.softText(for: colorScheme))
            Picker("", selection: $catalog.selectedModelID) {
                ForEach(catalog.providers[providerIndex].models) { model in
                    Text(model.title).tag(model.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(catalog.providers[providerIndex].models.isEmpty)
        }
    }

    private func modelManagement(providerIndex: Int) -> some View {
        DisclosureGroup(isExpanded: $isModelsExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(catalog.providers[providerIndex].models.indices), id: \.self) { modelIndex in
                    HStack(spacing: 8) {
                        TextField(
                            RokuricsCopy.text("模型 ID", "Model ID"),
                            text: modelBinding(providerIndex: providerIndex, modelIndex: modelIndex, keyPath: \.id)
                        )
                        .textFieldStyle(.plain)
                        .macSettingsFieldChrome()

                        TextField(
                            RokuricsCopy.text("显示名称", "Display name"),
                            text: modelBinding(providerIndex: providerIndex, modelIndex: modelIndex, keyPath: \.displayName)
                        )
                        .textFieldStyle(.plain)
                        .macSettingsFieldChrome()

                        Button {
                            removeModel(providerIndex: providerIndex, modelIndex: modelIndex)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .disabled(catalog.providers[providerIndex].models.count <= 1)
                    }
                }

                Button(action: { addModel(providerIndex: providerIndex) }) {
                    Label(RokuricsCopy.text("添加模型", "Add model"), systemImage: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
        } label: {
            Text(RokuricsCopy.text("管理模型", "Models"))
                .font(MacTypography.body(size: 13, weight: .semibold))
        }
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(MacTypography.body(size: 12, weight: .semibold))
                .foregroundStyle(MacTheme.softText(for: colorScheme))
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .macSettingsFieldChrome()
        }
    }

    private var selectedProviderIndex: Int? {
        catalog.providers.firstIndex { $0.id == catalog.selectedProviderID }
    }

    private func select(_ provider: RokuricsAIProvider) {
        catalog.selectedProviderID = provider.id
        catalog.selectedModelID = provider.models.first?.id ?? ""
        saved = false
        message = nil
    }

    private func addProvider() {
        let id = "provider-\(UUID().uuidString.lowercased().prefix(8))"
        let provider = RokuricsAIProvider(
            id: id,
            displayName: RokuricsCopy.text("新服务", "New Provider"),
            baseURL: "https://api.openai.com/v1",
            credential: .missing,
            models: [RokuricsAIModel(id: "model-id", displayName: "Model")]
        )
        catalog.providers.append(provider)
        select(provider)
    }

    private func removeSelectedProvider() {
        guard catalog.providers.count > 1,
              let index = selectedProviderIndex else { return }
        catalog.providers.remove(at: index)
        select(catalog.providers[0])
    }

    private func addModel(providerIndex: Int) {
        let model = RokuricsAIModel(id: "model-\(catalog.providers[providerIndex].models.count + 1)", displayName: "Model")
        catalog.providers[providerIndex].models.append(model)
        catalog.selectedModelID = model.id
    }

    private func removeModel(providerIndex: Int, modelIndex: Int) {
        guard catalog.providers[providerIndex].models.count > 1 else { return }
        let removed = catalog.providers[providerIndex].models.remove(at: modelIndex)
        if catalog.selectedModelID == removed.id {
            catalog.selectedModelID = catalog.providers[providerIndex].models[0].id
        }
        if catalog.transcriptionModel == RokuricsAIModelReference(
            providerID: catalog.providers[providerIndex].id,
            modelID: removed.id
        ) {
            catalog.transcriptionModel = nil
        }
    }

    private func save() {
        do {
            try store.save(catalog: catalog, apiKeysByProviderID: apiKeysByProviderID)
            catalog = store.catalog
            apiKeysByProviderID = [:]
            message = nil
            messageIsSuccess = true
            saved = true
        } catch {
            message = error.localizedDescription
            messageIsSuccess = false
            saved = false
        }
    }

    private func testProvider() {
        guard !isTesting else { return }
        isTesting = true
        message = nil
        Task { @MainActor in
            defer { isTesting = false }
            do {
                try store.save(catalog: catalog, apiKeysByProviderID: apiKeysByProviderID)
                catalog = store.catalog
                apiKeysByProviderID = [:]
                let route = try store.summaryRoute()
                _ = try await RokuricsAIRuntime().healthCheck(route: route)
                message = RokuricsCopy.text("服务可用", "Provider is available")
                messageIsSuccess = true
                saved = true
            } catch {
                message = error.localizedDescription
                messageIsSuccess = false
                saved = false
            }
        }
    }

    private func openConfiguration() {
        do {
            let url = try store.prepareEditableConfigurationFile()
            guard NSWorkspace.shared.open(url) else {
                throw RokuricsAIConfigurationError.configurationUnreadable
            }
            message = nil
            messageIsSuccess = true
        } catch {
            message = error.localizedDescription
            messageIsSuccess = false
        }
    }

    private func providerBinding(
        _ providerIndex: Int,
        _ keyPath: WritableKeyPath<RokuricsAIProvider, String>
    ) -> Binding<String> {
        Binding {
            catalog.providers[providerIndex][keyPath: keyPath]
        } set: { value in
            catalog.providers[providerIndex][keyPath: keyPath] = value
            saved = false
        }
    }

    private func baseURLBinding(providerIndex: Int) -> Binding<String> {
        Binding {
            catalog.providers[providerIndex].baseURL
        } set: { value in
            let oldBase = catalog.providers[providerIndex].baseURL
            let oldDefault = RokuricsAIProvider.defaultChatEndpoint(baseURL: oldBase)
            catalog.providers[providerIndex].baseURL = value
            if catalog.providers[providerIndex].chatEndpoint == oldDefault {
                catalog.providers[providerIndex].chatEndpoint = RokuricsAIProvider.defaultChatEndpoint(baseURL: value)
            }
            saved = false
        }
    }

    private func modelBinding(
        providerIndex: Int,
        modelIndex: Int,
        keyPath: WritableKeyPath<RokuricsAIModel, String>
    ) -> Binding<String> {
        Binding {
            catalog.providers[providerIndex].models[modelIndex][keyPath: keyPath]
        } set: { value in
            let oldID = catalog.providers[providerIndex].models[modelIndex].id
            catalog.providers[providerIndex].models[modelIndex][keyPath: keyPath] = value
            if keyPath == \.id, catalog.selectedModelID == oldID {
                catalog.selectedModelID = value
            }
            if keyPath == \.id,
               catalog.transcriptionModel == RokuricsAIModelReference(
                   providerID: catalog.providers[providerIndex].id,
                   modelID: oldID
               ) {
                catalog.transcriptionModel?.modelID = value
            }
            saved = false
        }
    }

    private func apiKeyBinding(providerID: String) -> Binding<String> {
        Binding {
            apiKeysByProviderID[providerID] ?? ""
        } set: { value in
            apiKeysByProviderID[providerID] = value
            saved = false
        }
    }
}
