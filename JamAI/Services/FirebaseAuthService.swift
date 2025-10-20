//
//  FirebaseAuthService.swift
//  JamAI
//
//  Handles Firebase authentication (Email, Google Sign-In)
//

import Foundation
import Combine
import FirebaseAuth
// import GoogleSignIn  // Temporarily disabled due to umbrella header issue
// import AuthenticationServices  // Commented out - not needed without Apple Sign-In

/// Authentication errors
enum AuthError: LocalizedError {
    case invalidCredentials
    case userNotFound
    case networkError
    case weakPassword
    case emailAlreadyInUse
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .userNotFound:
            return "No account found with this email"
        case .networkError:
            return "Network connection failed"
        case .weakPassword:
            return "Password must be at least 6 characters"
        case .emailAlreadyInUse:
            return "An account with this email already exists"
        case .unknown(let message):
            return message
        }
    }
}

/// Authentication result
struct AuthResult {
    let user: User
    let isNewUser: Bool
}

/// Firebase authentication service
@MainActor
class FirebaseAuthService: ObservableObject {
    
    static let shared = FirebaseAuthService()
    
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    
    private let auth = Auth.auth()
    nonisolated(unsafe) private var authStateListener: AuthStateDidChangeListenerHandle?
    
    private init() {
        setupAuthStateListener()
    }
    
    deinit {
        cleanup()
    }
    
    /// Cleanup auth listener
    nonisolated func cleanup() {
        if let listener = authStateListener {
            auth.removeStateDidChangeListener(listener)
            authStateListener = nil
        }
    }
    
    // MARK: - Auth State
    
    private func setupAuthStateListener() {
        authStateListener = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isAuthenticated = user != nil
                
                if let user = user {
                    // Update last login time in Firestore
                    await FirebaseDataService.shared.updateLastLogin(userId: user.uid)
                }
            }
        }
    }
    
    // MARK: - Email/Password Authentication
    
    /// Sign up with email and password
    func signUp(email: String, password: String, displayName: String?) async throws -> AuthResult {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let result = try await auth.createUser(withEmail: email, password: password)
            
            // Update display name if provided
            if let displayName = displayName {
                let changeRequest = result.user.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try await changeRequest.commitChanges()
            }
            
            // Create user account in Firestore
            await FirebaseDataService.shared.createUserAccount(
                userId: result.user.uid,
                email: email,
                displayName: displayName
            )
            
            return AuthResult(user: result.user, isNewUser: true)
        } catch let error as NSError {
            throw mapAuthError(error)
        }
    }
    
    /// Sign in with email and password
    func signIn(email: String, password: String) async throws -> AuthResult {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            return AuthResult(user: result.user, isNewUser: false)
        } catch let error as NSError {
            throw mapAuthError(error)
        }
    }
    
    // MARK: - Google Sign-In (Temporarily disabled due to SDK umbrella header issue)
    
    // /// Sign in with Google
    // func signInWithGoogle() async throws -> AuthResult {
    //     isLoading = true
    //     defer { isLoading = false }
    //     
    //     guard let clientID = FirebaseApp.app()?.options.clientID else {
    //         throw AuthError.unknown("Firebase client ID not found")
    //     }
    //     
    //     let config = GIDConfiguration(clientID: clientID)
    //     GIDSignIn.sharedInstance.configuration = config
    //     
    //     // Get the presenting window
    //     guard let window = NSApplication.shared.windows.first else {
    //         throw AuthError.unknown("No window found")
    //     }
    //     
    //     do {
    //         let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
    //         
    //         guard let idToken = result.user.idToken?.tokenString else {
    //             throw AuthError.unknown("Failed to get ID token")
    //         }
    //         
    //         let accessToken = result.user.accessToken.tokenString
    //         let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
    //         
    //         let authResult = try await auth.signIn(with: credential)
    //         let isNewUser = authResult.additionalUserInfo?.isNewUser ?? false
    //         
    //         // Create user account if new
    //         if isNewUser {
    //             await FirebaseDataService.shared.createUserAccount(
    //                 userId: authResult.user.uid,
    //                 email: authResult.user.email ?? "",
    //                 displayName: authResult.user.displayName
    //             )
    //         }
    //         
    //         return AuthResult(user: authResult.user, isNewUser: isNewUser)
    //     } catch {
    //         throw AuthError.unknown(error.localizedDescription)
    //     }
    // }
    
    // MARK: - Apple Sign-In (Commented out until credentials are available)
    
    // /// Sign in with Apple
    // func signInWithApple(authorization: ASAuthorization) async throws -> AuthResult {
    //     isLoading = true
    //     defer { isLoading = false }
    //     
    //     guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
    //         throw AuthError.unknown("Invalid Apple ID credential")
    //     }
    //     
    //     guard let appleIDToken = appleIDCredential.identityToken,
    //           let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
    //         throw AuthError.unknown("Unable to fetch identity token")
    //     }
    //     
    //     let nonce = randomNonceString()
    //     let credential = OAuthProvider.credential(
    //         withProviderID: "apple.com",
    //         idToken: idTokenString,
    //         rawNonce: nonce
    //     )
    //     
    //     do {
    //         let authResult = try await auth.signIn(with: credential)
    //         let isNewUser = authResult.additionalUserInfo?.isNewUser ?? false
    //         
    //         // Create user account if new
    //         if isNewUser {
    //             let displayName = [appleIDCredential.fullName?.givenName, appleIDCredential.fullName?.familyName]
    //                 .compactMap { $0 }
    //                 .joined(separator: " ")
    //             
    //             await FirebaseDataService.shared.createUserAccount(
    //                 userId: authResult.user.uid,
    //                 email: authResult.user.email ?? appleIDCredential.email ?? "",
    //                 displayName: displayName.isEmpty ? nil : displayName
    //             )
    //         }
    //         
    //         return AuthResult(user: authResult.user, isNewUser: isNewUser)
    //     } catch {
    //         throw AuthError.unknown(error.localizedDescription)
    //     }
    // }
    
    // MARK: - Password Reset
    
    /// Send password reset email
    func sendPasswordReset(email: String) async throws {
        do {
            try await auth.sendPasswordReset(withEmail: email)
        } catch let error as NSError {
            throw mapAuthError(error)
        }
    }
    
    // MARK: - Sign Out
    
    /// Sign out current user
    func signOut() throws {
        try auth.signOut()
        // GIDSignIn.sharedInstance.signOut()  // Temporarily disabled
    }
    
    // MARK: - Helpers
    
    private func mapAuthError(_ error: NSError) -> AuthError {
        guard let errorCode = AuthErrorCode(rawValue: error.code) else {
            return .unknown(error.localizedDescription)
        }
        
        switch errorCode {
        case .wrongPassword, .invalidCredential:
            return .invalidCredentials
        case .userNotFound:
            return .userNotFound
        case .networkError:
            return .networkError
        case .weakPassword:
            return .weakPassword
        case .emailAlreadyInUse:
            return .emailAlreadyInUse
        default:
            return .unknown(error.localizedDescription)
        }
    }
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        return String(nonce)
    }
}
