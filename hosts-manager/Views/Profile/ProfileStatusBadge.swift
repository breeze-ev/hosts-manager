import SwiftUI

struct ProfileStatusBadge: View {
    @ObservedObject var profile: Profile
    @EnvironmentObject private var l10n: Localization

    var body: some View {
        if profile.isSystem {
            badge
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().stroke(.quaternary))
                .foregroundStyle(.secondary)
        } else if profile.isAppliedForSystem {
            badge
                .background(Capsule().fill(.green.opacity(0.16)))
                .overlay(Capsule().stroke(.green.opacity(0.4)))
                .foregroundStyle(.green)
        } else {
            badge
                .background(Capsule().fill(.ultraThinMaterial))
                .foregroundStyle(.secondary)
        }
    }

    private var badge: some View {
        Text(detailProfileStatusText(for: profile, l10n: l10n))
            .font(.system(size: 11.5, weight: .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .accessibilityIdentifier("profile-status-badge")
    }
}

#Preview("Profile Status Badge") {
    ProfileStatusBadge(profile: PreviewFixtures.userProfile)
        .environmentObject(Localization())
        .padding(24)
}
