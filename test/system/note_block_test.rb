require "application_system_test_case"

# The Note block on the public site, as the browser computes it (note block
# spec, "The public side"): each kind in its own four tokens in both schemes,
# the text, links and inline code in the theme's; on a strong band the
# band's ground with the kind's own colour on its rule and word (decision
# 10); and an editor's title seen alone and heard after the kind's word
# (decision 6).
class NoteBlockSystemTest < ApplicationSystemTestCase
  KINDS = BlockTypes::Note::KINDS.keys.freeze
  TEXT = "Read [the guide](https://example.com/guide) and run `bin/setup` first.".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Guide")
  end

  def add_note(kind, title: nil, **attributes)
    settings = { "kind" => kind, "title" => title }.compact
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "note", settings: settings }.merge(attributes),
      translations: { "en" => { body: rich_doc(TEXT) } })
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def open_page
    publish_changes(@page)
    visit PublicSite::Urls.new.path_for(@page, "en")
    assert_selector "aside.content-block--note"
  end

  def with_theme(theme)
    page.execute_script("document.documentElement.dataset.theme = arguments[0]", theme)
    yield
  ensure
    page.execute_script("document.documentElement.dataset.theme = 'light'")
  end

  # What a note is drawn in, and what its tokens are THERE: a probe span is
  # put inside the note, so a band's values are what it reads.
  def probe(block)
    page.evaluate_script(<<~JS, "note-#{block.id}-heading")
      (() => {
        const head = document.getElementById(arguments[0])
        const note = head.closest("aside")
        const kind = [...note.classList].find((name) => /^content-block--note-/.test(name)).replace("content-block--note-", "")
        const token = (name, property = "color") => { const span = document.createElement("span"); span.style[property] = `var(${name})`; note.append(span); const value = getComputedStyle(span)[property]; span.remove(); return value }
        const style = getComputedStyle(note)
        const code = note.querySelector(".note-body code")
        return {
          ground: style.backgroundColor, groundToken: token(`--th-note-${kind}-ground`, "backgroundColor"),
          rule: [style.borderLeftWidth, style.borderLeftColor], line: token(`--th-note-${kind}-line`),
          frame: [style.borderTopWidth, style.borderTopColor], border: token(`--th-note-${kind}-border`),
          word: getComputedStyle(head).color, ink: token(`--th-note-${kind}-ink`),
          text: getComputedStyle(note.querySelector(".note-body")).color, textToken: token("--th-ink"),
          link: getComputedStyle(note.querySelector(".note-body a")).color, accent: token("--th-accent"),
          code: [getComputedStyle(code).backgroundColor, getComputedStyle(code).borderTopWidth], surface: token("--th-surface", "backgroundColor"),
          icon: [head.querySelector("svg").getBoundingClientRect().width, head.querySelector("svg").getAttribute("aria-hidden")],
          named: note.getAttribute("aria-labelledby") === head.id, heading: head.textContent.trim(), bandInk: token("--th-on-band-strong"),
          band: token("--th-band-strong", "backgroundColor"), element: head.tagName
        }
      })()
    JS
  end

  test "each kind is drawn in its own tokens in both schemes: its ground, its 3px rule, its frame and its word, with the text, links and inline code the theme's" do
    notes = KINDS.map { |kind| add_note(kind) }
    open_page

    grounds = {}
    %w[light dark].each do |theme|
      with_theme(theme) do
        seen = notes.map { |block| probe(block) }
        grounds[theme] = seen.map { |found| found["ground"] }
        # An undefined ink token would leave word and token both the inherited
        # colour and pass the pairwise check below: four inks, four colours.
        assert_equal 4, seen.map { |found| found["ink"] }.uniq.size, "#{theme}: four kinds, four inks"
        seen.zip(KINDS).each do |found, kind|
          where = "#{theme}, #{kind}"
          assert_equal found["groundToken"], found["ground"], "#{where}: ground"
          assert_equal [ "3px", found["line"] ], found["rule"], "#{where}: rule"
          assert_equal [ "1px", found["border"] ], found["frame"], "#{where}: frame"
          assert_equal found["ink"], found["word"], "#{where}: word"
          assert_equal found["textToken"], found["text"], "#{where}: text"
          assert_equal found["accent"], found["link"], "#{where}: link"
          assert_equal [ found["surface"], "1px" ], found["code"], "#{where}: inline code"
          assert_equal [ 16, "true" ], found["icon"], "#{where}: icon"
          assert found["named"], "#{where}: the aside is named by its heading"
          assert_equal "H3", found["element"], "#{where}: the heading is a heading"
          assert_equal BlockTypes::Note::KINDS.fetch(kind), found["heading"]
        end
        assert_equal 4, seen.map { |found| found["ground"] }.uniq.size, "#{theme}: four kinds, four grounds"
      end
    end
    # The scheme switch took effect: every kind has another ground in the dark.
    KINDS.each_with_index do |kind, index|
      assert_not_equal grounds["light"][index], grounds["dark"][index], "#{kind}: the ground differs between light and dark"
    end
  end

  test "in a strong band a note shares the band's ground in both schemes, its text the band's, its rule and word its kind's own colour" do
    section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "one", "background" => "strong" } }).record
    inside = add_note("tip", section_id: section.id, section_column: 1)
    outside = add_note("tip")
    open_page
    assert_selector ".content-section--strong aside.content-block--note", count: 1

    %w[light dark].each do |theme|
      with_theme(theme) do
        banded = probe(inside)
        plain = probe(outside)
        assert_equal banded["band"], banded["ground"], "#{theme}: the band's ground"
        assert_equal banded["groundToken"], banded["ground"], "#{theme}: the note's ground token is the band's there"
        assert_equal banded["bandInk"], banded["text"], "#{theme}: the text is the band's ink"
        assert_equal banded["ink"], banded["word"], "#{theme}: the word is the kind's ink there"
        assert_equal [ "3px", banded["line"] ], banded["rule"], "#{theme}: the rule is the kind's line there"
        assert_not_equal banded["bandInk"], banded["word"], "#{theme}: the kind keeps a colour of its own on the band"
        assert_not_equal plain["ground"], banded["ground"], "#{theme}: not the page's tint"
      end
    end
  end

  # Spec decision 6: the kind's word before an editor's title is in the
  # heading's text, so a screen reader reads it, and takes no room on screen.
  test "an editor's title is seen alone and heard after the kind's word, in both schemes" do
    block = add_note("tip", title: "Before you publish")
    open_page

    %w[light dark].each do |theme|
      with_theme(theme) do
        found = page.evaluate_script(<<~JS, "note-#{block.id}-heading")
          (() => {
            const head = document.getElementById(arguments[0])
            const box = head.querySelector(".note-kind").getBoundingClientRect()
            return { said: head.textContent.replace(/\\s+/g, " ").trim(), width: box.width, height: box.height }
          })()
        JS
        assert_equal "Tip: Before you publish", found["said"], theme
        assert_operator found["width"], :<=, 1, "#{theme}: the word takes no room"
        assert_operator found["height"], :<=, 1, "#{theme}: the word takes no room"
      end
    end
  end
end
