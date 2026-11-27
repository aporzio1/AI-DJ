import Foundation

/// Swift port of edge-tts' `drm.py` Sec-MS-GEC token generator. The Microsoft
/// readaloud endpoint rejects WebSocket handshakes without this token; the
/// hash is a salted, schedule-patched SHA-256 — NOT CryptoKit's SHA256.
enum EdgeDRM {
    static let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    static let gecVersion = "2-143.0.3650.75"

    static func secMsGEC(unixTimestamp: Double) -> String {
        var ticks = unixTimestamp + 11_644_473_600
        ticks -= ticks.truncatingRemainder(dividingBy: 300)
        let tickInt = UInt64(ticks * 10_000_000)
        return token(payload: Array("\(tickInt)\(trustedClientToken)".utf8))
    }

    // MARK: - patched SHA-256 constants
    private static let k: [UInt32] = [
        0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1,
        0x923F82A4, 0xAB1C5ED5, 0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
        0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174, 0xE49B69C1, 0xEFBE4786,
        0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
        0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147,
        0x06CA6351, 0x14292967, 0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
        0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85, 0xA2BFE8A1, 0xA81A664B,
        0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
        0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A,
        0x5B9CCA4F, 0x682E6FF3, 0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
        0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
    ]
    private static var kBlock: [UInt32] { var kb = k; kb[14] = 0xC9DC06A7; return kb }
    private static let schedule: [UInt32] = [
        0xEB24BF9E, 0x1558691F, 0xA0C09EE2, 0x0CFA32BA, 0xA622EE8C, 0xD1DD9491,
        0xC0DD25A0, 0xF9E70AB6, 0xF0C31573, 0x7058CE4E, 0x7188E606, 0x00E5AB33,
        0xD258B060, 0x72766564,
    ]
    private static let sigma0Adj: UInt32 = 0x059C0B80
    private static let sigma1Adj: UInt32 = 0x000B92C0
    private static let initial: [UInt32] = [
        0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
        0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
    ]
    private static let state0: [UInt32] = [
        0xFD9FBEA2, 0x91243CE7, 0xBE499094, 0xCD2E1E0A,
        0x6C006F49, 0x04BD35AB, 0xFEB0A7E4, 0x03EFFBD2,
    ]
    private static let coefficients: [(UInt32, UInt32)] = [
        (0xE82E91B1, 0xB32700D0), (0x44DE24C6, 0x88DFF51D), (0x3BEB65BC, 0x29514038),
        (0xC89C5933, 0xB328CBDF), (0x8D1EC211, 0xD405B4D5), (0x314EF5D5, 0x26E55F3C),
        (0xE92491B1, 0x607801C6), (0xF0A5B9D5, 0x82B2C1FB), (0x06064CF3, 0xFA51A3DA),
        (0xDA79FA60, 0x207CC464), (0xBED20560, 0x3C3C74F3), (0x89F9C9F8, 0xD2D14B61),
        (0x35FA38C6, 0xBB04A2C1), (0xCB49E3C6, 0xC5626167),
    ]

    private static func rol16(_ v: UInt32) -> UInt32 { (v << 16) | (v >> 16) }
    private static func sigma0(_ v: UInt32) -> UInt32 {
        (v >> 7) ^ (v << 25) ^ (v >> 18) ^ (v << 14) ^ (v >> 3)
    }
    private static func sigma1(_ v: UInt32) -> UInt32 {
        (v >> 17) ^ (v << 15) ^ (v >> 19) ^ (v << 13) ^ (v >> 10)
    }
    private static func be32(_ b: [UInt8], _ off: Int) -> UInt32 {
        (UInt32(b[off]) << 24) | (UInt32(b[off + 1]) << 16) | (UInt32(b[off + 2]) << 8) | UInt32(b[off + 3])
    }
    private static func le32(_ b: [UInt8], _ off: Int) -> UInt32 {
        UInt32(b[off]) | (UInt32(b[off + 1]) << 8) | (UInt32(b[off + 2]) << 16) | (UInt32(b[off + 3]) << 24)
    }

