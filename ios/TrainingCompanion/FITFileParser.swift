import Foundation
import CryptoKit

// MARK: - FIT Binary Parser
// Parses Garmin FIT Activity files produced by WorkoutDoors and similar apps.
// Handles: normal records, compressed-timestamp records, little- and big-endian messages.

struct FITFileParser {

    private static let fitEpochOffset: TimeInterval = 631_065_600  // 1989-12-31 00:00:00 UTC
    private static let semiToDeg: Double = 180.0 / 2_147_483_648.0  // 180 / 2^31

    // MARK: - Output types

    struct Session {
        var sport: String = "generic"
        var startTime: Date?
        var elapsedSeconds: Double = 0
        var distanceMeters: Double = 0
        var calories: Int?
        var avgHR: Int?
        var maxHR: Int?
        var totalAscentM: Double?
    }

    struct Record {
        var timestamp: Date
        var lat: Double?
        var lng: Double?
        var altitudeM: Double?
        var heartRate: Int?
        var speedMS: Double?
    }

    enum ParseError: Error {
        case invalidHeader
        case notFitFile
        case noSession
    }

    // MARK: - Private types

    private struct FieldDef {
        let num: UInt8
        let size: Int
        let byteOffset: Int  // byte offset within the data message payload
    }

    private struct MsgDef {
        let globalNum: UInt16
        let bigEndian: Bool
        let fields: [FieldDef]
        let dataSize: Int
        /// dataSize minus the 4-byte timestamp field (for compressed-timestamp records)
        let compressedDataSize: Int
    }

    // MARK: - Parse

    static func parse(data: Data) throws -> (session: Session, records: [Record]) {
        guard data.count >= 14 else { throw ParseError.invalidHeader }
        guard data[8] == 0x2E, data[9] == 0x46,
              data[10] == 0x49, data[11] == 0x54 else { throw ParseError.notFitFile }

        let headerSize = Int(data[0])
        let dataSize   = leUInt32(data, at: 4)
        guard headerSize + dataSize <= data.count else { throw ParseError.invalidHeader }

        var defs: [UInt8: MsgDef] = [:]
        var session = Session()
        var records: [Record] = []
        var lastTimestamp: UInt32 = 0

        var pos = headerSize
        let end = headerSize + dataSize

        while pos < end {
            guard pos < data.count else { break }
            let hdr = data[pos]; pos += 1

            if hdr & 0x80 != 0 {
                // ── Compressed-timestamp data record ──────────────────────────
                let localType = (hdr >> 5) & 0x03
                let timeOffset = UInt32(hdr & 0x1F)

                // Reconstruct 32-bit timestamp from 5-bit offset
                var ts = (lastTimestamp & ~UInt32(0x1F)) | timeOffset
                if timeOffset < (lastTimestamp & 0x1F) { ts &+= 32 }
                lastTimestamp = ts

                guard let def = defs[localType] else { break }
                guard pos + def.compressedDataSize <= end else { break }

                // Parse fields, injecting the reconstructed timestamp
                if def.globalNum == 20 {
                    if var rec = parseRecordMsg(data: data, at: pos, def: def,
                                               compressedTimestamp: fitDate(ts)) {
                        records.append(rec)
                    }
                } else if def.globalNum == 18 {
                    parseSessionMsg(data: data, at: pos, def: def, into: &session,
                                    compressedTimestamp: fitDate(ts))
                }
                pos += def.compressedDataSize

            } else if hdr & 0x40 != 0 {
                // ── Definition message ─────────────────────────────────────────
                guard pos + 5 <= end else { break }
                pos += 1  // reserved
                let bigEndian = data[pos] == 1; pos += 1
                let globalNum: UInt16 = bigEndian
                    ? UInt16(data[pos]) << 8 | UInt16(data[pos+1])
                    : UInt16(data[pos]) | UInt16(data[pos+1]) << 8
                pos += 2
                let fieldCount = Int(data[pos]); pos += 1

                var fields: [FieldDef] = []
                var byteOffset = 0
                var tsFieldSize = 0
                for _ in 0..<fieldCount {
                    guard pos + 3 <= end else { break }
                    let num  = data[pos]; pos += 1
                    let size = Int(data[pos]); pos += 1
                    pos += 1  // base type (not needed — we infer from field num)
                    if num == 253 { tsFieldSize = size }
                    fields.append(FieldDef(num: num, size: size, byteOffset: byteOffset))
                    byteOffset += size
                }

                // Developer fields
                if hdr & 0x20 != 0, pos < end {
                    let devCount = Int(data[pos]); pos += 1
                    pos += devCount * 3
                }

                let totalDataSize = byteOffset
                let localType = hdr & 0x0F
                defs[localType] = MsgDef(
                    globalNum: globalNum,
                    bigEndian: bigEndian,
                    fields: fields,
                    dataSize: totalDataSize,
                    compressedDataSize: max(0, totalDataSize - tsFieldSize)
                )

            } else {
                // ── Normal data message ────────────────────────────────────────
                let localType = hdr & 0x0F
                guard let def = defs[localType] else { break }
                guard pos + def.dataSize <= end else { break }

                if def.globalNum == 20 {  // record
                    if let rec = parseRecordMsg(data: data, at: pos, def: def,
                                               compressedTimestamp: nil) {
                        lastTimestamp = lastTS(from: rec)
                        records.append(rec)
                    }
                } else if def.globalNum == 18 {  // session
                    parseSessionMsg(data: data, at: pos, def: def, into: &session,
                                    compressedTimestamp: nil)
                }
                pos += def.dataSize
            }
        }

        // Fallback: infer start time from first record if session message had none
        if session.startTime == nil, let first = records.first {
            session.startTime = first.timestamp
        }
        guard session.startTime != nil else { throw ParseError.noSession }

        return (session, records)
    }

