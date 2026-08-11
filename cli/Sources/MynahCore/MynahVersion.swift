/// The single place the project's version is written down.
///
/// `make app` substitutes this into the bundle's `Info.plist`, and the Homebrew formula
/// asserts that `mynah --version` matches the release tarball it built from — so bumping
/// this one line is the whole version bump. See `make version` and Decision 0010.
public enum MynahVersion {
    public static let current = "0.2.1"
}
