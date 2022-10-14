//
//  ContentView.swift
//  deb-to-ipa-app
//
//  Created by exerhythm on 13.10.2022.
//

import SwiftUI
import ArArchiveKit
import Gzip
import Light_Swift_Untar
import Zip

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
                Text("By sourcelocation\n\nCredits: itsnebulalol,\n LebJe/ArArchiveKit, \n1024jp/GzipSwift,\nmarmelroy/Zip,\nUInt2048/Light-Swift-Untar")
                    .foregroundColor(Color.secondary)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                
            }
            .navigationTitle("deb-to-ipa")
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
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
        let extractedDir = tempDir.appendingPathComponent("extracted")
        let ipaPayloadDir = tempDir.appendingPathComponent("Payload")
        let dataURL = tempDir.appendingPathComponent("deb.tar.gz")
        var zipFilePath: URL?
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
            
            do {
                guard url.startAccessingSecurityScopedResource() else { throw ConversionError.noPermission }
                let reader = try ArArchiveReader(archive: Array<UInt8>(Data(contentsOf: url)))
                
                // Extract .deb
                var foundData = false
                for (header, dataInts) in reader {
                    if header.name == "data.tar.gz" {
                        // Extract data.tar.gz
                        let data = Data(dataInts)
                        try data.write(to: dataURL, options: .atomic)
                        foundData = true
                        let decompressedData = try data.gunzipped()
                        try fm.createFilesAndDirectories(url: extractedDir, tarData: decompressedData)
                        
                        // Create .ipa archive
                        try fm.createDirectory(at: ipaPayloadDir, withIntermediateDirectories: true)
                        
                        // Copy apps to the archive
                        for url in try fm.contentsOfDirectory(at: tempDir.appendingPathComponent( "extracted/Applications/"), includingPropertiesForKeys: nil) {
                            try fm.moveItem(at: url, to: ipaPayloadDir.appendingPathComponent( url.lastPathComponent))
                        }
                        
                        // Create archive of ipa folder
                        zipFilePath = try Zip.quickZipFiles([ipaPayloadDir], fileName: url.deletingPathExtension().lastPathComponent) // Zip
                        
                        // Rename
                        let destIpaURL = zipFilePath!.deletingPathExtension().appendingPathExtension("ipa")
                        try? fm.removeItem(at: destIpaURL)
                        try fm.moveItem(at: zipFilePath!, to: destIpaURL)
                        
                        let shareActivity = UIActivityViewController(activityItems: [zipFilePath!.deletingPathExtension().appendingPathExtension("ipa")], applicationActivities: nil)
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
                }
                
                if !foundData {
                    throw ConversionError.noDataFound
                }
            } catch let error {
                alert(error.localizedDescription)
            }
            url.stopAccessingSecurityScopedResource()
            // clean up
            try? fm.removeItem(at: dataURL)
            try? fm.removeItem(at: extractedDir)
            try? fm.removeItem(at: ipaPayloadDir)
            if zipFilePath != nil {
                try? fm.removeItem(at: zipFilePath!)
            }
            
            converting = false
        })
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


enum ConversionError: Error {
    case noDataFound
    case noPermission
}
