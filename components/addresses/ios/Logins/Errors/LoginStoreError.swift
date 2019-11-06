/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

/// Indicates an error occurred while calling into the addresses storage layer
public enum AddressesStoreError: LocalizedError {
    /// This is a catch-all error code used for errors not yet exposed to consumers,
    /// typically since it doesn't seem like there's a sane way for them to be handled.
    case unspecified(message: String)

    /// The rust code implementing addresses storage paniced. This always indicates a bug.
    case panic(message: String)

    /// This indicates that the sync authentication is invalid, likely due to having
    /// expired.
    case authInvalid(message: String)

    /// This is thrown if a `touch` or `update` refers to a record whose ID is not known
    case noSuchRecord(message: String)

    /// This is thrown on attempts to `add` a record with a specific ID, but that ID
    /// already exists.
    case duplicateGuid(message: String)

    /// This is thrown on attempts to insert or update a record so that it
    /// is no longer valid. Valid records have:
    ///
    /// - non-empty hostnames
    /// - non-empty passwords
    /// - and exactly one of `httpRealm` or `formSubmitUrl` is non-null.
    case invalidAddress(message: String)

    /// This error is emitted in two cases:
    ///
    /// 1. An incorrect key is used to to open the address database
    /// 2. The file at the path specified is not a sqlite database.
    case invalidKey(message: String)

    /// This error is emitted if a request to a sync server failed.
    case network(message: String)

    /// This error is emitted if a call to `interrupt()` is made to
    /// abort some operation.
    case interrupted(message: String)

    /// Our implementation of the localizedError protocol -- (This shows up in Sentry)
    public var errorDescription: String? {
        switch self {
        case let .unspecified(message):
            return "AddressesStoreError.unspecified: \(message)"
        case let .panic(message):
            return "AddressesStoreError.panic: \(message)"
        case let .authInvalid(message):
            return "AddressesStoreError.authInvalid: \(message)"
        case let .noSuchRecord(message):
            return "AddressesStoreError.noSuchRecord: \(message)"
        case let .duplicateGuid(message):
            return "AddressesStoreError.duplicateGuid: \(message)"
        case let .invalidAddress(message):
            return "AddressesStoreError.invalidAddress: \(message)"
        case let .invalidKey(message):
            return "AddressesStoreError.invalidKey: \(message)"
        case let .network(message):
            return "AddressesStoreError.network: \(message)"
        case let .interrupted(message):
            return "AddressesStoreError.interrupted: \(message)"
        }
    }

    // The name is attempting to indicate that we free rustError.message if it
    // existed, and that it's a very bad idea to touch it after you call this
    // function
    static func fromConsuming(_ rustError: Sync15PasswordsError) -> AddressesStoreError? {
        let message = rustError.message

        switch rustError.code {
        case Sync15Passwords_NoError:
            return nil

        case Sync15Passwords_OtherError:
            return .unspecified(message: String(freeingRustString: message!))

        case Sync15Passwords_UnexpectedPanic:
            return .panic(message: String(freeingRustString: message!))

        case Sync15Passwords_AuthInvalidError:
            return .authInvalid(message: String(freeingRustString: message!))

        case Sync15Passwords_NoSuchRecord:
            return .noSuchRecord(message: String(freeingRustString: message!))

        case Sync15Passwords_DuplicateGuid:
            return .duplicateGuid(message: String(freeingRustString: message!))

        case Sync15Passwords_InvalidAddress:
            return .invalidAddress(message: String(freeingRustString: message!))

        case Sync15Passwords_InvalidKeyError:
            return .invalidKey(message: String(freeingRustString: message!))

        case Sync15Passwords_NetworkError:
            return .network(message: String(freeingRustString: message!))

        case Sync15Passwords_InterruptedError:
            return .interrupted(message: String(freeingRustString: message!))

        default:
            return .unspecified(message: String(freeingRustString: message!))
        }
    }

    @discardableResult
    public static func unwrap<T>(_ fn: (UnsafeMutablePointer<Sync15PasswordsError>) throws -> T?) throws -> T {
        var err = Sync15PasswordsError(code: Sync15Passwords_NoError, message: nil)
        guard let result = try fn(&err) else {
            if let addressErr = AddressesStoreError.fromConsuming(err) {
                throw addressErr
            }
            throw ResultError.empty
        }
        // result might not be nil (e.g. it could be 0), while still indicating failure. Ultimately,
        // `err` is the source of truth here.
        if let addressErr = AddressesStoreError.fromConsuming(err) {
            throw addressErr
        }
        return result
    }

    @discardableResult
    public static func tryUnwrap<T>(_ fn: (UnsafeMutablePointer<Sync15PasswordsError>) throws -> T?) throws -> T? {
        var err = Sync15PasswordsError(code: Sync15Passwords_NoError, message: nil)
        guard let result = try fn(&err) else {
            if let addressErr = AddressesStoreError.fromConsuming(err) {
                throw addressErr
            }
            return nil
        }
        // result might not be nil (e.g. it could be 0), while still indicating failure. Ultimately,
        // `err` is the source of truth here.
        if let addressErr = AddressesStoreError.fromConsuming(err) {
            throw addressErr
        }
        return result
    }
}
