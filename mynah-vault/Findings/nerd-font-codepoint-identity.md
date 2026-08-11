# Finding — Nerd Font coverage ≠ identity; and how to test coverage correctly

- **Date:** 2026-08-04
- **Context:** picking the status-item glyph set for [[0008-nerd-font-status-icons]].

## Two separate questions

Choosing a Nerd Font glyph raises two questions that are easy to conflate:

1. **Coverage** — does this font contain that codepoint? Answerable in code.
2. **Identity** — is the glyph at that codepoint the icon the name suggests? Answerable only by
   looking at it.

## Coverage: use the character set, not the glyph lookup

The obvious API is wrong for half the range:

```swift
CTFontGetGlyphsForCharacters(font, &utf16, &glyphs, count)   // ✗ false negatives
CTFontCopyCharacterSet(font) as CharacterSet                  // ✓ correct
```

`CTFontGetGlyphsForCharacters` works in **UTF-16 code units**, so any codepoint above U+FFFF
arrives as a surrogate pair and reports 0 glyphs — a false negative. Nerd Fonts v3 relocated the
whole **Material Design** block to **U+F0001+**, which is above U+FFFF, so the first coverage sweep
reported every `nf-md-*` glyph as missing while all Font Awesome ones (U+F0xx–F2xx, in the BMP)
passed. Re-checking with `CTFontCopyCharacterSet` showed JetBrainsMono Nerd Font covers **all** of
them.

## Identity: names from memory are unreliable

With coverage confirmed, glyphs were still wrong, because the *name → codepoint* pairings quoted
from memory did not survive the v2 → v3 renumbering:

| assumed | actually renders as |
|---|---|
| `nf-md-ruler` U+F0595 | something like a small vase |
| `nf-md-book_open_variant` U+F0E0F | **the AWS logo** |
| `nf-md-spellcheck` U+F0630 | a person with dots |

Font Awesome codepoints (U+F0xx–F2xx) matched their names every time; the Material Design block did
not match once. The fix was to render every candidate large, with its hex label, and pick from the
picture — which is how `empty` became U+F016 (outlined page) instead of a clipboard glyph that read
as "copy", `tooLong` became U+F02D (a closed book — "you copied a book"), and a genuine 文A
translate glyph turned up at U+F05CA and earned the translator its own icon state.

## Takeaway

- Verify coverage with `CTFontCopyCharacterSet`; anything above U+FFFF needs it.
- **Never trust a Nerd Font glyph name from memory** — render the candidate and look. Prefer the
  Font Awesome range when a suitable glyph exists there.
- This is the same lesson the dotfiles repo recorded for tmux (glyph choice "by evidence rather
  than taste"), reached independently through a different failure.
- A rendered PNG proves colour and shape only. Vertical centring in a real `NSStatusItem` still has
  to be eyeballed.

## Related

[[0008-nerd-font-status-icons]] · [[ad-hoc-translator]] · [[phase2-menubar-evaluator]]
