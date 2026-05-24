import ArgumentParser

@main
struct EverlogCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "everlog",
        abstract: "Unofficial command-line interface for the Everlog (Hummingbird) journaling app.",
        discussion: """
        Reads your Everlog journal directly via the Hummingbird SQLite store \
        (~/Library/Group Containers/group.hummingbird/Hummingbird.sqlite). \
        Snapshots the live DB to /tmp/ before querying so we never fight \
        the running app for the file. All read operations are headless — \
        Everlog.app is not launched or activated.

        Write subcommands (Phase 2) will wrap Everlog's Shortcuts actions \
        (Create Entry, Append Text to Entry, etc.) via the macOS `shortcuts` \
        CLI or, eventually, direct AppIntents bindings.
        """,
        version: "0.1.0",
        subcommands: [
            Journals.self,
            Tags.self,
            Show.self,
            Search.self,
            Read.self,
            OnThisDay.self,
            Random.self,
            New.self,
            Append.self,
        ],
        defaultSubcommand: nil
    )
}