    private static func expandSchedule(_ words: inout [UInt32], _ firstWord: Int) {
        for index in firstWord..<64 {
            let x = UInt64(words[index - 2]), y = UInt64(words[index - 15])
            let s1 = (x >> 17) ^ (x << 15) ^ (x >> 19) ^ (x << 13) ^ (x >> 10)
            let s0 = (y >> 7) ^ (y << 25) ^ (y >> 18) ^ (y << 14) ^ (y >> 3)
            words.append(UInt32(truncatingIfNeeded:
                s1 &+ UInt64(words[index - 7]) &+ s0 &+ UInt64(words[index - 16])))
        }
    }

    internal static func dbgR14(_ state: [UInt32], _ words: [UInt32]) -> [UInt32] {
        let words = words
        var a=state[0],b=state[1],c=state[2],d=state[3],e=state[4],f=state[5],g=state[6],h=state[7]
        let constants = kBlock
        let rotE = UInt64(e) &* 0x1_0000_0001, rotA = UInt64(a) &* 0x1_0000_0001
        let t1 = UInt64(h) &+ ((rotE >> 6) ^ (rotE >> 11) ^ (rotE >> 25))
               &+ UInt64(g ^ (e & (f ^ g))) &+ UInt64(constants[14]) &+ UInt64(words[14])
        let t2 = ((rotA >> 2) ^ (rotA >> 13) ^ (rotA >> 22)) &+ UInt64((a & b) | (c & (a | b)))
        let na = UInt32(truncatingIfNeeded: t1 &+ t2)
        let ne = UInt32(truncatingIfNeeded: UInt64(d) &+ t1)
        return [na,a,b,c,ne,e,f,g,h]
    }

    
    internal static func dbgRoundsHead2(_ state: [UInt32], _ words: [UInt32]) -> [UInt32] {
        var a=state[0],b=state[1],c=state[2],d=state[3],e=state[4],f=state[5],g=state[6],h=state[7]
        for index in 14..<16 {
            let rotE = UInt64(e) &* 0x1_0000_0001, rotA = UInt64(a) &* 0x1_0000_0001
            let t1 = UInt64(h) &+ ((rotE >> 6) ^ (rotE >> 11) ^ (rotE >> 25))
                   &+ UInt64(g ^ (e & (f ^ g))) &+ UInt64(kBlock[index]) &+ UInt64(words[index])
            let t2 = ((rotA >> 2) ^ (rotA >> 13) ^ (rotA >> 22)) &+ UInt64((a & b) | (c & (a | b)))
            let na = UInt32(truncatingIfNeeded: t1 &+ t2)
            let ne = UInt32(truncatingIfNeeded: UInt64(d) &+ t1)
            let (oa, ob, oc, oe, of, og) = (a, b, c, e, f, g)
            a = na; b = oa; c = ob; d = oc; e = ne; f = oe; g = of; h = og
        }
        return [a,b,c,d,e,f,g,h]
    }

internal static func dbgRounds(_ state: [UInt32], _ words: [UInt32], _ firstRound: Int) -> [UInt32] {
        var a = state[0], b = state[1], c = state[2], d = state[3]
        var e = state[4], f = state[5], g = state[6], h = state[7]
        let constants = firstRound == 14 ? kBlock : k
        let aligned = min(64, ((firstRound + 7) / 8) * 8)
        var index = firstRound
        while index < aligned {   // head rounds; only non-empty on the init path
            let rotE = UInt64(e) &* 0x1_0000_0001, rotA = UInt64(a) &* 0x1_0000_0001
            let t1 = UInt64(h) &+ ((rotE >> 6) ^ (rotE >> 11) ^ (rotE >> 25))
                   &+ UInt64(g ^ (e & (f ^ g))) &+ UInt64(constants[index]) &+ UInt64(words[index])
            let t2 = ((rotA >> 2) ^ (rotA >> 13) ^ (rotA >> 22))
                   &+ UInt64((a & b) | (c & (a | b)))
            let na = UInt32(truncatingIfNeeded: t1 &+ t2)
            let ne = UInt32(truncatingIfNeeded: UInt64(d) &+ t1)
            let (oa, ob, oc, oe, of, og) = (a, b, c, e, f, g)
            a = na; b = oa; c = ob; d = oc; e = ne; f = oe; g = of; h = og
            index += 1
        }
        while index < 64 {
            var rotE = UInt64(e) &* 0x1_0000_0001, rotA = UInt64(a) &* 0x1_0000_0001
            var t1 = UInt64(h) &+ ((rotE >> 6) ^ (rotE >> 11) ^ (rotE >> 25))
                   &+ UInt64(g ^ (e & (f ^ g))) &+ UInt64(constants[index]) &+ UInt64(words[index])
            var t2 = ((rotA >> 2) ^ (rotA >> 13) ^ (rotA >> 22)) &+ UInt64((a & b) | (c & (a | b)))
            d = UInt32(truncatingIfNeeded: UInt64(d) &+ t1)
            h = UInt32(truncatingIfNeeded: t1 &+ t2)
            rotE = UInt64(d) &* 0x1_0000_0001; rotA = UInt64(h) &* 0x1_0000_0001
            t1 = UInt64(g) &+ ((rotE >> 6) ^ (rotE >> 11) ^ (rotE >> 25))
               &+ UInt64(f ^ (d & (e ^ f))) &+ UInt64(constants[index + 1]) &+ UInt64(words[index + 1])
            t2 = ((rotA >> 2) ^ (rotA >> 13) ^ (rotA >> 22)) &+ UInt64((h & a) | (b & (h | a)))
            c = UInt32(truncatingIfNeeded: UInt64(c) &+ t1)
            g = UInt32(truncatingIfNeeded: t1 &+ t2)
            rotE = UInt64(c) &* 0x1_0000_0001; rotA = UInt64(g) &* 0x1_0000_0001
            t1 = UInt64(f) &+ ((rotE >> 6) ^ (rotE >> 11) ^ (rotE >> 25))
               &+ UInt64(e ^ (c & (d ^ e))) &+ UInt64(constants[index + 2]) &+ UInt64(words[index + 2])
            t2 = ((rotA >> 2) ^ (rotA >> 13) ^ (rotA >> 22)) &+ UInt64((g & h) | (a & (g | h)))
            b = UInt32(truncatingIfNeeded: UInt64(b) &+ t1)
            f = UInt32(truncatingIfNeeded: t1 &+ t2)
            rotE = UInt64(b) &* 0x1_0000_0001; rotA = UInt64(f) &* 0x1_0000_0001
            t1 = UInt64(e) &+ ((rotE >> 6) ^ (rotE >> 11) ^ (rotE >> 25))
               &+ UInt64(d ^ (b & (c ^ d))) &+ UInt64(constants[index + 3]) &+ UInt64(words[index + 3])
            t2 = ((rotA >> 2) ^ (rotA >> 13) ^ (rotA >> 22)) &+ UInt64((f & g) | (h & (f | g)))
            a = UInt32(truncatingIfNeeded: UInt64(a) &+ t1)
            e = UInt32(truncatingIfNeeded: t1 &+ t2)
            rotE = UInt64(a) &* 0x1_0000_0001; rotA = UInt64(e) &* 0x1_0000_0001
            t1 = UInt64(d) &+ ((rotE >> 6) ^ (rotE >> 11) ^ (rotE >> 25))
               &+ UInt64(c ^ (a & (b ^ c))) &+ UInt64(constants[index + 4]) &+ UInt64(words[index + 4])
            t2 = ((rotA >> 2) ^ (rotA >> 13) ^ (rotA >> 22)) &+ UInt64((e & f) | (g & (e | f)))
            h = UInt32(truncatingIfNeeded: UInt64(h) &+ t1)
            d = UInt32(truncatingIfNeeded: t1 &+ t2)
            rotE = UInt64(h) &* 0x1_0000_0001; rotA = UInt64(d) &* 0x1_0000_0001
            t1 = UInt64(c) &+ ((rotE >> 6) ^ (rotE >> 11) ^ (rotE >> 25))
               &+ UInt64(b ^ (h & (a ^ b))) &+ UInt64(constants[index + 5]) &+ UInt64(words[index + 5])
            t2 = ((rotA >> 2) ^ (rotA >> 13) ^ (rotA >> 22)) &+ UInt64((d & e) | (f & (d | e)))
            g = UInt32(truncatingIfNeeded: UInt64(g) &+ t1)
            c = UInt32(truncatingIfNeeded: t1 &+ t2)
            rotE = UInt64(g) &* 0x1_0000_0001; rotA = UInt64(c) &* 0x1_0000_0001
            t1 = UInt64(b) &+ ((rotE >> 6) ^ (rotE >> 11) ^ (rotE >> 25))
               &+ UInt64(a ^ (g & (h ^ a))) &+ UInt64(constants[index + 6]) &+ UInt64(words[index + 6])
            t2 = ((rotA >> 2) ^ (rotA >> 13) ^ (rotA >> 22)) &+ UInt64((c & d) | (e & (c | d)))
            f = UInt32(truncatingIfNeeded: UInt64(f) &+ t1)
            b = UInt32(truncatingIfNeeded: t1 &+ t2)
            rotE = UInt64(f) &* 0x1_0000_0001; rotA = UInt64(b) &* 0x1_0000_0001
            t1 = UInt64(a) &+ ((rotE >> 6) ^ (rotE >> 11) ^ (rotE >> 25))
               &+ UInt64(h ^ (f & (g ^ h))) &+ UInt64(constants[index + 7]) &+ UInt64(words[index + 7])
            t2 = ((rotA >> 2) ^ (rotA >> 13) ^ (rotA >> 22)) &+ UInt64((b & c) | (d & (b | c)))
            e = UInt32(truncatingIfNeeded: UInt64(e) &+ t1)
            a = UInt32(truncatingIfNeeded: t1 &+ t2)
            index += 8
        }
        return [a, b, c, d, e, f, g, h]
    }

