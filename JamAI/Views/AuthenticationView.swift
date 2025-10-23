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
    
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isSignUpMode = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingForgotPassword = false
    
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
                    
                    Text(isSignUpMode ? "Create your account" : "Sign in to continue")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 40)
                
                // Auth form
                VStack(spacing: 12) {
                    if isSignUpMode {
                        TextField("Display Name", text: $displayName)
                            .textFieldStyle(AuthTextFieldStyle())
                    }
                    
                    TextField("Email", text: $email)
                        .textFieldStyle(AuthTextFieldStyle())
                        .textContentType(.emailAddress)
                        // .autocapitalization(.none)  // iOS-only, not needed on macOS
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(AuthTextFieldStyle())
                        .textContentType(isSignUpMode ? .newPassword : .password)
                    
                    if !isSignUpMode {
                        HStack {
                            Spacer()
                            Button("Forgot Password?") {
                                showingForgotPassword = true
                            }
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                        }
                        .padding(.top, 4)
                    }
                    
                    // Email sign in/up button
                    Button {
                        handleEmailAuth()
                    } label: {
                        HStack {
                            if authService.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                            Text(isSignUpMode ? "Create Account" : "Sign In")
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
                    .padding(.top, 16)
                }
                .frame(width: 460)
                .padding(.bottom, 24)
                
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
                
                // Toggle sign up/in
                HStack(spacing: 4) {
                    Text(isSignUpMode ? "Already have an account?" : "Don't have an account?")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    Button(isSignUpMode ? "Sign In" : "Sign Up") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSignUpMode.toggle()
                        }
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
                if isSignUpMode {
                    _ = try await authService.signUp(
                        email: email,
                        password: password,
                        displayName: displayName.isEmpty ? nil : displayName
                    )
                } else {
                    _ = try await authService.signIn(email: email, password: password)
                }
                
                // Clear any persisted tabs to show welcome screen after login
                UserDefaults.standard.removeObject(forKey: "lastOpenedProjectURL")
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
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
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 15))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(10)
    }
}

#Preview {
    AuthenticationView()
}
