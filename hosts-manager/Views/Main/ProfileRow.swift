import SwiftUI

struct ProfileRow: View {
    @ObservedObject var profile: Profile
    let isSelected: Bool
    @EnvironmentObject private var l10n: Localization

    var body: some View {
        HStack(spacing: 10) {
            ProfileAvatar(profile: profile)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.localizedName(isEnglish: l10n.isEnglish))
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Text(meta)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var meta: String {
        if profile.isSystem { return l10n.s("系统只读", "System") }
        if !profile.isAppliedForSystem { return l10n.s("已停用", "Disabled") }
        let on = profile.sortedEntries.filter(\.isEnabled).count
        return l10n.s("已应用 · \(on) 条启用", "Applied · \(on) enabled")
    }
}

#Preview("Profile Row") {
    ProfileRow(profile: PreviewFixtures.userProfile, isSelected: false)
        .environmentObject(Localization())
        .padding()
        .frame(width: 280)
}
