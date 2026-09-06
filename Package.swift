// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LinearNotes",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "NotesCore", targets: ["NotesCore"]), .executable(name: "LinearNotes", targets: ["LinearNotes"])],
    targets: [
        .target(name: "NotesCore"),
        .executableTarget(name: "LinearNotes", dependencies: ["NotesCore"], resources: [.copy("Resources/Editor")]),
        .testTarget(name: "NotesCoreTests", dependencies: ["NotesCore"])
    ]
)
