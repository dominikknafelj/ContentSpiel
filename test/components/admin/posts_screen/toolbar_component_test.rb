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
    assert_selector "form[method=get][data-controller='admin--ui--auto-submit'][data-turbo-frame=content]"
    assert_selector "fieldset legend", text: "Show", visible: :all
    assert_selector "label[for=posts-scope-all]", text: /All\s*128/
    assert_selector "label[for=posts-scope-live]", text: /Live\s*96/
    assert_selector "label[for=posts-scope-drafts]", text: /Drafts\s*20/
    assert_selector "label[for=posts-scope-scheduled]", text: /Scheduled\s*12/
    assert_selector "input[type=radio][name=scope]", count: 4, visible: :all
    assert_selector "input#posts-scope-drafts[checked]", visible: :all
  end

  test "search and the three drop-downs are labelled for a screen reader and keep their values" do
    render_toolbar(filters: { q: "hello", type: "blog", tag: "rails", translation: "outdated" })
    assert_selector "label.sr-only[for=q]", text: "Search titles"
    assert_selector "input#q[value=hello]"
    assert_selector "select#type option[selected][value=blog]"
    assert_selector "select#tag option[selected][value=rails]"
    assert_selector "select#translation option[selected][value=outdated]"
    assert_selector "select#translation option", text: "Translation: Any"
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