    // MARK: - Message parsers

    private static func parseRecordMsg(data: Data, at base: Int, def: MsgDef,
                                       compressedTimestamp: Date?) -> Record? {
        var timestamp: Date? = compressedTimestamp
        var lat: Double?
        var lng: Double?
        var alt: Double?
        var hr: Int?
        var speed: Double?

        for f in def.fields {
            if compressedTimestamp != nil && f.num == 253 { continue }  // skip in compressed mode
            let raw = readU64(data, at: base + f.byteOffset, size: f.size, bigEndian: def.bigEndian)
            guard !isInvalid(raw, size: f.size) else { continue }

            switch f.num {
            case 253:
                timestamp = fitDate(UInt32(raw & 0xFFFFFFFF))
            case 0:
                lat = Double(Int32(bitPattern: UInt32(raw & 0xFFFFFFFF))) * semiToDeg
            case 1:
                lng = Double(Int32(bitPattern: UInt32(raw & 0xFFFFFFFF))) * semiToDeg
            case 2, 78:   // altitude / enhanced_altitude  (scale=5, offset=500)
                let v = Double(raw) / 5.0 - 500.0
                if v > -500 { alt = v }  // discard obviously bogus values
            case 3:
                hr = Int(raw)
            case 6, 136:  // speed / enhanced_speed  (scale=1000 → m/s)
                speed = Double(raw) / 1000.0
            default: break
            }
        }

        guard let ts = timestamp else { return nil }
        guard lat != nil || hr != nil else { return nil }  // skip empty records
        return Record(timestamp: ts, lat: lat, lng: lng,
                      altitudeM: alt, heartRate: hr, speedMS: speed)
    }

    private static func parseSessionMsg(data: Data, at base: Int, def: MsgDef,
                                        into session: inout Session,
                                        compressedTimestamp: Date?) {
        for f in def.fields {
            if compressedTimestamp != nil && f.num == 253 { continue }
            let raw = readU64(data, at: base + f.byteOffset, size: f.size, bigEndian: def.bigEndian)
            guard !isInvalid(raw, size: f.size) else { continue }

            switch f.num {
            case 2:   session.startTime = fitDate(UInt32(raw & 0xFFFFFFFF))
            case 253: if session.startTime == nil { session.startTime = fitDate(UInt32(raw & 0xFFFFFFFF)) }
            case 7:   session.elapsedSeconds = Double(raw) / 1000.0
            case 9:   session.distanceMeters = Double(raw) / 100.0
            case 11:  session.calories = Int(raw)
            case 16:  session.avgHR = Int(raw)
            case 17:  session.maxHR = Int(raw)
            case 5:   session.sport = sportName(UInt8(raw & 0xFF))
            case 6:
                let sub = subSportName(UInt8(raw & 0xFF))
                if sub != "generic" { session.sport = sub }
            case 26:  session.totalAscentM = Double(raw)
            default: break
            }
        }
    }

    // MARK: - Reading primitives

    private static func readU64(_ data: Data, at offset: Int, size: Int, bigEndian: Bool) -> UInt64 {
        guard size > 0, offset >= 0, offset + size <= data.count else {
            return 0xFFFFFFFFFFFFFFFF
        }
        var val: UInt64 = 0
        if bigEndian {
            for i in 0..<size { val = (val << 8) | UInt64(data[offset + i]) }
        } else {
            for i in 0..<size { val |= UInt64(data[offset + i]) << (i * 8) }
        }
        return val
    }

    private static func leUInt32(_ data: Data, at offset: Int) -> Int {
        guard offset + 3 < data.count else { return 0 }
        return Int(data[offset]) | Int(data[offset+1]) << 8
             | Int(data[offset+2]) << 16 | Int(data[offset+3]) << 24
    }

