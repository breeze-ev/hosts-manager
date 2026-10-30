import SwiftUI

enum ProfilePalette {
    private static let palettes: [[Color]] = [
        [.blue, .cyan],
        [.orange, .red],
        [.teal, .green],
        [.indigo, .cyan],
        [.pink, .purple],
        [.mint, .teal],
        [.red, .orange],
        [.cyan, .blue]
    ]

    static func colors(for seed: String) -> [Color] {
        guard !seed.isEmpty else { return palettes[0] }
        var hash = 0
        for scalar in seed.unicodeScalars {
            hash = (hash &* 31 &+ Int(scalar.value)) & 0x7fffffff
        }
        return palettes[hash % palettes.count]
    }
}

struct ProfileAvatar: View {
    @ObservedObject var profile: Profile
    @EnvironmentObject private var l10n: Localization

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(
                    colors: ProfilePalette.colors(
                        for: profile.id?.uuidString ?? profile.localizedName(isEnglish: l10n.isEnglish)
                    ),
                    startPoint: .top,
                    endPoint: .bottom
                ))
            Text(String(profile.localizedName(isEnglish: l10n.isEnglish).prefix(1)))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 32, height: 32)
    }
}

#Preview("Profile Avatar") {
    HStack(spacing: 12) {
        ProfileAvatar(profile: PreviewFixtures.userProfile)
        ProfileAvatar(profile: PreviewFixtures.systemProfile)
    }
    .environmentObject(Localization())
    .padding()
}
