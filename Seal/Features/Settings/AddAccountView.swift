import SwiftUI

struct AddAccountView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject private var verificationBroker: VerificationCodeBroker
    let replacingAccount: AppleAccountRecord?
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var verificationCode = ""
    @State private var selectedTeamID: String?
    @State private var authenticationTask: Task<Void, Never>?
    @State private var authenticationFailure: ImportFailure?
    @State private var hasAppeared = false

    init(viewModel: SettingsViewModel, replacingAccount: AppleAccountRecord? = nil) {
        self.viewModel = viewModel
        self.replacingAccount = replacingAccount
        verificationBroker = viewModel.verificationBroker
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let pending = viewModel.pendingAppleAuthentication {
                        teamSelectionContent(pending)
                    } else if verificationBroker.isRequested {
                        verificationContent
                    } else {
                        credentialsContent
                    }
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .navigationTitle(replacingAccount == nil ? "添加账号" : "重新验证")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(viewModel.accountPhase == .authenticating)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { cancelAuthentication(); dismiss() } } }
            .task { if let replacingAccount, email.isEmpty { email = await viewModel.email(for: replacingAccount) } }
            .onAppear {
                guard hasAppeared == false else { return }
                hasAppeared = true
                viewModel.cancelPendingAppleAuthentication()
            }
            .onDisappear {
                cancelAuthentication()
            }
            .alert(item: $authenticationFailure) { failure in
                Alert(title: Text(failure.title), message: Text(failure.userMessage), dismissButton: .default(Text(failure.recovery)))
            }
        }
        .sealScreenBackground()
    }

    private var credentialsContent: some View {
        Group {
            VStack(spacing: 10) {
                Image(systemName: "person.badge.key").font(.system(size: 46)).foregroundStyle(Color.sealAccent)
                Text("Apple ID").font(.title2.weight(.semibold))
                Text("用于个人 IPA 签名。凭据仅保存在本机钥匙串。")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(24).glassSurface(cornerRadius: 24)
            VStack(spacing: 0) {
                TextField("Apple ID", text: $email).textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().padding(.vertical, 15)
                Divider()
                SecureField("密码", text: $password).textContentType(.password).padding(.vertical, 15)
            }
            .padding(.horizontal, 16).glassSurface(cornerRadius: 24)
            Button {
                startAuthentication()
            } label: {
                if viewModel.accountPhase == .authenticating { ProgressView().frame(maxWidth: .infinity) }
                else { Text(replacingAccount == nil ? "添加" : "重新验证") }
            }
            .sealPrimaryAction()
            .disabled(primaryActionDisabled)
        }
    }

    private var verificationContent: some View {
        Group {
            VStack(spacing: 12) {
                Image(systemName: "lock.shield").font(.system(size: 48)).foregroundStyle(Color.sealAccent)
                Text("输入验证码").font(.title2.weight(.semibold))
                Text("请在受信任设备上允许登录，然后输入 Apple 发送的六位验证码。")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text(email).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 24)
            TextField("六位验证码", text: $verificationCode)
                .keyboardType(.numberPad).textContentType(.oneTimeCode).multilineTextAlignment(.center).font(.title2.monospacedDigit().weight(.semibold))
                .padding(.vertical, 16).background(Color.sealSurfaceElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onChange(of: verificationCode) { code in
                    verificationCode = String(code.filter(\.isNumber).prefix(6))
                }
            Text("允许登录后输入验证码。")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                verificationBroker.submit(verificationCode)
            } label: {
                if verificationBroker.hasSubmittedCode {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("验证")
                }
            }
            .sealPrimaryAction()
            .disabled(verificationCode.count < 6 || verificationBroker.hasSubmittedCode)
        }
    }

    private func teamSelectionContent(_ pending: PendingAppleAuthentication) -> some View {
        Group {
            VStack(spacing: 10) {
                Image(systemName: "person.3").font(.system(size: 46)).foregroundStyle(Color.sealAccent)
                Text("选择开发团队").font(.title2.weight(.semibold))
                Text("Seal 不会自动选择团队。请确认本次签名使用的开发团队。")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text(pending.maskedEmail).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(24).glassSurface(cornerRadius: 24)

            VStack(spacing: 10) {
                ForEach(pending.teams) { team in
                    Button {
                        selectedTeamID = team.id
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(team.name).font(.headline)
                                Text(team.isFreeTeam ? "免费个人团队" : team.identifier)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: selectedTeamID == team.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedTeamID == team.id ? Color.sealAccent : Color.secondary)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glassSurface(cornerRadius: 18)
                }
            }

            Button("确认团队") {
                completeAuthentication(pending)
            }
            .sealPrimaryAction()
            .disabled(selectedTeamID == nil || viewModel.accountPhase == .authenticating)

            Button("使用其他 Apple ID") {
                selectedTeamID = nil
                password = ""
                viewModel.cancelPendingAppleAuthentication()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var primaryActionDisabled: Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || viewModel.accountPhase == .authenticating
    }

    private func startAuthentication() {
        guard authenticationTask == nil else { return }
        viewModel.alertFailure = nil
        authenticationFailure = nil
        authenticationTask = Task { @MainActor in
            let isReadyForTeamSelection = await viewModel.beginAddingAccount(
                email: email,
                password: password
            )
            authenticationTask = nil
            if isReadyForTeamSelection, Task.isCancelled == false {
                email = ""
                password = ""
                let teams = viewModel.pendingAppleAuthentication?.teams ?? []
                selectedTeamID = teams.count == 1 ? teams.first?.id : nil
            } else if Task.isCancelled == false, let failure = viewModel.alertFailure {
                email = ""
                verificationCode = ""
                verificationBroker.cancel()
                viewModel.alertFailure = nil
                authenticationFailure = failure
            }
        }
    }

    private func completeAuthentication(_ pending: PendingAppleAuthentication) {
        guard authenticationTask == nil,
              let selectedTeamID,
              let team = pending.teams.first(where: { $0.id == selectedTeamID }) else { return }
        viewModel.alertFailure = nil
        authenticationFailure = nil
        authenticationTask = Task { @MainActor in
            let added = await viewModel.completeAddingAccount(
                team: team,
                replacing: replacingAccount
            )
            authenticationTask = nil
            if added, Task.isCancelled == false {
                dismiss()
            } else if Task.isCancelled == false, let failure = viewModel.alertFailure {
                viewModel.alertFailure = nil
                authenticationFailure = failure
            }
        }
    }

    private func cancelAuthentication() {
        authenticationTask?.cancel()
        authenticationTask = nil
        selectedTeamID = nil
        email = ""
        password = ""
        viewModel.cancelPendingAppleAuthentication()
    }
}
