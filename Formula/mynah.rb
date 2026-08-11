class Mynah < Formula
  desc "Rate how clearly a message reads, and translate English to Russian, via Claude"
  homepage "https://github.com/axklim/mynah"
  url "https://github.com/axklim/mynah/archive/refs/tags/v0.2.1.tar.gz"
  sha256 "e1d742dcb78bee3e0d64b257c6a6f2cd60794cb0ec4273800274f91803f4542f"
  head "https://github.com/axklim/mynah.git", branch: "main"

  # Package.swift targets .macOS(.v13); Info.plist sets LSMinimumSystemVersion 13.0.
  depends_on macos: :ventura

  # Ships only the `mynah` CLI, which builds with the Command Line Tools alone. The
  # menu-bar app is deliberately absent: its KeyboardShortcuts dependency uses #Preview,
  # whose macro plugin ships only inside Xcode, so building it here would force every user
  # to install Xcode. See mynah-vault/Findings/preview-macro-needs-xcode.md.
  def install
    # SwiftPM wants a writable home for its caches; the real one is outside the build
    # sandbox, and without this it warns and disables user-level caching.
    ENV["HOME"] = buildpath/"brew-home"

    # --disable-sandbox: a brew build is already sandboxed, and the nested sandbox-exec
    # SwiftPM uses to compile Package.swift cannot start inside it ("Invalid manifest").
    # Going through `make install` keeps one definition of what "installed" means.
    system "make", "install", "PREFIX=#{prefix}", "SWIFT_FLAGS=--disable-sandbox"
  end

  def caveats
    <<~EOS
      mynah shells out to an authenticated `claude` CLI — there is no API key to set.
      Install Claude Code and sign in first, or every check fails.

        mynah check "i has finished the task and it works good"
        pbpaste | mynah translate

      The menu-bar app (global hotkeys) is not installed by this formula; building it
      needs full Xcode. Clone the repo and run `make app` for now.
    EOS
  end

  test do
    assert_match "mynah check", shell_output("#{bin}/mynah --help")

    # Catches the release mistake this formula cannot otherwise see: a tag cut without
    # bumping MynahVersion.swift, leaving the binary reporting the previous version.
    assert_equal version.to_s, shell_output("#{bin}/mynah --version").strip
  end
end
