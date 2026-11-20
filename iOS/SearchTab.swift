import SwiftUI

struct SearchTab: View {
    @State private var model = SearchModel()

    var body: some View {
        NavigationStack {
            List {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(SearchModel.genres, id: \.0) { g in
                            Button(g.0) { model.query = g.1; Task { await model.run(reset: true) } }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

                Picker("Lähde", selection: $model.source) {
                    ForEach(MusicSource.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .onChange(of: model.source) { _, _ in Task { await model.run(reset: true) } }

                ForEach(model.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }

                if !model.items.isEmpty {
                    Section(model.query.isEmpty ? "Albumit" : "Albumit – artistin omat ensin") {
                        ForEach(model.items) { item in
                            NavigationLink(value: item) { AlbumRow(item: item) }
                        }
                    }
                }
                if !model.tracks.isEmpty {
                    Section(model.source == .radio ? "Nettiradiot" : "Yksittäiset kappaleet") {
                        TrackListSection(tracks: model.tracks)
                    }
                }

                if model.loading {
                    ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
                } else if model.canMore {
                    Button("Näytä lisää") { Task { await model.run(reset: false) } }
                        .frame(maxWidth: .infinity).listRowSeparator(.hidden)
                } else if model.hasSearched && model.items.isEmpty && model.tracks.isEmpty && model.notes.isEmpty {
                    Text("Ei tuloksia.").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .listStyle(.plain)
            .navigationTitle(model.query.isEmpty ? "Suosituimmat" : "Haku")
            .navigationDestination(for: ArchiveItem.self) { AlbumDetailView(item: $0) }
            .searchable(text: $model.query, prompt: "Artisti, kappale tai aihe")
            .onSubmit(of: .search) { Task { await model.run(reset: true) } }
            .task { if !model.hasSearched { await model.run(reset: true) } }
        }
    }
}
