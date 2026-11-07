require "test_helper"

class Admin::PostsScreen::ToolbarComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }
  teardown { Current.reset }

  def render_toolbar(scope: "all", filters: {}, **options)
    render_inline Admin::PostsScreen::ToolbarComponent.new(scope:, counts: { "all" => 128, "live" => 96, "drafts" => 20, "scheduled" => 12 },
      content_types: ContentTypes.all, tags: [ Tag.new(name: "rails") ], filters: { q: nil, type: nil, tag: nil, translation: nil }.merge(filters), **options)
  end

  test "the checked segment is bold as well as tinted" do
    render_toolbar(scope: "drafts")
    assert_selector "label[class*='has-[:checked]:font-semibold']", count: 4
  end

  test "a GET form that applies as it changes, with the four counts in a radio group" do
    render_toolbar(scope: "drafts")
    assert_selector "form#posts-filters[method=get][data-controller='admin--ui--auto-submit'][data-turbo-frame=content]"
    bar = page.find("form#posts-filters .admin-filter-bar")
    bar.assert_selector "fieldset legend", text: "Show", visible: :all
    bar.assert_selector "label[for=posts-scope-all]", text: /All\s*128/
    bar.assert_selector "label[for=posts-scope-live]", text: /Live\s*96/
    bar.assert_selector "label[for=posts-scope-drafts]", text: /Drafts\s*20/
    bar.assert_selector "label[for=posts-scope-scheduled]", text: /Scheduled\s*12/
    bar.assert_selector "input[type=radio][name=scope]", count: 4, visible: :all
    bar.assert_selector "input#posts-scope-drafts[checked]", visible: :all
  end

  test "the segments are the list's own scopes, in its order" do
    render_toolbar
    assert_equal Posts::List::SCOPES, page.all("input[type=radio][name=scope]", visible: :all).map(&:value)
  end

  test "one form holds the bar and the panel, drawn as contents, and applies as it changes" do
    render_toolbar
    assert_selector "form", count: 1
    form = page.find("form#posts-filters.contents[data-controller='admin--ui--auto-submit']")
    form.assert_selector ".admin-filter-bar input#q"
    form.assert_selector ".admin-filter-bar input[type=radio][name=scope]", count: 4, visible: :all
    form.assert_selector ".admin-filter-panel select#translation"
    assert_no_selector "form.admin-filter-bar"
  end

  test "search is labelled for a screen reader, and Type, Tag and Translation stand under visible labels in the filter panel, keeping their values" do
    render_toolbar(filters: { q: "hello", type: "blog", tag: "rails", translation: "outdated" })
    assert_selector "label.sr-only[for=q]", text: "Search titles"
    assert_selector "input#q[value=hello]"
    panel = page.find("form#posts-filters fieldset.admin-list-rail__rail.admin-filter-panel")
    panel.assert_selector "legend", text: "Filters"
    { "type" => "Type", "tag" => "Tag", "translation" => "Translation" }.each do |id, words|
      panel.assert_selector "label[for=#{id}]:not(.sr-only)", text: words
    end
    panel.assert_selector "select#type option[value='']", text: "All"
    panel.assert_selector "select#tag option[value='']", text: "Any"
    panel.assert_selector "select#translation option[value='']", text: "Any"
    panel.assert_selector "select#type option[selected][value=blog]"
    panel.assert_selector "select#tag option[selected][value=rails]"
    panel.assert_selector "select#translation option[selected][value=outdated]", text: "Outdated"
    assert_equal [ "", "needs", "outdated", "complete" ], panel.all("select#translation option").map(&:value)
  end

  test "a tag filter that names no tag shows that name as the chosen option, so the filter can be seen and cleared" do
    render_inline Admin::PostsScreen::ToolbarComponent.new(scope: "all", counts: { "all" => 0, "live" => 0, "drafts" => 0, "scheduled" => 0 },
      content_types: ContentTypes.all, tags: [ Tag.new(name: "music") ], filters: { q: nil, type: nil, tag: "gone", translation: nil })
    assert_selector "select#tag option[selected]", text: "gone"
    assert_selector "select#tag option", text: "music"
    assert_selector "a", text: "Clear"
  end

  test "the tag options are the tags' names, and a known filter is not added twice" do
    component = Admin::PostsScreen::ToolbarComponent.new(scope: "all", counts: {}, content_types: [], tags: [ Tag.new(name: "music") ],
      filters: { q: nil, type: nil, tag: "music", translation: nil })
    assert_equal [ "music" ], component.tag_options
  end

  test "Clear shows only while something is active, and the editing locale rides along" do
    render_toolbar
    assert_no_selector "a", text: "Clear"
    assert_no_selector "input[name=locale]", visible: :all

    render_toolbar(scope: "live", locale: "de")
    assert_selector "a[href='/cs-studio/posts'][data-turbo-frame=content]", text: "Clear"
    assert_selector "input[name=locale][value=de]", visible: :all

    render_toolbar(filters: { tag: "rails" })
    assert_selector "a", text: "Clear"
  end

  # Contrast and buttons spec (D1): a selected pill is inverted, ink with
  # paper words (the accent tint was 1.13:1 against the others), and its
  # keyboard ring is paper, since the accent on dark ink is 1.96:1.
  test "a selected pill is inverted, its count with it, and its focus ring is paper" do
    classes = Admin::PostsScreen::ToolbarComponent::SEGMENT_CLASS.split

    %w[has-[:checked]:bg-ink has-[:checked]:text-paper has-[:checked]:has-[:focus-visible]:outline-paper has-[:checked]:has-[:focus-visible]:-outline-offset-4].each do |name|
      assert_includes classes, name
    end
    assert_empty classes.grep(/accent-tint/)
  end
end
