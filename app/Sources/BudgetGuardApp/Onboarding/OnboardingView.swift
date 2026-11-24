import SwiftUI
import BudgetGuardCore

enum CheckState {
    case reading
    case success(UsageSnapshot)
    case unsupportedPlan
    case failed
}

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var step: OnboardingStep = .welcome
    @Published var check: CheckState = .reading
    @Published var launchAtLogin = true
    @Published var alertsEnabled = true
    @Published var applying = false

    var loginView: NSView?
    var onStart: () -> Void = {}
    var onContinue: () -> Void = {}
    var onRetry: () -> Void = {}
    var onBackToLogin: () -> Void = {}
    var onQuit: () -> Void = {}
}

private let stepOrder: [OnboardingStep] = [.welcome, .login, .check, .settings, .done]

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            StepDots(current: model.step)
                .padding(.top, 22)
                .padding(.bottom, 12)
            Group {
                switch model.step {
                case .welcome: WelcomeStep(model: model)
                case .login: LoginStep(model: model)
                case .check: CheckStep(model: model)
                case .settings: SettingsStep(model: model)
                case .done: DoneStep(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 560, height: 760)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct StepDots: View {
    let current: OnboardingStep
    var body: some View {
        HStack(spacing: 8) {
            ForEach(stepOrder, id: \.self) { s in
                Circle()
                    .fill(s == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

private struct PrimaryButton: View {
    let title: String
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .semibold)).frame(width: 260, height: 30)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(disabled)
    }
}

private struct StepLayout<Content: View, Footer: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            content.padding(.horizontal, 48)
            Spacer(minLength: 0)
            footer.padding(.bottom, 44).padding(.horizontal, 48)
        }
    }
}

private func bodyText(_ s: String) -> some View {
    Text(s)
        .font(.system(size: 20))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
}

private struct WelcomeStep: View {
    @ObservedObject var model: OnboardingModel
    var body: some View {
        StepLayout {
            VStack(spacing: 24) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
                Text("Bienvenue").font(.system(size: 34, weight: .bold))
                bodyText("Budget Guard affiche en permanence, en haut de votre écran, la part de votre limite Claude de la semaine que vous avez déjà utilisée.")
            }
        } footer: {
            PrimaryButton(title: "Commencer") { model.onStart() }
        }
    }
}

private struct LoginStep: View {
    @ObservedObject var model: OnboardingModel
    var body: some View {
        if let v = model.loginView {
            EmbeddedView(view: v).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct EmbeddedView: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct CheckStep: View {
    @ObservedObject var model: OnboardingModel
    var body: some View {
        switch model.check {
        case .reading:
            StepLayout {
                VStack(spacing: 20) {
                    ProgressView().controlSize(.large)
                    bodyText("Lecture de votre consommation…")
                }
            } footer: { Color.clear.frame(height: 30) }
        case .success(let snap):
            successView(snap)
        case .unsupportedPlan:
            StepLayout {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 52)).foregroundColor(.orange)
                    bodyText(Copy.unsupportedPlan)
                }
            } footer: {
                PrimaryButton(title: "Quitter") { model.onQuit() }
            }
        case .failed:
            StepLayout {
                VStack(spacing: 20) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 52)).foregroundColor(.orange)
                    bodyText("Impossible de lire votre consommation pour le moment.")
                }
            } footer: {
                VStack(spacing: 14) {
                    PrimaryButton(title: "Réessayer") { model.onRetry() }
                    Button("Revenir à la connexion") { model.onBackToLogin() }
                        .buttonStyle(.link)
                        .font(.system(size: 15))
                }
            }
        }
    }

    private func successView(_ snap: UsageSnapshot) -> some View {
        let display = makeMenuDisplay(snapshot: snap, error: nil, now: Date(), calendar: .current)
        let tint = StatusItemController.color(display.tone).map(Color.init(nsColor:)) ?? .accentColor
        return StepLayout {
            VStack(spacing: 22) {
                Text(Copy.percentTitle(snap.weeklyPercent))
                    .font(.system(size: 84, weight: .bold, design: .rounded))
                    .monospacedDigit()
                ProgressView(value: Double(min(max(snap.weeklyPercent, 0), 100)), total: 100)
                    .tint(tint)
                    .frame(width: 280)
                bodyText(Copy.usageSentence(snap.weeklyPercent) + ".")
                if let reset = snap.resetsAt {
                    Text(Copy.resetLine(reset, now: Date(), calendar: .current))
                        .font(.system(size: 17))
                        .foregroundColor(.secondary)
                }
            }
        } footer: {
            PrimaryButton(title: "Continuer") { model.onContinue() }
        }
    }
}

private struct SettingsStep: View {
    @ObservedObject var model: OnboardingModel
    var body: some View {
        StepLayout {
            VStack(alignment: .leading, spacing: 28) {
                Text("Réglages").font(.system(size: 34, weight: .bold)).frame(maxWidth: .infinity)
                Toggle(isOn: $model.launchAtLogin) {
                    Text("Lancer Budget Guard au démarrage du Mac").font(.system(size: 18))
                }
                Toggle(isOn: $model.alertsEnabled) {
                    Text("M’alerter à 80\u{202F}% et à 95\u{202F}%").font(.system(size: 18))
                }
            }
            .toggleStyle(.switch)
        } footer: {
            VStack(spacing: 18) {
                Text("macOS va vous demander si Budget Guard peut vous envoyer des notifications : répondez « Autoriser ».")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: "Continuer", disabled: model.applying) { model.onContinue() }
            }
        }
    }
}

private struct DoneStep: View {
    @ObservedObject var model: OnboardingModel
    var body: some View {
        StepLayout {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundColor(.green)
                bodyText("C’est prêt ! Votre pourcentage s’affiche en haut à droite de l’écran, à côté de l’heure.")
            }
        } footer: {
            PrimaryButton(title: "Fermer") { model.onContinue() }
        }
    }
}
