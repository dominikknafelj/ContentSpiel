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

  test "a type filter that names no registered type shows that name as the chosen option, and a known one is not added twice" do
    render_inline Admin::PostsScreen::ToolbarComponent.new(scope: "all", counts: { "all" => 0, "live" => 0, "drafts" => 0, "scheduled" => 0 },
      content_types: ContentTypes.all, tags: [], filters: { q: nil, type: "gone_type", tag: nil, translation: nil })
    assert_selector "select#type option[selected][value=gone_type]", text: "gone_type"

    component = Admin::PostsScreen::ToolbarComponent.new(scope: "all", counts: {}, content_types: ContentTypes.all, tags: [],
      filters: { q: nil, type: "blog", tag: nil, translation: nil })
    assert_equal ContentTypes.all.map { |type| [ type.label, type.name ] }, component.type_options
  end

  test "the translation options are the states Posts::List filters by" do
    render_inline Admin::PostsScreen::ToolbarComponent.new(scope: "all", counts: { "all" => 0, "live" => 0, "drafts" => 0, "scheduled" => 0 },
      content_types: [], tags: [], filters: { q: nil, type: nil, tag: nil, translation: nil })
    assert_equal [ "" ] + Posts::List::TRANSLATIONS, page.all("select#translation option").map(&:value)
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

  # The scope is the shared segmented control's radios: its look is the
  # component's (`Admin::Ui::SegmentedComponentTest`), and the toolbar only
  # hands it the scopes.
  test "the scope is the shared segmented control's radios, the chosen scope checked" do
    render_toolbar(scope: "drafts")

    assert_selector "fieldset label.group\\/segment", count: Posts::List::SCOPES.size
    assert_equal Admin::Ui::SegmentedComponent::RADIO_SEGMENT_CLASS, page.find("label[for=posts-scope-drafts]")[:class]
    assert_selector "label[for=posts-scope-drafts] > input[type=radio][name=scope][value=drafts][checked].sr-only", visible: :all
  end
end
