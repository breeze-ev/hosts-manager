import SwiftUI

struct OperationErrorAlert: ViewModifier {
    let title: String
    @Binding var error: String?

    func body(content: Content) -> some View {
        content.alert(
            title,
            isPresented: Binding(
                get: { error != nil },
                set: { isPresented in
                    if !isPresented {
                        error = nil
                    }
                }
            )
        ) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }
}
