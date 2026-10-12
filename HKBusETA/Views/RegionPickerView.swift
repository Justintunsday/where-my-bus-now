import SwiftUI

struct RegionPickerView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var regions: [TransitRegion] {
        RegionCatalog.all.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { select(RegionCatalog.autoID) } label: {
                        HStack {
                            Label(L10n.t("settings.region.auto"), systemImage: "location.fill")
                            Spacer()
                            if app.settings.selectedRegionID == RegionCatalog.autoID { Image(systemName: "checkmark") }
                        }.frame(minHeight: 44)
                    }
                } footer: { Text("\(L10n.t("settings.region.current")) · \(app.region.name)") }
                Section(L10n.t("settings.region")) {
                    ForEach(regions) { region in
                        Button { select(region.id) } label: {
                            HStack {
                                Text(region.name).foregroundStyle(.primary)
                                Spacer()
                                if app.settings.selectedRegionID == region.id { Image(systemName: "checkmark") }
                            }.frame(minHeight: 44)
                        }
                        .accessibilityAddTraits(app.settings.selectedRegionID == region.id ? [.isSelected] : [])
                    }
                }
            }
            .searchable(text: $query, prompt: Text(L10n.t("region.search")))
            .navigationTitle(L10n.t("settings.region"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.t("common.done")) { dismiss() } } }
        }
    }
    private func select(_ id: String) {
        app.settings.selectedRegionID = id
        app.settings.persist()
        app.selectRegion(id)
        dismiss()
    }
}
