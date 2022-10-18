//
//  DebToIPA.swift
//  deb-to-ipa-app
//
//  Created by exerhythm on 14.10.2022.
//

import ArArchiveKit
import Zip
import SWCompression
import UIKit

class DebToIPA {
    private static let fm = FileManager.default
    private static var tempDir: URL { fm.temporaryDirectory }
    
    /// Converts .deb app to .ipa, returns url of .ipa
    static func convert(_ url: URL, statusUpdate: (String) -> ()) throws -> SavedIpa {
        try cleanup()
        var savedIpa = SavedIpa(name: "IPA", bundleID: "Bundle ID unknown", version: "Unknown version", url: nil)
        let payloadDir = tempDir.appendingPathComponent("Payload")
        
        // Extract .deb
        let appURLs = try fm.contentsOfDirectory(at: try extractDeb(url, to: tempDir.appendingPathComponent("deb_extracted"), statusUpdate: statusUpdate).appendingPathComponent("Applications/"), includingPropertiesForKeys: nil)
        guard fm.fileExists(atPath: tempDir.appendingPathComponent("deb_extracted/Applications/").path) else { throw ConversionError.unsupportedApp }
        
        statusUpdate("Creating .ipa archive")
        // Create .ipa archive
        try fm.createDirectory(at: payloadDir, withIntermediateDirectories: true)
        for url in appURLs {
            if let infoPlist = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")) {
                savedIpa.name = (infoPlist["CFBundleDisplayName"] ?? infoPlist["CFBundleName"]) as? String ?? "Unknown"
                savedIpa.version = infoPlist["CFBundleVersion"] as? String ?? "Unknown"
                savedIpa.bundleID = infoPlist["CFBundleIdentifier"] as? String ?? "Unknown"
//                if let iconFiles = (infoPlist["CFBundleIconFiles"] ?? infoPlist["CFBundleIcons~ipad"]) as? [String], let name = iconFiles.first {
//                    savedIpa.image = try Data(contentsOf: url.appendingPathComponent(name))
//                }
            }
            
            try fm.moveItem(at: url, to: payloadDir.appendingPathComponent( url.lastPathComponent))
        }
        
        // Create archive of ipa folder
        statusUpdate("Zipping app")
        let zipFilePath = try Zip.quickZipFiles([payloadDir], fileName: url.deletingPathExtension().lastPathComponent) // Zip
        
        // Rename
        statusUpdate("Renaming .zip to .ipa")
        let destIpaURL = zipFilePath.deletingPathExtension().appendingPathExtension("ipa")
        try? fm.removeItem(at: destIpaURL)
        try fm.moveItem(at: zipFilePath, to: destIpaURL)
        
        statusUpdate("Opening share sheet...")
        savedIpa.url = destIpaURL
        return savedIpa
    }
    
    
    /// Extracts deb and returns .app urls
    static func extractDeb(_ url: URL, to extractedDir: URL, statusUpdate: (String) -> ()) throws -> URL {
        statusUpdate("Reading .deb")
        let reader = try ArArchiveReader(archive: Array<UInt8>(Data(contentsOf: url)))
        var foundData = false
        for (header, dataInts) in reader {
            guard header.name.contains("data.tar") else { continue }
            let dataURL = tempDir.appendingPathComponent(header.name)
            
            // Write data to disk
            statusUpdate("Creating data from ints")
            let data = Data(dataInts)
            try data.write(to: dataURL, options: .atomic)
            
            statusUpdate("Decompressing data archive")
            let decompressedData: Data?
            switch DecompressionMethod(rawValue: header.name.components(separatedBy: ".").last ?? "") {
            case .lzma:
                foundData = true
                statusUpdate("Decompressing LZMA data.\nThis might take a while")
                decompressedData = try LZMA.decompress(data: data)
            case .gz:
                foundData = true
                statusUpdate("Unarchiving Gzip archive.\nThis might take a while")
                decompressedData = try GzipArchive.unarchive(archive:data)
            case .bzip2:
                foundData = true
                statusUpdate("Decompressing BZip2 data.\nThis might take a while")
                decompressedData = try BZip2.decompress(data:data)
            case .xz:
                foundData = true
                statusUpdate("Unarchiving XZ archive.\nThis might take a while")
                decompressedData = try XZArchive.unarchive(archive:data)
            case .none:
                throw ConversionError.unsupportedCompression
            }
            
            statusUpdate("Opening .tar")
            try decompressedData!.write(to: extractedDir.appendingPathExtension("tar"))
            let tarContainer = try TarContainer.open(container: decompressedData!)
            
            statusUpdate("Creating files")
            for entry in tarContainer {
                if entry.info.type == .directory {
                    try fm.createDirectory(at: extractedDir.appendingPathComponent(entry.info.name), withIntermediateDirectories: true)
                } else if entry.info.type == .regular {
                    try entry.data?.write(to: extractedDir.appendingPathComponent(entry.info.name))
                } else if entry.info.type == .symbolicLink {
                    try fm.createSymbolicLink(at: extractedDir.appendingPathComponent(entry.info.name), withDestinationURL: URL(fileURLWithPath: entry.info.linkName))
                } else {
                    throw ConversionError.unknownFiletypeInsideTar
                }
                print(entry.info)
            }
        }
        
        if !foundData {
            throw ConversionError.noDataFound
        }
        return extractedDir
    }
    
    static func cleanup() throws {
        for url in try fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            try fm.removeItem(at: url)
        }
    }
}

enum DecompressionMethod: String {
    case gz, lzma, bzip2, xz
}

enum ConversionError: Error {
    case noDataFound
    case noPermission
    case unknownFiletypeInsideTar
    case noApplication
    case unsupportedApp
    case unsupportedCompression
}