    // python tuple swap in the head loop handled inline above.

    internal static func dbgWords(_ salt: [UInt8]) -> [UInt32] {
        var words: [UInt32] = Array(repeating: 0, count: 14)
        words.append((UInt32(salt[0]) << 16) | (UInt32(salt[1]) << 8) | UInt32(salt[2]))  // int.from_bytes(data[:3]) — 3 bytes!
        words.append(be32(salt, 3))
        for index in 16..<30 {
            var value = UInt64(schedule[index - 16])
            if index - 2 >= 14 {
                value &+= index == 16 ? UInt64(sigma1(words[index - 2]) ^ sigma1Adj)
                                      : UInt64(sigma1(words[index - 2]))
            }
            if index - 7 >= 14 { value &+= UInt64(words[index - 7]) }
            if index - 15 >= 14 {
                value &+= index == 29 ? UInt64(sigma0(words[index - 15]) ^ sigma0Adj)
                                      : UInt64(sigma0(words[index - 15]))
            }
            words.append(UInt32(truncatingIfNeeded: value))
        }
        words.append(UInt32(truncatingIfNeeded:
            UInt64(sigma1(words[28])) &+ UInt64(words[23]) &+ UInt64(sigma0(words[15]))
            &+ UInt64(words[14]) &+ 0xC9DC06A7 &- UInt64(k[14])))
        expandSchedule(&words, 31)
        let working = dbgRounds(state0, words, 14)
        return zip(initial, working).map(&+)
    }

