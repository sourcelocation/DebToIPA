//
//  ContentView.swift
//  DebToIPA
//
//  Created by exerhythm on 13.10.2022.
//

import SwiftUI

struct ContentView: View {
    @State private var isImporting = false
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var converting = false
    
    var body: some View {
        NavigationView {
            VStack {
                ProgressView()
                    .padding()
                    .opacity(converting ? 1 : 0)
                Button("Import .deb", action: {
                    isImporting.toggle()
                })
                .padding(10)
                .background(Color.blue)
                .cornerRadius(8)
                .foregroundColor(.white)
                Text("By sourcelocation\n\nCredits: itsnebulalol,\nLebJe/ArArchiveKit,\nmarmelroy/Zip,\ntsolomko/SWCompression")
                    .foregroundColor(Color.secondary)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                
            }
            .navigationTitle("DebToIPA")
        }
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
                title: Text("Error"),
                message: Text(alertMessage)
            )
        }
    }
    
    func convert(url: URL) {
        converting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
            do {
                guard url.startAccessingSecurityScopedResource() else { throw ConversionError.noPermission }
                let ipa = try DebToIPA.convert(url)
                share(ipa)
            } catch let error {
                print(error)
                if let convError = error as? ConversionError {
                    switch convError {
                    case .unsupportedApp:
                        alert("The .deb you imported is UNSUPPORTED and CANNOT be converted to .ipa, as it doesn't have Applications folder.")
                    case .noDataFound:
                        alert("Data wasn't found in .deb. Are you sure the .deb you imported isn't corrupted?")
                    case .noApplication:
                        alert("The .deb you imported is UNSUPPORTED and CANNOT be converted to .ipa, as it doesn't have a .app file inside it.")
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
            url.stopAccessingSecurityScopedResource()
            
            converting = false
        })
    }
    
    func share(_ url: URL) {
        // Share
        let shareActivity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let vc = UIApplication.shared.keyWindow?.rootViewController {
            shareActivity.popoverPresentationController?.sourceView = vc.view
            shareActivity.popoverPresentationController?.sourceRect = CGRect(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height, width: 0, height: 0)
            shareActivity.popoverPresentationController?.permittedArrowDirections = UIPopoverArrowDirection.down
            DispatchQueue.main.async {
                vc.present(shareActivity, animated: true, completion: {
                })
            }
        }
    }
    
    func alert(_ message: String) {
        alertMessage = message
        showingAlert.toggle()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

