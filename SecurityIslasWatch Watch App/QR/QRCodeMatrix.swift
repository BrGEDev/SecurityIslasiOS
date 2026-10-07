//
//  QRCodeMatrix.swift
//  SecurityIslasWatch Watch App
//
//  watchOS no tiene CoreImage, así que el reloj arma el QR él mismo (sin
//  internet, RF-15). Codificador mínimo de la norma ISO/IEC 18004: modo byte,
//  corrección M y versiones 1 a 10 (hasta 213 bytes), de sobra para el payload
//  `ACC1.<userId>.<código>`. Basado en el algoritmo de referencia de Project
//  Nayuki (licencia MIT).
//

import Foundation

nonisolated struct QRCodeMatrix: Sendable {
    let size: Int
    private var modules: [Bool]
    private var isFunction: [Bool]

    /// Nivel de corrección M (~15 %). Índice = versión.
    private static let eccCodewordsPerBlock = [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26]
    private static let errorCorrectionBlocks = [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5]
    /// Bits de formato del nivel M.
    private static let eccFormatBits = 0
    static let maxVersion = 10

    /// `mask` fijo solo para pruebas; por omisión se elige el de menor penalización.
    init?(text: String, mask fixedMask: Int? = nil) {
        let data = Array(text.utf8)

        var version = 1
        while true {
            let capacityBits = Self.dataCodewords(version: version) * 8
            let countBits = version <= 9 ? 8 : 16
            if 4 + countBits + data.count * 8 <= capacityBits { break }
            version += 1
            if version > Self.maxVersion { return nil }
        }

        // Segmento en modo byte + terminador + relleno.
        let capacityBits = Self.dataCodewords(version: version) * 8
        var bits: [Bool] = []
        func append(_ value: Int, _ length: Int) {
            for i in stride(from: length - 1, through: 0, by: -1) {
                bits.append((value >> i) & 1 == 1)
            }
        }
        append(0x4, 4)
        append(data.count, version <= 9 ? 8 : 16)
        for byte in data { append(Int(byte), 8) }
        append(0, min(4, capacityBits - bits.count))
        append(0, (8 - bits.count % 8) % 8)
        var padByte = 0xEC
        while bits.count < capacityBits {
            append(padByte, 8)
            padByte ^= 0xEC ^ 0x11
        }
        var codewords = [UInt8](repeating: 0, count: bits.count / 8)
        for (index, bit) in bits.enumerated() where bit {
            codewords[index >> 3] |= UInt8(1 << (7 - (index & 7)))
        }

        size = version * 4 + 17
        modules = Array(repeating: false, count: size * size)
        isFunction = Array(repeating: false, count: size * size)

        drawFunctionPatterns(version: version)
        drawCodewords(Self.addErrorCorrection(codewords, version: version))

        var bestMask = fixedMask ?? 0
        if fixedMask == nil {
            var lowestPenalty = Int.max
            for mask in 0..<8 {
                applyMask(mask)
                drawFormatBits(mask: mask)
                let penalty = penaltyScore()
                if penalty < lowestPenalty {
                    bestMask = mask
                    lowestPenalty = penalty
                }
                applyMask(mask) // XOR: deshace la máscara
            }
        }
        applyMask(bestMask)
        drawFormatBits(mask: bestMask)
    }

    func isDark(x: Int, y: Int) -> Bool {
        modules[y * size + x]
    }

    // MARK: - Patrones fijos

    private mutating func drawFunctionPatterns(version: Int) {
        for i in 0..<size {
            setFunction(x: 6, y: i, dark: i % 2 == 0)
            setFunction(x: i, y: 6, dark: i % 2 == 0)
        }
        drawFinder(x: 3, y: 3)
        drawFinder(x: size - 4, y: 3)
        drawFinder(x: 3, y: size - 4)

        let positions = Self.alignmentPositions(version: version, size: size)
        let count = positions.count
        for i in 0..<count {
            for j in 0..<count {
                let overlapsFinder = (i == 0 && j == 0) || (i == 0 && j == count - 1) || (i == count - 1 && j == 0)
                if !overlapsFinder {
                    drawAlignment(x: positions[i], y: positions[j])
                }
            }
        }

        drawFormatBits(mask: 0) // reserva el área; se reescribe con la máscara final
        drawVersion(version)
    }

    private mutating func drawFinder(x: Int, y: Int) {
        for dy in -4...4 {
            for dx in -4...4 {
                let distance = max(abs(dx), abs(dy))
                let xx = x + dx
                let yy = y + dy
                if (0..<size).contains(xx), (0..<size).contains(yy) {
                    setFunction(x: xx, y: yy, dark: distance != 2 && distance != 4)
                }
            }
        }
    }

    private mutating func drawAlignment(x: Int, y: Int) {
        for dy in -2...2 {
            for dx in -2...2 {
                setFunction(x: x + dx, y: y + dy, dark: max(abs(dx), abs(dy)) != 1)
            }
        }
    }

    private mutating func drawFormatBits(mask: Int) {
        let data = Self.eccFormatBits << 3 | mask
        var remainder = data
        for _ in 0..<10 {
            remainder = (remainder << 1) ^ ((remainder >> 9) * 0x537)
        }
        let bits = (data << 10 | remainder) ^ 0x5412

        for i in 0...5 { setFunction(x: 8, y: i, dark: Self.bit(bits, i)) }
        setFunction(x: 8, y: 7, dark: Self.bit(bits, 6))
        setFunction(x: 8, y: 8, dark: Self.bit(bits, 7))
        setFunction(x: 7, y: 8, dark: Self.bit(bits, 8))
        for i in 9..<15 { setFunction(x: 14 - i, y: 8, dark: Self.bit(bits, i)) }

        for i in 0..<8 { setFunction(x: size - 1 - i, y: 8, dark: Self.bit(bits, i)) }
        for i in 8..<15 { setFunction(x: 8, y: size - 15 + i, dark: Self.bit(bits, i)) }
        setFunction(x: 8, y: size - 8, dark: true)
    }

    private mutating func drawVersion(_ version: Int) {
        guard version >= 7 else { return }
        var remainder = version
        for _ in 0..<12 {
            remainder = (remainder << 1) ^ ((remainder >> 11) * 0x1F25)
        }
        let bits = version << 12 | remainder
        for i in 0..<18 {
            let dark = Self.bit(bits, i)
            let a = size - 11 + i % 3
            let b = i / 3
            setFunction(x: a, y: b, dark: dark)
            setFunction(x: b, y: a, dark: dark)
        }
    }

    private mutating func setFunction(x: Int, y: Int, dark: Bool) {
        modules[y * size + x] = dark
        isFunction[y * size + x] = true
    }

    // MARK: - Datos

    private mutating func drawCodewords(_ data: [UInt8]) {
        var index = 0
        var right = size - 1
        while right >= 1 {
            if right == 6 { right = 5 }
            for vertical in 0..<size {
                for j in 0..<2 {
                    let x = right - j
                    let upward = (right + 1) & 2 == 0
                    let y = upward ? size - 1 - vertical : vertical
                    if !isFunction[y * size + x], index < data.count * 8 {
                        modules[y * size + x] = Self.bit(Int(data[index >> 3]), 7 - (index & 7))
                        index += 1
                    }
                }
            }
            right -= 2
        }
    }

    private mutating func applyMask(_ mask: Int) {
        for y in 0..<size {
            for x in 0..<size where !isFunction[y * size + x] {
                let invert: Bool
                switch mask {
                case 0: invert = (x + y) % 2 == 0
                case 1: invert = y % 2 == 0
                case 2: invert = x % 3 == 0
                case 3: invert = (x + y) % 3 == 0
                case 4: invert = (x / 3 + y / 2) % 2 == 0
                case 5: invert = x * y % 2 + x * y % 3 == 0
                case 6: invert = (x * y % 2 + x * y % 3) % 2 == 0
                default: invert = ((x + y) % 2 + x * y % 3) % 2 == 0
                }
                if invert {
                    modules[y * size + x].toggle()
                }
            }
        }
    }

    /// Reglas de penalización de la norma: rachas, bloques 2×2, patrones
    /// parecidos al buscador y balance de oscuros.
    private func penaltyScore() -> Int {
        var penalty = 0

        func runPenalty(_ line: [Bool]) -> Int {
            var result = 0
            var runLength = 1
            for i in 1..<line.count {
                if line[i] == line[i - 1] {
                    runLength += 1
                } else {
                    if runLength >= 5 { result += runLength - 2 }
                    runLength = 1
                }
            }
            if runLength >= 5 { result += runLength - 2 }
            return result
        }

        let finderLike: [Bool] = [true, false, true, true, true, false, true, false, false, false, false]
        let finderLikeReversed: [Bool] = finderLike.reversed()
        func finderPenalty(_ line: [Bool]) -> Int {
            guard line.count >= finderLike.count else { return 0 }
            var result = 0
            for start in 0...(line.count - finderLike.count) {
                let window = Array(line[start..<(start + finderLike.count)])
                if window == finderLike || window == finderLikeReversed { result += 40 }
            }
            return result
        }

        for y in 0..<size {
            let row = (0..<size).map { isDark(x: $0, y: y) }
            penalty += runPenalty(row) + finderPenalty(row)
        }
        for x in 0..<size {
            let column = (0..<size).map { isDark(x: x, y: $0) }
            penalty += runPenalty(column) + finderPenalty(column)
        }

        for y in 0..<(size - 1) {
            for x in 0..<(size - 1) {
                let color = isDark(x: x, y: y)
                if color == isDark(x: x + 1, y: y),
                   color == isDark(x: x, y: y + 1),
                   color == isDark(x: x + 1, y: y + 1) {
                    penalty += 3
                }
            }
        }

        let dark = modules.reduce(0) { $0 + ($1 ? 1 : 0) }
        let total = size * size
        let k = (abs(dark * 20 - total * 10) + total - 1) / total - 1
        penalty += max(0, k) * 10
        return penalty
    }

    // MARK: - Corrección de errores (Reed-Solomon)

    private static func rawDataModules(version: Int) -> Int {
        var result = (16 * version + 128) * version + 64
        if version >= 2 {
            let alignments = version / 7 + 2
            result -= (25 * alignments - 10) * alignments - 55
            if version >= 7 { result -= 36 }
        }
        return result
    }

    private static func dataCodewords(version: Int) -> Int {
        rawDataModules(version: version) / 8
            - eccCodewordsPerBlock[version] * errorCorrectionBlocks[version]
    }

    private static func alignmentPositions(version: Int, size: Int) -> [Int] {
        guard version >= 2 else { return [] }
        let count = version / 7 + 2
        let step = (version * 8 + count * 3 + 5) / (count * 4 - 4) * 2
        var result = [6]
        var position = size - 7
        for _ in 0..<(count - 1) {
            result.insert(position, at: 1)
            position -= step
        }
        return result
    }

    private static func addErrorCorrection(_ data: [UInt8], version: Int) -> [UInt8] {
        let blockCount = errorCorrectionBlocks[version]
        let eccLength = eccCodewordsPerBlock[version]
        let rawCodewords = rawDataModules(version: version) / 8
        let shortBlocks = blockCount - rawCodewords % blockCount
        let shortBlockLength = rawCodewords / blockCount
        let divisor = reedSolomonDivisor(degree: eccLength)

        var blocks: [[UInt8]] = []
        var offset = 0
        for i in 0..<blockCount {
            let length = shortBlockLength - eccLength + (i < shortBlocks ? 0 : 1)
            var block = Array(data[offset..<(offset + length)])
            offset += length
            let ecc = reedSolomonRemainder(block, divisor: divisor)
            if i < shortBlocks { block.append(0) }
            blocks.append(block + ecc)
        }

        var result: [UInt8] = []
        for i in 0..<blocks[0].count {
            for (j, block) in blocks.enumerated() where i != shortBlockLength - eccLength || j >= shortBlocks {
                result.append(block[i])
            }
        }
        return result
    }

    private static func reedSolomonDivisor(degree: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: degree)
        result[degree - 1] = 1
        var root: UInt8 = 1
        for _ in 0..<degree {
            for j in 0..<degree {
                result[j] = multiply(result[j], root)
                if j + 1 < degree {
                    result[j] ^= result[j + 1]
                }
            }
            root = multiply(root, 0x02)
        }
        return result
    }

    private static func reedSolomonRemainder(_ data: [UInt8], divisor: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: divisor.count)
        for byte in data {
            let factor = byte ^ result.removeFirst()
            result.append(0)
            for i in 0..<result.count {
                result[i] ^= multiply(divisor[i], factor)
            }
        }
        return result
    }

    private static func multiply(_ x: UInt8, _ y: UInt8) -> UInt8 {
        var z = 0
        for i in stride(from: 7, through: 0, by: -1) {
            z = (z << 1) ^ ((z >> 7) * 0x11D)
            z ^= ((Int(y) >> i) & 1) * Int(x)
        }
        return UInt8(z)
    }

    private static func bit(_ value: Int, _ index: Int) -> Bool {
        (value >> index) & 1 != 0
    }
}
