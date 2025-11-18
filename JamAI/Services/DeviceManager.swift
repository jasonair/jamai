//
//  DeviceManager.swift
//  JamAI
//
//  Manages per-installation device identifier and Firestore device limit enforcement.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Manages the current device identity and registration in Firestore.
@MainActor
final class DeviceManager {
    static let shared = DeviceManager()
    
    private let db = Firestore.firestore()
    private let auth = Auth.auth()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Returns a stable device identifier for this installation, stored securely in Keychain.
    func currentDeviceId() -> String {
        if let existing = try? KeychainHelper.retrieve(forKey: Config.deviceIdKey) {
            return existing
        }
        let newId = UUID().uuidString
        try? KeychainHelper.save(newId, forKey: Config.deviceIdKey)
        return newId
    }
    
    /// Human-friendly device name (not security critical).
    private func currentDeviceName() -> String {
        return "Mac"
    }
    
    /// Register the current device for the given user, enforcing a maximum of two devices.
    ///
    /// - Returns: `true` if this device is allowed, `false` if the user already has two active devices.
    func registerCurrentDeviceForUser(userId: String) async -> Bool {
        let deviceId = currentDeviceId()
        let deviceName = currentDeviceName()
        let docRef = db.collection("users").document(userId).collection("_internal").document("devices")
        let now = Timestamp(date: Date())
        
        do {
            let _ = try await db.runTransaction { transaction, errorPointer in
                do {
                    let snapshot = try transaction.getDocument(docRef)
                    var data = snapshot.data() ?? [:]
                    
                    var slot1Id = data["slot1DeviceId"] as? String
                    var slot1Name = data["slot1DeviceName"] as? String
                    var slot1LastActive = data["slot1LastActiveAt"] as? Timestamp
                    
                    var slot2Id = data["slot2DeviceId"] as? String
                    var slot2Name = data["slot2DeviceName"] as? String
                    var slot2LastActive = data["slot2LastActiveAt"] as? Timestamp
                    
                    // If this device already occupies a slot, just refresh metadata.
                    if slot1Id == deviceId {
                        slot1Name = deviceName
                        slot1LastActive = now
                    } else if slot2Id == deviceId {
                        slot2Name = deviceName
                        slot2LastActive = now
                    } else {
                        // Try to claim an empty slot first.
                        if slot1Id == nil || slot1Id?.isEmpty == true {
                            slot1Id = deviceId
                            slot1Name = deviceName
                            slot1LastActive = now
                        } else if slot2Id == nil || slot2Id?.isEmpty == true {
                            slot2Id = deviceId
                            slot2Name = deviceName
                            slot2LastActive = now
                        } else {
                            // Both slots are occupied by other devices. Reject.
                            errorPointer?.pointee = NSError(
                                domain: "DeviceManager",
                                code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Maximum number of devices reached"]
                            )
                            return nil
                        }
                    }
                    
                    data["slot1DeviceId"] = slot1Id
                    data["slot1DeviceName"] = slot1Name
                    data["slot1LastActiveAt"] = slot1LastActive
                    
                    data["slot2DeviceId"] = slot2Id
                    data["slot2DeviceName"] = slot2Name
                    data["slot2LastActiveAt"] = slot2LastActive
                    
                    transaction.setData(data, forDocument: docRef, merge: true)
                    return true as NSNumber
                } catch let error as NSError {
                    errorPointer?.pointee = error
                    return nil
                }
            }
            return true
        } catch {
            print("❌ Failed to register device for user \(userId): \(error)")
            return false
        }
    }
    
    /// Clear the current device from the user's device slots on sign-out.
    func unregisterCurrentDeviceForUser(userId: String) async {
        let deviceId = currentDeviceId()
        let docRef = db.collection("users").document(userId).collection("_internal").document("devices")
        
        do {
            let _ = try await db.runTransaction { transaction, errorPointer in
                do {
                    let snapshot = try transaction.getDocument(docRef)
                    guard var data = snapshot.data() else {
                        return nil
                    }
                    
                    var changed = false
                    if let slot1Id = data["slot1DeviceId"] as? String, slot1Id == deviceId {
                        data["slot1DeviceId"] = FieldValue.delete()
                        data["slot1DeviceName"] = FieldValue.delete()
                        data["slot1LastActiveAt"] = FieldValue.delete()
                        changed = true
                    }
                    if let slot2Id = data["slot2DeviceId"] as? String, slot2Id == deviceId {
                        data["slot2DeviceId"] = FieldValue.delete()
                        data["slot2DeviceName"] = FieldValue.delete()
                        data["slot2LastActiveAt"] = FieldValue.delete()
                        changed = true
                    }
                    
                    if changed {
                        transaction.updateData(data, forDocument: docRef)
                    }
                    return nil
                } catch let error as NSError {
                    errorPointer?.pointee = error
                    return nil
                }
            }
        } catch {
            print("⚠️ Failed to unregister device for user \(userId): \(error)")
        }
    }
}
