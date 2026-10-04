require "test_helper"

# The translations matrix (design pass round 2, Task 18): a cell per target
# language linking to that language's editor, the row title and call to
# action following the first outdated, else first missing, language.
class Admin::TranslationScreen::MatrixComponentTest < ViewComponent::TestCase
  Item = Admin::TranslationsController::Item

  setup do
    Current.actor = users(:one)
    Current.channel = :admin
    with_locales(%w[en de es], default: "en")
    @post = create_post(title: "Welcome")
  end
  teardown { Current.reset }

  def matrix(*items) = render_inline(Admin::TranslationScreen::MatrixComponent.new(items:, locales: %w[de es]))

  def row = "#translation-item-post-#{@post.id}"

  test "an outdated row opens the outdated language and says Review changes" do
    matrix(Item.new(type: "post", record: @post, states: { "de" => :missing, "es" => :outdated }))

    assert_selector "#{row} th[scope=row] a[href='/cs-studio/posts/#{@post.id}?locale=es']", text: "Welcome"
    assert_selector "#{row} td a[href='/cs-studio/posts/#{@post.id}?locale=es']", text: "Review changes →"
    assert_selector "#{row} [data-locale=de][data-translation-state=missing]"
    assert_selector "#{row} [data-locale=es][data-translation-state=outdated]"
  end

  test "a missing-only row opens the first missing language and says Translate" do
    matrix(Item.new(type: "post", record: @post, states: { "de" => :complete, "es" => :missing }))

    assert_selector "#{row} th[scope=row] a[href='/cs-studio/posts/#{@post.id}?locale=es']"
    assert_selector "#{row} td a", text: "Translate →"
    # Each action link is told apart by its item (review C, M20).
    assert_selector "#{row} td a[aria-label^='Translate: ']"
  end

  test "a complete language in an incomplete row is the solid chip and still links" do
    matrix(Item.new(type: "post", record: @post, states: { "de" => :complete, "es" => :missing }))

    assert_selector "#{row} a[href='/cs-studio/posts/#{@post.id}?locale=de'] [data-locale=de][data-translation-state=complete]"
    assert_no_selector "#{row} [data-locale=de] .border-dashed"
  end

  test "each cell says its state in words, headers are real th elements" do
    matrix(Item.new(type: "post", record: @post, states: { "de" => :complete, "es" => :outdated }))

    assert_selector "#{row} a[aria-label='Welcome: Deutsch, translated']"
    assert_selector "#{row} a[aria-label='Welcome: Español, outdated']"
    assert_selector "thead th[scope=col]", text: "Deutsch"
    assert_selector "thead th[scope=col]", text: "Español"
    assert_selector "[data-translation-matrix-scroll].overflow-x-auto"
  end

  test "the site settings row links to Settings in that language" do
    matrix(Item.new(type: "settings", record: SiteSetting.first, states: { "de" => :complete, "es" => :missing }))

    assert_selector "#translation-item-settings th[scope=row] a[href='/cs-studio/settings?locale=es']", text: "Site settings"
  end

  test "nothing to show reads Everything is translated" do
    matrix

    assert_text "Everything is translated."
    assert_no_selector "table"
  end
end
