import Testing
@testable import hosts_manager

struct HostsLineDiffTests {
    @Test func reportsChangedLinesWithoutDuplicatingUnchangedContent() {
        let diff = HostsLineDiff.compare(
            before: "one\ntwo\ntwo\n",
            after: "one\ntwo\nthree\n"
        )

        #expect(diff.removed == ["two"])
        #expect(diff.added == ["three"])
    }

    @Test func identicalLargeInputsAreHandledLinearly() {
        let content = (0..<20_000)
            .map { "10.0.0.\($0 % 255) host-\($0).local" }
            .joined(separator: "\n")

        let diff = HostsLineDiff.compare(before: content, after: content)

        #expect(diff.isEmpty)
    }
}
