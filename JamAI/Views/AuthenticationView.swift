//
//  AuthenticationView.swift
//  JamAI
//
//  Main authentication screen with email and Google Sign-In
//

import SwiftUI
// import AuthenticationServices  // Commented out - not needed without Apple Sign-In

struct AuthenticationView: View {
    
    @StateObject private var authService = FirebaseAuthService.shared
    @StateObject private var dataService = FirebaseDataService.shared
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var email = ""
    @State private var password = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingForgotPassword = false

    private enum FocusField {
        case email
        case password
    }

    @FocusState private var focusedField: FocusField?
    
    var body: some View {
        ZStack {
            // Clean background
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Logo and title
                VStack(spacing: 16) {
                    Image("AppLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                    
                    Text("Welcome to Jam AI")
                        .font(.system(size: 32, weight: .bold))
                    
                    Text("Sign in to continue")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 40)
                
                // Auth form
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email")
                            .font(.system(size: 14, weight: .medium))
                        
                        TextField("you@example.com", text: $email)
                            .textFieldStyle(
                                AuthTextFieldStyle(
                                    isFocused: focusedField == .email,
                                    isDarkMode: colorScheme == .dark
                                )
                            )
                            .focused($focusedField, equals: .email)
                            .textContentType(.emailAddress)
                            // .autocapitalization(.none)  // iOS-only, not needed on macOS
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password")
                            .font(.system(size: 14, weight: .medium))
                        
                        SecureField("••••••••", text: $password)
                            .textFieldStyle(
                                AuthTextFieldStyle(
                                    isFocused: focusedField == .password,
                                    isDarkMode: colorScheme == .dark
                                )
                            )
                            .focused($focusedField, equals: .password)
                            .textContentType(.password)
                    }
                    
                    HStack {
                        Spacer()
                        Button("Forgot Password?") {
                            showingForgotPassword = true
                        }
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                    }
                    
                    // Email sign in button
                    Button {
                        handleEmailAuth()
                    } label: {
                        HStack {
                            if authService.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                            Text("Sign In")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(authService.isLoading || email.isEmpty || password.isEmpty)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 28)
                .frame(width: 420)
                .background(
                    Group {
                        if colorScheme == .dark {
                            Color.white.opacity(0.04)
                        } else {
                            Color(nsColor: .controlBackgroundColor)
                        }
                    }
                )
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.55 : 0.08), radius: 22, y: 18)
                .padding(.bottom, 32)
                
                // OAuth buttons - Temporarily disabled due to SDK issues
                // // Divider
                // HStack {
                //     Rectangle()
                //         .fill(Color.secondary.opacity(0.3))
                //         .frame(height: 1)
                //     Text("OR")
                //         .font(.system(size: 13, weight: .medium))
                //         .foregroundColor(.secondary)
                //         .padding(.horizontal, 12)
                //     Rectangle()
                //         .fill(Color.secondary.opacity(0.3))
                //         .frame(height: 1)
                // }
                // .frame(width: 380)
                // .padding(.bottom, 24)
                //
                // VStack(spacing: 12) {
                //     // Google Sign-In
                //     Button {
                //         handleGoogleSignIn()
                //     } label: {
                //         HStack(spacing: 12) {
                //             Image(systemName: "g.circle.fill")
                //                 .font(.system(size: 20))
                //             Text("Continue with Google")
                //                 .font(.system(size: 15, weight: .medium))
                //         }
                //         .frame(maxWidth: .infinity)
                //         .frame(height: 50)
                //         .background(Color(nsColor: .controlBackgroundColor))
                //         .cornerRadius(12)
                //         .overlay(
                //             RoundedRectangle(cornerRadius: 12)
                //                 .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                //         )
                //     }
                //     .buttonStyle(.plain)
                //
                //     // Apple Sign-In - Commented out until credentials are available
                //     // SignInWithAppleButton(.signIn) { request in
                //     //     request.requestedScopes = [.fullName, .email]
                //     // } onCompletion: { result in
                //     //     handleAppleSignIn(result: result)
                //     // }
                //     // .signInWithAppleButtonStyle(.black)
                //     // .frame(height: 50)
                //     // .cornerRadius(12)
                // }
                // .frame(width: 380)
                
                Spacer()
                
                // Sign up on website
                HStack(spacing: 4) {
                    Text("Need an account?")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    Button("Sign up on website") {
                        openSignupPage()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
                }
                .padding(.bottom, 32)
            }
        }
        .alert("Authentication Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Reset Password", isPresented: $showingForgotPassword) {
            TextField("Email", text: $email)
            Button("Cancel", role: .cancel) {}
            Button("Send Reset Link") {
                handlePasswordReset()
            }
        } message: {
            Text("Enter your email to receive a password reset link")
        }
    }
    
    // MARK: - Actions
    
    private func handleEmailAuth() {
        Task {
            do {
                _ = try await authService.signIn(email: email, password: password)
                
                // Clear any persisted tabs to show welcome screen after login
                UserDefaults.standard.removeObject(forKey: "lastOpenedProjectURL")
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func openSignupPage() {
        guard let url = URL(string: "https://www.usejamai.com/") else { return }
        NSWorkspace.shared.open(url)
    }
    
    // Google Sign-In handler - Temporarily disabled due to SDK issues
    // private func handleGoogleSignIn() {
    //     Task {
    //         do {
    //             _ = try await authService.signInWithGoogle()
    //         } catch {
    //             errorMessage = error.localizedDescription
    //             showingError = true
    //         }
    //     }
    // }
    
    // Apple Sign-In handler - Commented out until credentials are available
    // private func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
    //     Task {
    //         do {
    //             switch result {
    //             case .success(let authorization):
    //                 _ = try await authService.signInWithApple(authorization: authorization)
    //             case .failure(let error):
    //                 throw error
    //             }
    //         } catch {
    //             errorMessage = error.localizedDescription
    //             showingError = true
    //         }
    //     }
    // }
    
    private func handlePasswordReset() {
        Task {
            do {
                try await authService.sendPasswordReset(email: email)
                errorMessage = "Password reset email sent! Check your inbox."
                showingError = true
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}

// MARK: - Custom Text Field Style

struct AuthTextFieldStyle: TextFieldStyle {
    var isFocused: Bool = false
    var isDarkMode: Bool = false
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        let background: Color = isDarkMode
            ? Color.white.opacity(0.06)
            : Color(nsColor: .textBackgroundColor)
        
        return configuration
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isFocused ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.35),
                        lineWidth: 1
                    )
            )
            .cornerRadius(10)
    }
}

#Preview {
    AuthenticationView()
}
