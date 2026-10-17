import LocalAuthentication

/// Face ID in front of History.
///
/// The entries are the private part of this app: what you just dictated is on screen anyway,
/// but everything you have ever written is one tap away without this.
enum Lock {
    enum Outcome: Equatable {
        case unlocked
        /// Cancelled deliberately. Not an error, and not worth telling the user what they just did.
        case cancelled
        case failed(String)
    }

    static func authenticate() async -> Outcome {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        // deviceOwnerAuthentication, not the biometrics-only policy: a mask, a dark room or a
        // broken sensor would otherwise lock you out of your own journal with no way back in.
        // This falls through to the passcode instead.
        let policy = LAPolicy.deviceOwnerAuthentication

        var availability: NSError?
        guard context.canEvaluatePolicy(policy, error: &availability) else {
            // No passcode and no biometrics. There is nothing to authenticate against, and
            // refusing would seal the entries away for good on a phone that is not protecting
            // anything else either. Open rather than lock out.
            return .unlocked
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: "Unlock your journal") { success, error in
                if success {
                    continuation.resume(returning: .unlocked)
                } else if let error = error as? LAError,
                          error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
                    continuation.resume(returning: .cancelled)
                } else {
                    continuation.resume(returning: .failed(error?.localizedDescription ?? "Couldn't unlock."))
                }
            }
        }
    }
}
