/// The Nerd Font used for the status-item glyphs, by PostScript name — not the
/// filename `JetBrainsMonoNerdFont-Regular.ttf`. Declared once here, rather than
/// duplicated as a literal in both `StatusItemController` and
/// `IconFontCoverageTests`, so the two can never quietly drift apart.
///
/// The **proportional** variant, not `JetBrainsMonoNFM-Regular`: the Mono
/// variant forces every glyph into one fixed terminal cell, which squeezes the
/// wide icons, and the menu bar shows one glyph at a time so there is nothing
/// to align to.
public enum IconFont {
    public static let postScriptName = "JetBrainsMonoNF-Regular"
}
