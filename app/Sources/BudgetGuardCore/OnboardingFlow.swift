import Foundation

public enum OnboardingStep: Equatable {
    case welcome, login, check, settings, done
}

public enum OnboardingEvent: Equatable {
    case start, loggedIn, checkSucceeded, continueTapped, backToLogin
}

public enum OnboardingTransition: Equatable {
    case stay
    case go(OnboardingStep)
    case close
}

/// Step sequencing of the assistant, kept pure so it can be tested without any UI.
public enum OnboardingFlow {
    /// `reconnect`: the assistant was opened from « Se reconnecter à Claude… » and closes once the check succeeds.
    public static func next(from step: OnboardingStep, event: OnboardingEvent, reconnect: Bool = false) -> OnboardingTransition {
        switch (step, event) {
        case (.welcome, .start): return .go(.login)
        case (.login, .loggedIn): return .go(.check)
        case (.check, .checkSucceeded): return reconnect ? .close : .stay
        case (.check, .continueTapped): return .go(.settings)
        case (.check, .backToLogin): return .go(.login)
        case (.settings, .continueTapped): return .go(.done)
        case (.done, .continueTapped): return .close
        default: return .stay
        }
    }

    /// Only finishing the last step marks the assistant as completed; any earlier close shows it again next launch.
    public static func marksCompleted(closingFrom step: OnboardingStep) -> Bool { step == .done }
}
