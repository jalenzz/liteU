import SwiftUI

struct LoginView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.ujingClient) private var client

    @State private var mobile = ""
    @State private var captcha = ""
    @State private var isSending = false
    @State private var isLoggingIn = false
    @State private var cooldown = 0
    @State private var errorMessage: String?
    @FocusState private var focused: Field?

    private enum Field {
        case mobile, captcha
    }

    var body: some View {
        Form {
            Section("账号") {
                TextField("手机号", text: $mobile)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .focused($focused, equals: .mobile)
                    .onChange(of: mobile) { _, value in
                        mobile = String(value.filter(\.isNumber).prefix(11))
                    }
                TextField("验证码", text: $captcha)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focused, equals: .captcha)
                    .onChange(of: captcha) { _, value in
                        captcha = String(value.filter(\.isNumber).prefix(8))
                    }
            }
            Section {
                Button(sendTitle) {
                    Task { await send() }
                }
                .disabled(!PhoneNumber.isValid(mobile) || isSending || cooldown > 0)
                Button("登录") {
                    Task { await login() }
                }
                .disabled(!PhoneNumber.isValid(mobile) || !CaptchaCode.isValid(captcha) || isLoggingIn)
            }
        }
        .navigationTitle("登录 U 净")
        .alert("无法登录", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear { focused = .mobile }
        .task(id: cooldown) {
            guard cooldown > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { cooldown -= 1 }
        }
    }

    private var sendTitle: String {
        if isSending { return "发送中…" }
        if cooldown > 0 { return "\(cooldown)s 后可重发" }
        return "获取验证码"
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            try await client.sendCaptcha(mobile)
            cooldown = 60
            focused = .captcha
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func login() async {
        isLoggingIn = true
        defer { isLoggingIn = false }
        do {
            let token = try await client.login(mobile, captcha)
            auth.save(token)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        LoginView()
            .environment(AuthStore())
            .environment(\.ujingClient, .live())
    }
}
