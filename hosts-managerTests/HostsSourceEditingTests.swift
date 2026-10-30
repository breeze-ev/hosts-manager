import Testing
@testable import hosts_manager

struct HostsSourceEditingTests {
    @Test func mixedSelectionOnlyAddsComments() {
        let result = HostsSourceEditing.toggledComment(
            in: "# already commented\nplain.local"
        )

        #expect(result == "# already commented\n# plain.local")
        #expect(result.contains("plain.local"))
    }

    @Test func commentedSelectionPreservesIndentationWhenUncommenting() {
        let result = HostsSourceEditing.toggledComment(
            in: "# first\n  # indented"
        )

        #expect(result == "first\n  indented")
    }

    @Test func blankLinesArePreserved() {
        let result = HostsSourceEditing.toggledComment(
            in: "one\n\n two"
        )

        #expect(result == "# one\n\n # two")
    }
}
