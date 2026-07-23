import CryptoKit
import Foundation

enum StableIdentifier {
    static func uuid(
        namespace: String,
        components: [String?]
    ) -> UUID {
        var material = Data()
        append(namespace, to: &material)

        for component in components {
            guard let component else {
                material.append(0)
                continue
            }
            material.append(1)
            append(component, to: &material)
        }

        var bytes = Array(SHA256.hash(data: material).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            )
        )
    }

    private static func append(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        var length = UInt64(bytes.count).bigEndian
        withUnsafeBytes(of: &length) { buffer in
            data.append(contentsOf: buffer)
        }
        data.append(bytes)
    }
}
