//
//  ResidentQRGenerator.swift
//  SecurityIslas
//
//  Mi QR (RF-15): cambia cada 30 s y se genera sin internet con HMAC tipo
//  TOTP. El secreto lo entrega el backend y se guarda en el Keychain.
//  Algoritmo, periodo y formato del payload son supuestos (DECISIONES.md).
//

import CryptoKit
import Foundation
#if os(iOS)
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
#endif

nonisolated enum TOTP {
    static func code(secret: Data, date: Date = .now, period: Int = 30, digits: Int = 8) -> String {
        let counter = UInt64(date.timeIntervalSince1970) / UInt64(period)
        var bigEndian = counter.bigEndian
        let message = Data(bytes: &bigEndian, count: MemoryLayout<UInt64>.size)
        let mac = Array(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: secret)))

        let offset = Int(mac[mac.count - 1] & 0x0f)
        let truncated = (UInt32(mac[offset] & 0x7f) << 24)
            | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8)
            | UInt32(mac[offset + 3])
        var modulus: UInt32 = 1
        for _ in 0..<digits { modulus *= 10 }
        let value = truncated % modulus
        return String(format: "%0\(digits)u", value)
    }

    static func secondsRemaining(date: Date = .now, period: Int = 30) -> Int {
        period - Int(date.timeIntervalSince1970) % period
    }
}

#if os(iOS)
/// En el iPhone el QR se dibuja con CoreImage. watchOS no tiene CoreImage:
/// el reloj usa su propio codificador (`QRCodeMatrix`).
enum QRCodeRenderer {
    static func image(for payload: String, scale: CGFloat = 12) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else {
            return nil
        }
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
#endif

/// Obtiene (y cachea) la semilla del QR y arma el payload vigente.
final class ResidentQRGenerator {
    private let repository: GateRepository
    private let keychain: KeychainStore
    private let key = "resident.qr.seed"

    init(repository: GateRepository, keychain: KeychainStore) {
        self.repository = repository
        self.keychain = keychain
    }

    var cachedSeed: QRSeed? {
        keychain.value(QRSeed.self, for: key)
    }

    /// Usa la semilla guardada; si no hay, la pide al backend.
    func seed() async throws -> QRSeed {
        if let cachedSeed { return cachedSeed }
        let seed = try await repository.qrSeed()
        try? keychain.setValue(seed, for: key)
        return seed
    }

    func payload(userId: String, seed: QRSeed, date: Date = .now) -> String {
        let secret = Data(base64Encoded: seed.secret) ?? Data()
        let code = TOTP.code(secret: secret, date: date, period: seed.period, digits: seed.digits)
        return "ACC1.\(userId).\(code)"
    }

    func clear() {
        keychain.delete(key)
    }
}
