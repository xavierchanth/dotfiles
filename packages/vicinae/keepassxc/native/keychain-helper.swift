import Foundation
import LocalAuthentication
import Security

private let namespace = "com.xavierchanth.vicinae.keepassxc"
private let keepassxcCLI = "@KEEPASSXC_CLI@"
private let maximumSecretBytes = 64 * 1024
private let maximumExportBytes = 16 * 1024 * 1024
private let exportTimeout: TimeInterval = 30

private enum HelperError: Error {
    case usage
    case invalidDatabase
    case invalidPassword
    case keychain(OSStatus)
    case process
    case exportTooLarge
    case timeout
}

private func canonicalPath(_ argument: String, mustExist: Bool) throws -> String {
    guard argument.hasPrefix("/") else { throw HelperError.invalidDatabase }
    let url = URL(fileURLWithPath: argument).standardizedFileURL.resolvingSymlinksInPath()
    if mustExist && !FileManager.default.fileExists(atPath: url.path) {
        throw HelperError.invalidDatabase
    }
    return url.path
}

private func keychainIdentity(database: String) -> (service: String, account: String) {
    ("\(namespace).database-password", "database:\(database)")
}

private func baseQuery(database: String) -> [String: Any] {
    let identity = keychainIdentity(database: database)
    return [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: identity.service,
        kSecAttrAccount as String: identity.account,
    ]
}

private func readPassword() throws -> Data {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard data.count <= maximumSecretBytes else { throw HelperError.invalidPassword }
    var password = data
    while password.last == 10 || password.last == 13 { password.removeLast() }
    guard !password.isEmpty else { throw HelperError.invalidPassword }
    return password
}

private func delete(database: String, allowMissing: Bool = false) throws {
    let status = SecItemDelete(baseQuery(database: database) as CFDictionary)
    guard status == errSecSuccess || (allowMissing && status == errSecItemNotFound) else {
        throw HelperError.keychain(status)
    }
}

private func store(database: String) throws {
    var password = try readPassword()
    defer { password.resetBytes(in: 0..<password.count) }
    var accessError: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        .userPresence,
        &accessError
    ) else { throw HelperError.keychain(errSecParam) }

    try delete(database: database, allowMissing: true)
    var query = baseQuery(database: database)
    query[kSecValueData as String] = password
    query[kSecAttrAccessControl as String] = access
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else { throw HelperError.keychain(status) }
}

private func retrieve(database: String) throws -> Data {
    var query = baseQuery(database: database)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    let context = LAContext()
    context.localizedReason = "Unlock the KeePassXC database for Vicinae"
    query[kSecUseAuthenticationContext as String] = context
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let password = result as? Data else {
        throw HelperError.keychain(status)
    }
    return password
}

private func export(database: String, keyFile: String?) throws {
    var password = try retrieve(database: database)
    defer { password.resetBytes(in: 0..<password.count) }
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: keepassxcCLI)
    process.arguments = ["export", "--quiet", "--format", "xml"]
        + (keyFile.map { ["--key-file", $0] } ?? [])
        + [database]
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { throw HelperError.process }
    let timeoutLock = NSLock()
    var timedOut = false
    let timeout = DispatchWorkItem {
        timeoutLock.lock()
        timedOut = true
        timeoutLock.unlock()
        if process.isRunning { process.terminate() }
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + exportTimeout, execute: timeout)
    input.fileHandleForWriting.write(password)
    input.fileHandleForWriting.write(Data([10]))
    try input.fileHandleForWriting.close()

    var xml = Data()
    var overflowed = false
    while true {
        let chunk = output.fileHandleForReading.availableData
        if chunk.isEmpty { break }
        if xml.count + chunk.count > maximumExportBytes {
            overflowed = true
            if process.isRunning { process.terminate() }
        } else if !overflowed {
            xml.append(chunk)
        }
    }
    process.waitUntilExit()
    timeout.cancel()
    timeoutLock.lock()
    let didTimeOut = timedOut
    timeoutLock.unlock()
    if didTimeOut { throw HelperError.timeout }
    if overflowed { throw HelperError.exportTooLarge }
    guard process.terminationReason == .exit && process.terminationStatus == 0 else {
        throw HelperError.process
    }
    FileHandle.standardOutput.write(xml)
}

private func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count >= 2 else { throw HelperError.usage }
    let operation = arguments[0]
    let database = try canonicalPath(arguments[1], mustExist: operation == "export")
    switch operation {
    case "store" where arguments.count == 2:
        try store(database: database)
    case "delete" where arguments.count == 2:
        try delete(database: database, allowMissing: true)
    case "export" where arguments.count == 2 || arguments.count == 3:
        let keyFile = try arguments.count == 3 ? canonicalPath(arguments[2], mustExist: true) : nil
        try export(database: database, keyFile: keyFile)
    default:
        throw HelperError.usage
    }
}

do {
    try run()
} catch HelperError.usage {
    FileHandle.standardError.write(Data("Usage error\n".utf8))
    exit(64)
} catch HelperError.invalidDatabase {
    FileHandle.standardError.write(Data("Invalid path\n".utf8))
    exit(65)
} catch HelperError.invalidPassword {
    FileHandle.standardError.write(Data("Invalid password input\n".utf8))
    exit(65)
} catch HelperError.exportTooLarge {
    FileHandle.standardError.write(Data("KeePassXC export exceeds the safety limit\n".utf8))
    exit(74)
} catch HelperError.timeout {
    FileHandle.standardError.write(Data("KeePassXC export timed out\n".utf8))
    exit(75)
} catch HelperError.keychain(let status) {
    FileHandle.standardError.write(Data("Keychain operation failed (\(status))\n".utf8))
    exit(77)
} catch {
    FileHandle.standardError.write(Data("KeePassXC export failed\n".utf8))
    exit(70)
}
