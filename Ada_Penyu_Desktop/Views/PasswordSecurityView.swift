import SwiftUI

struct PasswordSecurityView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var model: PasswordSecurityModel
    let onBack: () -> Void

    @FocusState private var focusedField: Field?

    private enum Field {
        case current, new, confirm
    }

    var body: some View {
        SettingsDetailScaffold(
            title: "Password & Security",
            subtitle: "Update the password for your AdaPenyu account.",
            isBackDisabled: model.isSubmitting,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 20) {
                if let message = model.accessMessage {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lock")
                            .font(.system(size: 18))
                            .foregroundStyle(AdaColors.navy)
                            .frame(width: 40, height: 40)
                            .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(AdaColors.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdaColors.card, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous)
                            .stroke(AdaColors.line, lineWidth: 1)
                    )
                } else {
                    formCard
                }
            }
        }
        .onAppear {
            model.clearMessages()
            if model.canChangePassword {
                focusedField = .current
            }
        }
        .onDisappear {
            model.clearForm()
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let denied = model.accessDeniedMessage {
                SettingsStatusBanner(style: .error, message: denied)
            }
            if let error = model.errorMessage {
                SettingsStatusBanner(style: .error, message: error)
            }

            passwordField(
                label: "Current Password",
                placeholder: "Enter current password",
                text: $model.currentPassword,
                isVisible: $model.isCurrentPasswordVisible,
                field: .current,
                nextField: .new,
                accessibilityID: "settings.password.current"
            )

            if let currentError = model.currentPasswordError {
                Text(currentError)
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, -10)
                    .accessibilityIdentifier("settings.password.currentError")
            }

            VStack(alignment: .leading, spacing: 6) {
                passwordField(
                    label: "New Password",
                    placeholder: "Enter new password",
                    text: $model.newPassword,
                    isVisible: $model.isNewPasswordVisible,
                    field: .new,
                    nextField: .confirm,
                    accessibilityID: "settings.password.new"
                )
                Text("Your password must be at least 8 characters with a mix of letters, number, and symbols")
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            passwordField(
                label: "Confirm New Password",
                placeholder: "Confirm new password",
                text: $model.confirmNewPassword,
                isVisible: $model.isConfirmPasswordVisible,
                field: .confirm,
                nextField: nil,
                accessibilityID: "settings.password.confirm"
            )

            Text("After changing your password, you will be signed out on this Mac so you can sign in again with your new password.")
                .font(.system(size: 12))
                .foregroundStyle(AdaColors.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(action: submit) {
                    HStack(spacing: 8) {
                        if model.isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Text("Update password")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(model.canSubmit || model.isSubmitting ? .white : AdaColors.secondaryInk)
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .background(model.canSubmit || model.isSubmitting ? AdaColors.navy : AdaColors.canvas, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!model.canSubmit)
                .accessibilityIdentifier("settings.password.updateButton")

                Spacer(minLength: 0)
            }
        }
        .padding(24)
        .background(AdaColors.card, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous)
                .stroke(AdaColors.line, lineWidth: 1)
        )
        .disabled(model.isSubmitting)
    }

    private func passwordField(
        label: LocalizedStringKey,
        placeholder: LocalizedStringKey,
        text: Binding<String>,
        isVisible: Binding<Bool>,
        field: Field,
        nextField: Field?,
        accessibilityID: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AdaColors.ink)

            HStack(spacing: 10) {
                Group {
                    if isVisible.wrappedValue {
                        TextField(placeholder, text: text)
                    } else {
                        SecureField(placeholder, text: text)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focusedField, equals: field)
                .accessibilityIdentifier(accessibilityID)
                .onSubmit {
                    if let nextField {
                        focusedField = nextField
                    } else if model.canSubmit {
                        submit()
                    }
                }

                Button {
                    isVisible.wrappedValue.toggle()
                } label: {
                    Image(systemName: isVisible.wrappedValue ? "eye" : "eye.slash")
                        .font(.system(size: 14))
                        .foregroundStyle(AdaColors.secondaryInk)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isVisible.wrappedValue ? "Hide password" : "Show password")
                .accessibilityLabel(isVisible.wrappedValue ? "Hide password" : "Show password")
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(focusedField == field ? AdaColors.navy : AdaColors.line, lineWidth: focusedField == field ? 1.5 : 1)
            )
        }
    }

    private func submit() {
        Task {
            await model.submit {
                store.completePasswordChangeSignOut()
            }
        }
    }
}
