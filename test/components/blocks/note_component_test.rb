require "test_helper"

# `Blocks::NoteComponent` (note block spec, "The public side"): an aside
# named by its heading (an h3), the kind's icon and word or the editor's
# title after the kind's word hidden for a screen reader (decision 6), and
# the text; nothing for a note without text.
class Blocks::NoteComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  def note_block(kind: "tip", title: nil, body: "Mind the **gap**.", titles: {})
    block = root_page.content_blocks.new(block_type: :note, position: 0, settings: { "kind" => kind })
    block.assign_settings({ "title" => title }, locale: "en") if title
    titles.each { |locale, text| block.assign_settings({ "title" => text }, locale: locale) }
    block.assign_body(rich_doc(body), locale: :en) if body
    block.save!
    block
  end

  def draw(block) = render_inline(Blocks::NoteComponent.new(block: block, page: root_page))

  def heading(block) = page.find("#note-#{block.id}-heading")

  # What a screen reader reads of the heading: every text in it, the hidden
  # word included, with its white space collapsed.
  def said(block) = heading(block).text(:all).squish

  test "each kind is an aside named by its heading, with its own word, icon and class, and never an alert" do
    { "note" => %w[Note info], "tip" => %w[Tip lightbulb], "important" => %w[Important circle-alert], "warning" => %w[Warning triangle-alert] }.each do |kind, (word, icon)|
      block = note_block(kind: kind)
      draw(block)

      assert_selector "aside.content-block.content-block--note.content-block--note-#{kind}[aria-labelledby='note-#{block.id}-heading']", count: 1
      assert_selector "aside > h3.note-head#note-#{block.id}-heading", count: 1
      assert_equal word, said(block)
      assert_selector "#note-#{block.id}-heading svg.note-icon[data-icon='#{icon}'][aria-hidden='true'][width='16'][height='16']", visible: :all
      assert_selector "aside .note-body.cs-prose strong", text: "gap"
      assert_no_selector "[role='alert'], [aria-live]"
    end
  end

  # Spec decision 6 (Claude Design D4c): under an editor's title the kind is
  # still heard, once, before the title and inside the heading, so it is in
  # a list of headings too; it is not seen.
  test "an editor's title replaces the word on screen, the word is heard once before it, hidden, and the icon and the kind stay" do
    block = note_block(kind: "warning", title: "Before you publish")
    draw(block)

    assert_equal "Warning: Before you publish", said(block)
    assert_selector "#note-#{block.id}-heading .note-kind", count: 1, text: /\AWarning:\s*\z/, visible: :all
    assert_equal 1, said(block).scan("Warning").size, "the kind is said once"
    assert_selector "aside.content-block--note-warning svg[data-icon='triangle-alert']", visible: :all
  end

  test "without a title the heading is the kind's word alone, said once, and there is no hidden word" do
    block = note_block(kind: "tip")
    draw(block)

    assert_equal "Tip", said(block)
    assert_no_selector ".note-kind", visible: :all
  end

  # Review focus 1.
  test "a title of only white space is no title: the heading is the kind's word, said once" do
    block = note_block(kind: "tip", title: "   ")
    draw(block)

    assert_equal "Tip", said(block)
    assert_no_selector ".note-kind", visible: :all
    assert_empty block.reload.translated_settings, "nothing is stored for it"
  end

  # Review focus 6: "Tip: Tip" would say the kind twice.
  test "a title that is only the kind's word is no title: the word is said once" do
    block = note_block(kind: "tip", title: "tip")
    draw(block)

    assert_equal "Tip", said(block)
    assert_no_selector ".note-kind", visible: :all
  end

  # Review focus 2.
  test "a stored kind that is not on the list is drawn as a Note" do
    block = note_block(kind: "tip")
    block.update_columns(settings: { "kind" => "danger" }) # version: none (a test writes a kind around the services, as a console would)
    draw(block.reload)

    assert_selector "aside.content-block--note-note"
    assert_equal "Note", said(block)
    assert_selector "svg[data-icon='info']", visible: :all
    assert_no_selector ".content-block--note-danger"
  end

  # Spec decision 5, and review focus 3.
  test "a note without text draws nothing, whatever its title" do
    draw(note_block(title: "A title alone", body: nil))
    assert_equal "", rendered_content.strip

    draw(note_block(body: ""))
    assert_equal "", rendered_content.strip
  end

  # Review focus 4.
  test "a visitor of another language reads the text with the site's fallback, the title in their language where there is one, and the word in English where their language has no words" do
    with_locales(%w[en de es], default: "en") do
      titled = note_block(kind: "tip", title: "Before you publish", titles: { "de" => "Vor dem Veröffentlichen" })
      plain = note_block(kind: "tip")

      I18n.with_locale(:de) do
        draw(titled)
        assert_equal "Tip: Vor dem Veröffentlichen", said(titled), "German has no words file: the hidden word is English"
        assert_selector ".note-body strong", text: "gap"
        draw(plain)
        assert_equal "Tip", said(plain)
      end
      I18n.with_locale(:es) do
        draw(titled)
        assert_equal "Tip: Before you publish", said(titled), "no Spanish title: the default language's"
      end
    end
  end

  # The text is the rich-text renderer's, whose escaping is held in
  # test/models/rich_text; the title is what this component prints.
  test "a title that looks like markup is text" do
    block = note_block(title: %(<script>alert(1)</script><b>x</b>), body: "Words.")
    draw(block)

    assert_no_selector "script, b", visible: :all
    assert_includes said(block), "<script>alert(1)</script><b>x</b>"
  end
end
