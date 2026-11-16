require "application_system_test_case"

# The History screen in a browser (version history spec §3, R14–R16; the
# StudioHistory card): the versions on the lists' rail, the comparison of one
# version with another through its one auto-submitting GET form, and a
# restore that lands in the editor with the version's text as unpublished
# changes. A visitor is a session of its own that never signs in.
class Admin::VersionHistorySystemTest < ApplicationSystemTestCase
  HEADER = "header.admin-editor-header".freeze
  VERSIONS = "[data-history-versions]".freeze
  COMPARISON = "[data-history-comparison]".freeze
  # The window at which the page's History docks its rail beside the tree
  # (1200px of the list's own width), and one at which it folds.
  DOCKED = 1900
  FOLDED = 1100

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @me = users(:one).tap { |user| user.update!(name: "Olga Braun") }
    Current.set(actor: @me) do
      @page = create_page(title: "Pricing", published: false)
      @block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }, translations: { "en" => { body: rich_doc("First words") } }).record
      assert Pages::Save.call(@page, attributes: { published: true }).ok?
      assert Pages::Save.call(@page.reload, translations: { "en" => { title: "Pricing and plans" } }).ok?
      assert ContentBlocks::Save.call(@block.reload, translations: { "en" => { body: rich_doc("Second words") } }).ok?
      publish_changes(@page)
      assert Pages::Save.call(@page.reload, translations: { "en" => { title: "Pricing for everyone" } }).ok?
    end
    @address = PublicSite::Urls.new.path_for(@page, "en")
    sign_in_via_form(@me)
  end

  teardown do
    page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}")
  end

  def history = admin_page_history_path(@page)

  def block_text = @block.reload.body_document(locale: "en").to_markdown.strip

  # Whether every element `selector` finds has a box on the screen.
  def drawn?(selector)
    page.evaluate_script("[...document.querySelectorAll(arguments[0])].every((element) => element.getBoundingClientRect().height > 0)", selector) &&
      page.evaluate_script("document.querySelectorAll(arguments[0]).length", selector).positive?
  end

  # A choice in the comparison's form submits it (`admin--ui--auto-submit`):
  # a GET that draws the screen again.
  def compare_with(label)
    click_frame_link { find("#{COMPARISON} select[name=with]").select(label) }
  end

  test "History lists the versions, a version is compared with the one before it and with the working version, and restoring it lands in the editor with its text unpublished" do
    at_window(DOCKED) do
      visit_editor(@page)
      open_editor_menu
      click_frame_link "History"

      assert_current_path history
      assert_selector "h1", text: "Pricing for everyone"
      assert_selector "nav [aria-current=page]", text: "History"
      assert_link "Back to editor", href: admin_page_path(@page)

      # Docked, the rows stand in the rail without opening anything. The rail
      # is the `<details>` itself, closed, its content drawn by the
      # stylesheet (`::details-content`): the driver counts what a closed
      # `<details>` holds as hidden, so the rows are found with
      # `visible: :all` and their being drawn is read from their boxes.
      assert_no_selector "#{VERSIONS} summary"
      assert drawn?("#{VERSIONS} [data-version-row]"), "the docked rail draws its rows"
      within VERSIONS do
        rows = all("[data-version-row]", visible: :all).map { |row| row["data-version-row"] }
        assert_equal %w[working 2 1], rows
        assert_selector "[data-version-row=working]", text: "Working version", visible: :all
        within(find("[data-version-row='2']", visible: :all)) do
          assert_selector ".admin-status-chip", text: "Live", visible: :all
          assert_selector "a[aria-current=true]", text: "Version 2", visible: :all
          assert_selector "p", text: "Olga Braun", visible: :all
        end
        assert_no_selector "[data-version-row='1'] .admin-status-chip", visible: :all
      end

      # Version 2 with the one before it: what that publish changed.
      within COMPARISON do
        assert_selector "h2", text: "Version 2"
        assert_equal "previous", find("select[name=with]").value
        assert_text "the version before it (1)"
        assert_text "Second"
        assert_text "plans"
        assert_no_text "everyone"
        assert_button "Restore version 2…"
      end

      # With the working version: what has been saved since it.
      compare_with "the working version"
      assert_current_path(/with=working/)
      within COMPARISON do
        assert_selector "h2", text: "Version 2"
        assert_equal "working", find("select[name=with]").value
        assert_text "everyone"
      end

      # Another version, chosen in the rail, keeps the other side.
      click_frame_link { find("#{VERSIONS} a", text: "Version 1", visible: :all).click }
      assert_selector "#{VERSIONS} a[aria-current=true]", text: "Version 1", visible: :all
      within COMPARISON do
        assert_selector "h2", text: "Version 1"
        assert_equal "working", find("select[name=with]").value
        assert_no_selector "select[name=with] option[value=previous]", visible: :all
        assert_text "First"
      end

      press "Restore version 1…"
      within "dialog#history-restore[open]" do
        assert_text "Restore version 1?"
        assert_text "Nothing is published: the site keeps showing version 2 until you publish the changes."
        press "Restore version 1"
      end

      assert_current_path admin_page_path(@page)
      assert_text "Version 1 restored as unpublished changes. Publish changes… puts it on the site."
      assert_selector "h1", text: "Pricing"
      assert_no_selector "h1", text: "Pricing for everyone"
      assert_selector "#content_block_#{@block.id} .ProseMirror", text: "First words"
      assert_selector "#{HEADER} #publishing-chip [data-unpublished-changes]"
    end

    assert_equal "Pricing", Mobility.with_locale(:en) { @page.reload.title }
    assert_equal "First words", block_text
    assert_equal 2, Publishing.current(@page).number, "a restore publishes nothing"
    using_session(:visitor) do
      visit @address
      assert_text "Second words"
      assert_no_text "First words"
    end
  end

  test "below the rail's threshold the versions fold above the comparison and choosing one closes them" do
    at_window(FOLDED) do
      visit_screen history

      within VERSIONS do
        assert_selector "summary", text: "Version 2"
        assert_selector "summary", text: "2 versions"
        assert_no_link "Version 1"
      end
      assert_equal false, page.evaluate_script("document.querySelector('#{VERSIONS}').open")
      # Folded, the versions stand above the comparison.
      assert page.evaluate_script(<<~JS), "the folded versions stand above the comparison"
        document.querySelector("#{VERSIONS}").getBoundingClientRect().bottom <= document.querySelector("#{COMPARISON}").getBoundingClientRect().top
      JS

      find("#{VERSIONS} summary").click
      within(VERSIONS) { assert_link "Version 1" }

      click_frame_link { find("#{VERSIONS} a", text: "Version 1").click }

      within VERSIONS do
        assert_selector "summary", text: "Version 1"
        assert_no_link "Version 1"
      end
      assert_equal false, page.evaluate_script("document.querySelector('#{VERSIONS}').open")
      within(COMPARISON) { assert_selector "h2", text: "Version 1" }
    end
  end
end
