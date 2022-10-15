//
//  DebToIPA.swift
//  deb-to-ipa-app
//
//  Created by exerhythm on 14.10.2022.
//

import Foundation
import ArArchiveKit
import Zip
import SWCompression

class DebToIPA {
    private static let fm = FileManager.default
    private static var tempDir: URL { fm.temporaryDirectory }
    
    /// Converts .deb app to .ipa, returns url of .ipa
    static func convert(_ url: URL, statusUpdate: (String) -> ()) throws -> URL {
        try cleanup()
        let payloadDir = tempDir.appendingPathComponent("Payload")
        
        // Extract .deb
        let appURLs = try extractDeb(url, statusUpdate: statusUpdate)
        
        statusUpdate("Creating .ipa archive")
        // Create .ipa archive
        try fm.createDirectory(at: payloadDir, withIntermediateDirectories: true)
        for url in appURLs {
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
        
        statusUpdate("Done.")
        return zipFilePath.deletingPathExtension().appendingPathExtension("ipa")
    }
    
    
    /// Extracts deb and returns .app urls
    static func extractDeb(_ url: URL, statusUpdate: (String) -> ()) throws -> [URL] {
        let extractedDir = tempDir.appendingPathComponent("extracted")
        let appsDir = tempDir.appendingPathComponent( "extracted/Applications/")
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
                statusUpdate("Using LZMA")
                decompressedData = try LZMA.decompress(data: data)
            case .gz:
                foundData = true
                statusUpdate("Using GzipArchive")
                decompressedData = try GzipArchive.unarchive(archive:data)
            case .bzip2:
                foundData = true
                statusUpdate("Using BZip2")
                decompressedData = try BZip2.decompress(data:data)
            case .xz:
                foundData = true
                statusUpdate("Using XZArchive")
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
                } else {
                    throw ConversionError.unknownFiletypeInsideTar
                }
                print(entry.info)
            }
            guard fm.fileExists(atPath: appsDir.path) else { throw ConversionError.unsupportedApp }
        }
        
        if !foundData {
            throw ConversionError.noDataFound
        }
        return try fm.contentsOfDirectory(at: appsDir, includingPropertiesForKeys: nil)
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
