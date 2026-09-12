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

        Writes are headless too: the CLI loads Everlog's own compiled \
        CoreData model from the app bundle and saves through it with \
        persistent-history tracking, the same multi-process pattern the \
        Everlog widget uses. The app's CloudKit sync picks the changes up \
        like any other local edit. No Shortcuts, no app activation.
        """,
        version: "0.2.0",
        subcommands: [
            Journals.self,
            Tags.self,
            Show.self,
            Search.self,
            Read.self,
            OnThisDay.self,
            Random.self,
            Watch.self,
            New.self,
            Append.self,
            Attach.self,
            Bookmark.self,
            Place.self,
            WeatherCmd.self,
            Trash.self,
            ExportCmd.self,
        ],
        defaultSubcommand: nil
    )
}