    internal static func dbgDigest(_ data: [UInt8]) -> [UInt8] {
        precondition(data.count >= 7)
        let length = 57 + data.count
        var padded = Array(data[7...]) + [0x80]
        let padCount = ((55 - length) % 64 + 64) % 64   // python-style positive modulo
        padded.append(contentsOf: repeatElement(0, count: padCount))
        let bitLen = UInt64(length * 8)
        for shift in stride(from: 56, through: 0, by: -8) {
            padded.append(UInt8(truncatingIfNeeded: bitLen >> shift))
        }
        var state = dbgWords(Array(data[0..<7]))
        var offset = 0
        while offset < padded.count {
            var words = (0..<16).map { be32(padded, offset + $0 * 4) }
            expandSchedule(&words, 16)
            state = zip(state, dbgRounds(state, words, 0)).map(&+)
            offset += 64
        }
        var out = [UInt8]()
        for word in state {
            for shift in stride(from: 24, through: 0, by: -8) {
                out.append(UInt8(truncatingIfNeeded: word >> shift))
            }
        }
        return out
    }

    // MARK: - CS64 + token
    internal static func dbgCs64(_ digest: [UInt8], _ payload: [UInt8]) -> (UInt32, UInt32) {
        let keyA = le32(digest, 0) | 1, keyB = le32(digest, 4) | 1
        let factors = [keyA &* 0x82893933, keyB &* 0x82893933]
        let coefficients: [(UInt32, UInt32)] = [
            (0xE82E91B1, 0xB32700D0), (0x44DE24C6, 0x88DFF51D), (0x3BEB65BC, 0x29514038),
            (0xC89C5933, 0xB328CBDF), (0x8D1EC211, 0xD405B4D5), (0x314EF5D5, 0x26E55F3C),
            (0xE92491B1, 0x607801C6), (0xF0A5B9D5, 0x82B2C1FB), (0x06064CF3, 0xFA51A3DA),
            (0xDA79FA60, 0x207CC464), (0xBED20560, 0x3C3C74F3), (0x89F9C9F8, 0xD2D14B61),
            (0x35FA38C6, 0xBB04A2C1), (0xCB49E3C6, 0xC5626167),
        ]
        var terms = (0..<14).map { coefficients[$0].0 &* factors[$0 % 2] }
        var offsets = coefficients.map(\.1)
        var words: [UInt32] = []
        var shifted = [UInt8](repeating: 0, count: (payload.count + 4) / 4 * 4)
        for (i, byte) in payload.enumerated() { shifted[i + 1] = byte }   // b"\x00" + data, zero-padded
        for i in 0..<(shifted.count / 4) {
            words.append(UInt32(shifted[i*4]) | (UInt32(shifted[i*4+1]) << 8) | (UInt32(shifted[i*4+2]) << 16) | (UInt32(shifted[i*4+3]) << 24))
        }
        if words.count % 2 != 0 { words.append(0) }
        for (index, word) in words.enumerated() {
            var term = word &* (index % 2 == 0 ? keyA : keyB)
            var offset = rol16(word) &* (index % 2 == 0 ? 0xEF0569FB : 0xC31713DB)
            if index == 0 { term = term &+ 0xF2F90B1A &* factors[0]; offset = offset &+ 0x0B1A0000 }
            terms.append(term); offsets.append(offset)
        }
        var swapAcc: UInt32 = 0, swapLast: UInt32 = 0, state: UInt32 = 0, acc: UInt32 = 0
        var i = 0
        while i < terms.count {
            let x = terms[i], y = terms[i + 1]
            var t = rol16(offsets[i] &+ x); var q = t &* 0x76F50F34
            swapAcc = swapAcc &+ (rol16(q) &* 0xC3EFEA97) &+ q
            t = rol16(offsets[i + 1] &+ y); q = t &* 0x1881CE3C
            swapLast = (rol16(q) &* 0x35BD1EC9) &+ q
            swapAcc = swapAcc &+ swapLast
            state = (state &* keyA) &+ x
            state = rol16(state) &* 0xCF98B111; state = rol16(state) &* 0x87085B9F
            state = rol16(state) &* 0x12CEB96D; state = rol16(state) &* 0x257E1D83
            acc = acc &+ state
            var t2 = (state &* keyB) &+ y
            t2 = rol16(t2) &* 0xA27416F5; t2 = rol16(t2) &* 0xD38396FF
            state = rol16(rol16(t2) &* 0x7C932B89) &* 0xBFA49F69
            acc = acc &+ state
            i += 2
        }
        return (swapLast ^ state, swapAcc ^ acc)
    }


