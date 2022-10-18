//
//  DebToIPAView.swift
//  DebToIPA
//
//  Created by exerhythm on 15.10.2022.
//

import SwiftUI

struct DebToIPAView: View {
    @State private var isImporting = false
    @State private var converting = false
    @State private var performCleanup = true
    @State private var statusText = ""
    @State var savedIpas: [SavedIpa] = []

    @State private var alertMessage = ""
    @State private var alertTitle = ""
    @State private var showingAlert = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(savedIpas) { ipa in
                    SavedIpaCellView(savedIpa: ipa)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            share(ipa.url!)
                        }
                }
                .onDelete(perform: delete)
                if converting {
                    HStack {
                        Spacer()
                        VStack(alignment: .center) {
                            ProgressView()
                                .padding(8)
                                
                            Text(statusText)
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        Spacer()
                    }
                }
            }
            .toolbar {
                Button(action: {
                    isImporting.toggle()
                }) {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .navigationTitle("DebToIPA")
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.init(filenameExtension: "deb")!],
            allowsMultipleSelection: false
        ) { result in
            guard let url = try? result.get().first else { alert("Couldn't get url of file. Did you select it?"); return }
            convert(url: url)
        }
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage)
            )
        }
        .onAppear {
            loadSavedIpas()
        }
    }
    
    func convert(url: URL) {
        converting = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard url.startAccessingSecurityScopedResource() else { throw ConversionError.noPermission }
                let ipa = try DebToIPA.convert(url, statusUpdate: { message in
                    DispatchQueue.main.async {
                        statusText = message
                    }
                })
                DispatchQueue.main.async {
                    savedIpas.append(ipa)
                    saveIpas()
                }
            } catch let error {
                DispatchQueue.main.async {
                    print(error)
                    if let convError = error as? ConversionError {
                        switch convError {
                        case .unsupportedApp:
                            alert("The .deb you imported is UNSUPPORTED by the method the app uses and CANNOT be converted to .ipa, as it doesn't have Applications folder. You can try using a PC/Mac to inject the tweak into .ipa.")
                        case .noDataFound:
                            alert("Data wasn't found in .deb. Are you sure the .deb you imported isn't corrupted?")
                        case .noApplication:
                            alert("The .deb you imported is UNSUPPORTED by the method the app uses and CANNOT be converted to .ipa, as it doesn't have Applications folder. You can try using a PC/Mac to inject the tweak into .ipa.")
                        case .noPermission:
                            alert("No permission to view the file")
                        case .unknownFiletypeInsideTar:
                            alert("Unknown filetype inside tar. This is a bug with the app. Please create an issue on Github with the name of tweak/app. Thanks!")
                        case .unsupportedCompression:
                            alert("Unsupported compression. This is a bug with the app. Please create an issue on Github with the name of tweak/app. Thanks!")
                        }
                    } else {
                        alert("Unknown error.\n" + error.localizedDescription)
                    }
                }
            }
            url.stopAccessingSecurityScopedResource()
            
            converting = false
        }
    }
    
    func share(_ url: URL) {
        // Share
        let shareActivity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let vc = UIApplication.shared.keyWindow?.rootViewController {
            shareActivity.popoverPresentationController?.sourceView = vc.view
            shareActivity.popoverPresentationController?.sourceRect = CGRect(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height, width: 0, height: 0)
            shareActivity.popoverPresentationController?.permittedArrowDirections = UIPopoverArrowDirection.down
            shareActivity.completionWithItemsHandler = { (type,completed, returnedItems, activityError) in
                statusText = "Done."
                if performCleanup {
                    do {
                        try DebToIPA.cleanup()
                    } catch {
                        alert("Cleanup failed. Reinstall is most likely needed. " + error.localizedDescription)
                    }
                }
            }
            DispatchQueue.main.async {
                vc.present(shareActivity, animated: true)
            }
        }
    }
    
    
    func delete(at offsets: IndexSet) {
        if let url = savedIpas[offsets.first!].url {
            try? FileManager.default.removeItem(at: url)
        }
        savedIpas.remove(at: offsets.first!)
        saveIpas()
    }
    func saveIpas() {
        guard let data = try? JSONEncoder().encode(savedIpas) else { return }
        UserDefaults.standard.set(data, forKey: "savedIpas")
    }
    func loadSavedIpas() {
        guard let data = UserDefaults.standard.data(forKey: "savedIpas") else { return }
        savedIpas = (try? JSONDecoder().decode([SavedIpa].self, from: data)) ?? []
    }
    
    func alert(_ message: String, title: String = "Error") {
        alertTitle = title
        alertMessage = message
        showingAlert.toggle()
    }
}

struct DebToIPAView_Previews: PreviewProvider {
    static var previews: some View {
        DebToIPAView(savedIpas: [])
    }
}

struct SavedIpaCellView: View {
    var savedIpa: SavedIpa
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(savedIpa.name)
                    .font(.headline)
                Text("\(savedIpa.version) · \(savedIpa.bundleID)")
                    .font(.caption)
            }
            Spacer()
        }
        .padding(4)
    }
}

struct SavedIpa: Codable, Identifiable {
    var id = UUID()
    var name: String
    var bundleID: String
    var version: String
    var url: URL?
}
