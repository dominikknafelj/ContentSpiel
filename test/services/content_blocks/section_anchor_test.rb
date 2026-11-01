require "test_helper"

# A Section's anchor (`BlockTypes::Section`'s `anchor` setting): the address
# of a link that jumps to the band, kept stable when the band is moved or
# restyled. One per page, in a fixed shape, and never rewritten for the editor.
class ContentBlocks::SectionAnchorTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Anchors")
    @section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "one" })
    @other = @page.content_blocks.create!(block_type: "section", position: 1, settings: { "layout" => "one" })
  end

  def save(section, anchor)
    ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "one", "anchor" => anchor } }, actor: nil)
  end

  test "an anchor of lowercase letters, digits and hyphens, a letter first, up to 40 characters, is saved as typed" do
    %w[services a-1 a].push("a" * 40).each do |anchor|
      result = save(@section, anchor)

      assert result.ok?, "#{anchor}: #{result.errors.to_sentence}"
      assert_equal anchor, @section.reload.settings["anchor"]
    end
  end

  test "an anchor that is uppercase, starts with a digit, holds a space or an underscore or is 41 characters is refused, never cleaned, and nothing is written" do
    save(@section, "kept")

    [ "Services", "1services", "two words", "snake_case", "a" * 41, "-dash", "café" ].each do |anchor|
      result = save(@section, anchor)

      assert_not result.ok?, "#{anchor.inspect} was accepted"
      assert_match(/lowercase letters, digits and hyphens/, result.errors.to_sentence)
      assert_equal "kept", @section.reload.settings["anchor"]
    end
  end

  test "an anchor that equals an id the public templates write is refused as taken, writes nothing, and the CMS's ids are listed in one place" do
    save(@section, "kept")

    %w[page-children-label note-12-heading note-7 code-3-file table-98-caption].each do |anchor|
      result = save(@section, anchor)

      assert_not result.ok?, "#{anchor} was accepted"
      assert_equal [ "`#{anchor}` is already taken by the page itself. Choose another anchor." ], result.errors
      assert_equal "kept", @section.reload.settings["anchor"]
    end
    %w[note-taking table-of-contents code-review page-children].each do |anchor|
      assert save(@section, anchor).ok?, "#{anchor} was refused"
    end
  end

  test "a blank anchor stores nothing: the key is absent" do
    save(@section, "services")

    result = save(@section, "  ")

    assert result.ok?
    assert_not @section.reload.settings.key?("anchor")
  end

  test "a second section of the page with the same anchor is refused with the message, writes nothing and is a 422 for the editor" do
    save(@section, "services")
    before = @other.reload.updated_at

    result = nil
    assert_no_difference -> { Audit::Event.count } do
      result = save(@other, "services")
    end

    assert_not result.ok?
    assert_equal [ "Another section on this page is already called `services`." ], result.errors
    assert_not @other.reload.settings.key?("anchor")
    assert_equal before, @other.updated_at
  end

  test "the section keeps its own anchor when it is saved again, and the same anchor on another page is fine" do
    save(@section, "services")
    elsewhere = create_page(title: "Elsewhere")
    section = elsewhere.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "one" })

    assert save(@section, "services").ok?
    assert save(section, "services").ok?
  end

  test "the database refuses a duplicate written around the service, on one page only" do
    save(@section, "services")

    assert_raises(ActiveRecord::RecordNotUnique) do
      ContentBlock.transaction(requires_new: true) { @other.update_columns(settings: { "layout" => "one", "anchor" => "services" }) }
    end

    elsewhere = create_page(title: "Elsewhere").content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "one" })
    assert_nothing_raised { elsewhere.update_columns(settings: { "layout" => "one", "anchor" => "services" }) }
  end

  test "duplicating a section clears the copy's anchor and saves, and the original keeps it" do
    save(@section, "services")

    result = ContentBlocks::Duplicate.call(@section.reload, actor: nil)

    assert result.ok?, result.errors.to_sentence
    assert_not result.record.reload.settings.key?("anchor")
    assert_equal "services", @section.reload.settings["anchor"]
  end

  test "a save takes the page's row lock before it looks at the other sections" do
    statements = capture_sql { save(@other, "services") }
    lock = statements.index { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }
    look = statements.index { |sql| sql.include?("->> 'anchor'") }

    assert lock && look && lock < look, statements.join("\n")
  end
end