    private static func isInvalid(_ val: UInt64, size: Int) -> Bool {
        switch size {
        case 1: return val == 0xFF
        case 2: return val == 0xFFFF
        case 4: return val == 0xFFFFFFFF
        case 8: return val == 0xFFFFFFFFFFFFFFFF
        default: return false
        }
    }

    private static func fitDate(_ ts: UInt32) -> Date {
        Date(timeIntervalSince1970: Double(ts) + fitEpochOffset)
    }

    private static func lastTS(from record: Record) -> UInt32 {
        UInt32(max(0, record.timestamp.timeIntervalSince1970 - fitEpochOffset))
    }

    // MARK: - Sport name mapping

    private static func sportName(_ v: UInt8) -> String {
        switch v {
        case 1:  return "running"
        case 2:  return "cycling"
        case 5:  return "swimming"
        case 11: return "walking"
        case 15: return "rowing"
        case 17: return "hiking"
        case 10, 254: return "training"
        default: return "generic"
        }
    }

    private static func subSportName(_ v: UInt8) -> String {
        switch v {
        case 1:  return "treadmill"
        case 2:  return "street"
        case 3:  return "trail"
        case 4:  return "track"
        case 9:  return "cyclocross"
        default: return "generic"
        }
    }

    // MARK: - Convert to ImportedWorkout

    static func toImportedWorkout(session: Session, records: [Record]) -> ImportedWorkout {
        guard let startTime = session.startTime else {
            fatalError("parse should have rejected noSession before here")
        }

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.timeZone = TimeZone(identifier: "UTC")

        let isoFmt = DateFormatter()
        isoFmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
        isoFmt.timeZone = TimeZone(identifier: "UTC")

        let dateStr = dateFmt.string(from: startTime)
        let startStr = isoFmt.string(from: startTime)
        let durationMin = session.elapsedSeconds / 60.0

        // Deterministic ID matches the server-side algorithm
        let raw = "fit_file|\(startStr)|\(session.sport)|\(Int(durationMin))"
        let hash = SHA256.hash(data: Data(raw.utf8))
        let hexStr = hash.map { String(format: "%02x", $0) }.joined()
        let workoutId = "fit_file-\(String(hexStr.prefix(24)))"

        // GPS track
        let gpsTrack: [GPSPoint]? = records.compactMap { rec in
            guard let lat = rec.lat, let lng = rec.lng else { return nil }
            return GPSPoint(lat: lat, lng: lng, altitude: rec.altitudeM,
                            timestamp: isoFmt.string(from: rec.timestamp),
                            bpm: rec.heartRate, speed: rec.speedMS)
        }.nilIfEmpty()

        // HR samples
        let hrSamples: [HRSample] = records.compactMap { rec in
            guard let bpm = rec.heartRate, bpm > 0 else { return nil }
            return HRSample(timestamp: isoFmt.string(from: rec.timestamp), bpm: bpm)
        }

        // HR stats from records if session didn't have them
        let avgHR: Int? = session.avgHR ?? (hrSamples.isEmpty ? nil : hrSamples.map { $0.bpm }.reduce(0, +) / hrSamples.count)
        let maxHR: Int? = session.maxHR ?? hrSamples.map { $0.bpm }.max()

        // Elevation gain from GPS
        var gain = session.totalAscentM
        if gain == nil {
            gain = computeElevationGain(records: records)
        }

        let distance: WorkoutDistance? = session.distanceMeters > 0
            ? WorkoutDistance(value: round(session.distanceMeters) / 1000.0, unit: "km")
            : nil

        return ImportedWorkout(
            id: workoutId,
            source: "fit_file",
            date: dateStr,
            startTime: startStr,
            durationMinutes: durationMin,
            activityType: session.sport,
            inferredModalityId: modalityForSport(session.sport),
            heartRate: WorkoutHRData(avg: avgHR, max: maxHR, samples: hrSamples),
            calories: session.calories.map { Double($0) },
            distance: distance,
            gpsTrack: gpsTrack,
            elevation: gain.map { WorkoutElevation(gain: $0, loss: nil) }
        )
    }

    private static func computeElevationGain(records: [Record]) -> Double? {
        let alts = records.compactMap { $0.altitudeM }
        guard alts.count > 1 else { return nil }
        var gain = 0.0
        for i in 1..<alts.count {
            let diff = alts[i] - alts[i-1]
            if diff > 0 { gain += diff }
        }
        return gain > 0 ? gain : nil
    }

    private static func modalityForSport(_ sport: String) -> String? {
        switch sport {
        case "running", "cycling", "swimming", "rowing": return "aerobic_base"
        case "walking", "hiking":   return "durability"
        case "trail":               return "aerobic_base"
        case "training":            return "mixed_modal_conditioning"
        default:                    return nil
        }
    }
}

private extension Array {
    func nilIfEmpty() -> [Element]? { isEmpty ? nil : self }
}
