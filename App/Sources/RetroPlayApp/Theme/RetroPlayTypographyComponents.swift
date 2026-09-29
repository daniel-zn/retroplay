// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

@available(iOS 18.0, *)
@MainActor
struct RetroPlayAlertAction: Identifiable {
    enum Role {
        case standard
        case cancel
        case destructive
    }

    let id = UUID()
    let title: String
    let role: Role
    let perform: @MainActor () -> Void

    static func standard(_ title: String, perform: @escaping @MainActor () -> Void = {}) -> Self {
        Self(title: title, role: .standard, perform: perform)
    }

    static func cancel(_ title: String, perform: @escaping @MainActor () -> Void = {}) -> Self {
        Self(title: title, role: .cancel, perform: perform)
    }

    static func destructive(_ title: String, perform: @escaping @MainActor () -> Void) -> Self {
        Self(title: title, role: .destructive, perform: perform)
    }
}

@available(iOS 18.0, *)
@MainActor
private struct RetroPlayAlertModifier: ViewModifier {
    let title: String
    let message: String
    @Binding var isPresented: Bool
    let actions: [RetroPlayAlertAction]

    func body(content: Content) -> some View {
        content
            .disabled(isPresented)
            // VoiceOver stays inside the alert card instead of wandering behind it.
            .accessibilityHidden(isPresented)
            .overlay {
                if isPresented {
                    ZStack {
                        Color.black.opacity(0.45)
                            .ignoresSafeArea()

                        VStack(spacing: 14) {
                            Text(title)
                                .font(RetroPlayFont.title3)
                                .multilineTextAlignment(.center)

                            Text(message)
                                .font(RetroPlayFont.body)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                ForEach(actions) { action in
                                    Button {
                                        isPresented = false
                                        action.perform()
                                    } label: {
                                        Text(action.title)
                                            .font(RetroPlayFont.subheadline)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(tint(for: action.role))
                                }
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: 360)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(.white.opacity(0.16))
                        }
                        .padding(24)
                        .accessibilityElement(children: .contain)
                        .accessibilityAddTraits(.isModal)
                        .accessibilityLabel("\(title). \(message)")
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(10)
                }
            }
            .animation(.easeOut(duration: 0.16), value: isPresented)
    }

    private func tint(for role: RetroPlayAlertAction.Role) -> Color {
        switch role {
        case .standard:
            return RetroPlayTheme.accent
        case .cancel:
            return .secondary
        case .destructive:
            return .red
        }
    }
}

@available(iOS 18.0, *)
extension View {
    @MainActor
    func retroPlayAlert(
        _ title: String,
        message: String,
        isPresented: Binding<Bool>,
        actions: [RetroPlayAlertAction]
    ) -> some View {
        modifier(
            RetroPlayAlertModifier(
                title: title,
                message: message,
                isPresented: isPresented,
                actions: actions
            )
        )
    }
}

@available(iOS 18.0, *)
struct RetroPlayUnavailableView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .imageScale(.large)
                .foregroundStyle(.secondary)
            Text(title)
                .font(RetroPlayFont.title3)
                .multilineTextAlignment(.center)
            Text(description)
                .font(RetroPlayFont.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