    private static func token(payload: [UInt8]) -> String {
        let digest = dbgDigest(payload)
        let keyA = le32(digest, 0) | 1, keyB = le32(digest, 4) | 1
        let factors = [keyA &* 0x82893933, keyB &* 0x82893933]
        var terms = (0..<14).map { coefficients[$0].0 &* factors[$0 % 2] }
        var offsets = coefficients.map(\.1)
        var words: [UInt32] = []
        var shiftedA = [UInt8](repeating: 0, count: (payload.count + 4) / 4 * 4)
        for (i, byte) in payload.enumerated() { shiftedA[i + 1] = byte }
        for i in 0..<(shiftedA.count / 4) {
            words.append(UInt32(shiftedA[i*4]) | (UInt32(shiftedA[i*4+1]) << 8) | (UInt32(shiftedA[i*4+2]) << 16) | (UInt32(shiftedA[i*4+3]) << 24))
        }
        if words.count % 2 != 0 { words.append(0) }
        for (index, word) in words.enumerated() {
            var term = word &* (index % 2 == 0 ? keyA : keyB)
            var offset = rol16(word) &* (index % 2 == 0 ? 0xEF0569FB : 0xC31713DB)
            if index == 0 {
                term = term &+ 0xF2F90B1A &* factors[0]
                offset = offset &+ 0x0B1A0000
            }
            terms.append(term)
            offsets.append(offset)
        }
        var swapAcc: UInt32 = 0, swapLast: UInt32 = 0, state: UInt32 = 0, acc: UInt32 = 0
        var i = 0
        while i < terms.count {
            let x = terms[i], y = terms[i + 1]
            var t = rol16(offsets[i] &+ x)
            var q = t &* 0x76F50F34
            swapAcc = swapAcc &+ (rol16(q) &* 0xC3EFEA97) &+ q
            t = rol16(offsets[i + 1] &+ y)
            q = t &* 0x1881CE3C
            swapLast = (rol16(q) &* 0x35BD1EC9) &+ q
            swapAcc = swapAcc &+ swapLast
            state = (state &* keyA) &+ x
            state = rol16(state) &* 0xCF98B111
            state = rol16(state) &* 0x87085B9F
            state = rol16(state) &* 0x12CEB96D
            state = rol16(state) &* 0x257E1D83
            acc = acc &+ state
            var t2 = (state &* keyB) &+ y
            t2 = rol16(t2) &* 0xA27416F5
            t2 = rol16(t2) &* 0xD38396FF
            state = rol16(rol16(t2) &* 0x7C932B89) &* 0xBFA49F69
            acc = acc &+ state
            i += 2
        }
        func hexLE(_ v: UInt32) -> String {
            (0..<4).map { String(format: "%02X", UInt8(truncatingIfNeeded: v >> (8 * $0))) }.joined()
        }
        let sha = digest.map { String(format: "%02X", $0) }.joined()
        return "\(hexLE(swapLast ^ state))\(hexLE(swapAcc ^ acc))-\(sha)"
    }
}
