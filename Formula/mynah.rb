class Mynah < Formula
  desc "Rate how clearly a message reads, and translate English to Russian, via Claude"
  homepage "https://github.com/axklim/mynah"
  url "https://github.com/axklim/mynah/archive/refs/tags/v0.2.1.tar.gz"
  sha256 "e1d742dcb78bee3e0d64b257c6a6f2cd60794cb0ec4273800274f91803f4542f"
  head "https://github.com/axklim/mynah.git", branch: "main"

  # Package.swift targets .macOS(.v13); Info.plist sets LSMinimumSystemVersion 13.0.
  depends_on macos: :ventura

  # Ships both products, and both build with the Command Line Tools alone — no Xcode. The app
  # used to be absent because its KeyboardShortcuts dependency uses #Preview, whose macro
  # plugin lives only inside Xcode; `make app` now patches those blocks out of the pinned
  # checkout first. See mynah-vault/Findings/preview-macro-needs-xcode.md.
  #
  # Building the bundle rather than installing the prebuilt mynah-app-<version>.zip is a
  # deliberate choice, not a quarantine workaround — Decision 0010 verified that formula
  # downloads are not quarantined either. It keeps one artifact per release, and it makes
  # `brew install --HEAD` install an app actually built from HEAD.
  def install
    # SwiftPM wants a writable home for its caches; the real one is outside the build
    # sandbox, and without this it warns and disables user-level caching.
    ENV["HOME"] = buildpath/"brew-home"

    # --disable-sandbox: a brew build is already sandboxed, and the nested sandbox-exec
    # SwiftPM uses to compile Package.swift cannot start inside it ("Invalid manifest").
    # Going through make keeps one definition of what "built" and "installed" mean.
    system "make", "install", "PREFIX=#{prefix}", "SWIFT_FLAGS=--disable-sandbox"
    system "make", "app", "SWIFT_FLAGS=--disable-sandbox"

    prefix.install "cli/dist/Mynah.app"
  end

  # opt_prefix, not prefix, so the launch agent's command survives upgrades. It does not make
  # the app's identity stable: launching through the opt symlink resolves to the versioned
  # Cellar path (measured — the running process reports Cellar/mynah/<version>/Mynah.app), and
  # the bundle is only ad-hoc signed, so expect macOS to re-ask for permission after an upgrade.
  # See the vault Finding gui-claude-subprocess-tcc-prompt.
  service do
    run opt_prefix/"Mynah.app/Contents/MacOS/Mynah"
  end

  def caveats
    <<~EOS
      mynah shells out to an authenticated `claude` CLI — there is no API key to set.
      Install Claude Code and sign in first, or every check fails.

        mynah check "i has finished the task and it works good"
        pbpaste | mynah translate

      The menu-bar app is installed at:
        #{opt_prefix}/Mynah.app

      It has no Dock icon — it lives in the menu bar. ⌃⌥⌘C checks the clipboard, ⌃⌥⌘⇧C
      translates it to Russian. Start it now and at every login with:

        brew services start mynah

      To launch it by hand instead, or to find it in Spotlight:

        ln -sfn #{opt_prefix}/Mynah.app ~/Applications/Mynah.app
    EOS
  end

  test do
    assert_match "mynah check", shell_output("#{bin}/mynah --help")

    # Catches the release mistake this formula cannot otherwise see: a tag cut without
    # bumping MynahVersion.swift, leaving the binary reporting the previous version.
    assert_equal version.to_s, shell_output("#{bin}/mynah --version").strip

    # The app bundle is generated, not copied: Info.plist comes from Info.plist.in with the
    # version substituted in, and a bundle whose plist never got substituted still "exists".
    assert_predicate prefix/"Mynah.app/Contents/MacOS/Mynah", :executable?
    assert_match version.to_s, (prefix/"Mynah.app/Contents/Info.plist").read
  end
end
