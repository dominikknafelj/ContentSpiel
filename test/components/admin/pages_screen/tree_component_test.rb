require "test_helper"

# The page tree's cost profile with translation markers on (final fix wave,
# I1/T4): the tree is re-rendered after every page-settings autosave, so it
# must cost the same handful of queries however many pages (and blocks) it
# shows; its markers are one read of the stored `translation_states`.
class Admin::PagesScreen::TreeComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }

  def paragraph(text) = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => text } ] } ] }

  def add_pages(count, prefix)
    Array.new(count) do |index|
      page = create_page(title: "#{prefix} #{index}", translations: { "de" => { title: "#{prefix} #{index} (de)" } })
      result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
        translations: { "en" => { body: paragraph("Hello") }, "de" => { body: paragraph("Hallo") } })
      assert result.ok?, result.errors.to_sentence
      page
    end
  end

  def render_tree = render_inline(Admin::PagesScreen::TreeComponent.new(root: root_page.reload, locale: "en"))

  # Every statement sent, cached or not (the same counting the tree's
  # access-control query test uses): a per-row query shows up either way.
  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end

  test "the tree with translation markers costs the same queries for 3 pages as for 30" do
    with_locales(%w[en de es], default: "en") do
      add_pages(3, "Small")
      render_tree # warm up whatever a first render loads once
      small = count_queries { render_tree }

      add_pages(27, "Large")
      large = count_queries { render_tree }

      assert_selector "li.admin-tree-node", minimum: 31
      assert_equal small, large, "the tree ran a query per page"
    end
  end

  # Handoff §10 B24: "↻N" outdated and "○N" missing, summed over the target
  # languages, no box, no "!", the tooltip naming the languages.
  test "a row shows outdated and missing counts summed over the languages, with labels and a tooltip" do
    with_locales(%w[en de es], default: "en") do
      row = create_page(title: "Counted", translations: { "en" => { title: "Counted", subtitle: "Sub" }, "de" => { title: "Gezählt", subtitle: "Unter" } })
      assert Pages::Save.call(row, translations: { "en" => { title: "Counted again", subtitle: "Sub!" } }).ok?
      render_tree

      assert_selector "li[data-page-id='#{row.id}'] > div [data-translation-marker=outdated][role=img]", text: "↻2",
        count: 1
      marker = page_node(row).find("[data-translation-marker=outdated]")
      assert_equal "2 outdated translations: Deutsch", marker["aria-label"]
      assert_equal "Deutsch: 2 outdated", marker["title"]
      missing = page_node(row).find("[data-translation-marker=missing]")
      assert_equal "○1", missing.text
      assert_equal "1 missing translation: Español", missing["aria-label"]
      assert_equal "Español: 1 missing", missing["title"]
      assert_no_selector "[data-translation-marker]", text: "!"
    end
  end

  test "a complete page shows neither count" do
    with_locales(%w[en de], default: "en") do
      done = create_page(title: "Done", translations: { "de" => { title: "Fertig" } })
      render_tree
      assert_no_selector "li[data-page-id='#{done.id}'] > div [data-translation-marker]"
    end
  end

  test "the header names the tree and offers New page" do
    render_tree
    assert_selector "h2", text: "Pages"
    assert_selector "a[href='/cs-studio/pages/new']", text: "+ New page"
  end

  test "the header's New page and each row's + open the New page dialog, the row presetting Inside" do
    about = create_page(title: "About")
    render_tree
    assert_selector "a[href='/cs-studio/pages/new'][data-action='admin--dialog#open'][data-admin--dialog-id-param=new-page-dialog]", text: "+ New page"
    assert_selector "li[data-page-id='#{about.id}'] > div a[data-action='admin--dialog#open'][data-admin--dialog-id-param=new-page-dialog][data-new-page-parent-id-param='#{about.id}'][href='/cs-studio/pages/new?parent_id=#{about.id}']", visible: :all
  end

  test "the starter offer sits in the header menu only while Home is the only kept page" do
    render_tree
    assert_selector "[role=menu] button", text: "Create starter pages", visible: :all
    create_page(title: "About")
    render_tree
    assert_no_selector "[role=menu] button", text: "Create starter pages", visible: :all
  end

  def page_node(record) = page.find("li[data-page-id='#{record.id}'] > div")

  test "a re-render after one page's save shows that page's new marker and leaves the others alone" do
    with_locales(%w[en de], default: "en") do
      pages = add_pages(4, "Page")
      render_tree

      assert Pages::Save.call(pages.first, translations: { "en" => { title: "Page 0, revised" } }).ok?
      render_tree

      assert_selector "li[data-page-id='#{pages.first.id}'] > div [data-translation-marker=outdated][title*='Deutsch']"
      assert_no_selector "li[data-page-id='#{pages.second.id}'] [data-translation-marker=outdated][title*='Deutsch']"
    end
  end

  test "a live page shows no status chip; a draft does" do
    live = create_page(title: "Live one")
    draft = create_page(title: "Draft one", published: false)
    render_tree
    assert_no_selector "li[data-page-id='#{live.id}'] > div .admin-status-chip"
    assert_selector "li[data-page-id='#{draft.id}'] > div .admin-status-chip", text: "Draft"
  end

  test "a page without children shows no child count" do
    parent = create_page(title: "Parent")
    create_page(title: "Child", parent: parent)
    leaf = create_page(title: "Leaf")
    render_tree
    assert_no_selector "li[data-page-id='#{leaf.id}'] > div [data-child-count]"
    assert_selector "li[data-page-id='#{parent.id}'] > div [data-child-count]", text: "1"
  end

  test "the full title is available as a tooltip when the row truncates" do
    leaf = create_page(title: "A rather long page title that the narrow tree column will cut off")
    render_tree
    assert_selector "li[data-page-id='#{leaf.id}'] > div a[title='#{leaf.title}']"
  end
end
