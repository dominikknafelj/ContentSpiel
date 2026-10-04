require "test_helper"

class Admin::LanguagesTest < ActionDispatch::IntegrationTest
  # Only needed by the carried-in post-level test below (Task 9, from Task
  # 8's review) -- see `test/support/test_types.rb`'s own comment for why
  # every file that calls `with_test_types` includes this module itself.
  include TestTypes

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    @page = create_page(title: "About")
  end

  # Fix (final-fixes round, finding 5): the modules column's own Dashboard/
  # Pages/Posts/Tags links used to drop `?locale=` outright, silently
  # bouncing an editor back to `Locales.default` the moment they followed
  # one while working in another language.
  test "the modules column's own links keep the editing locale" do
    get "/cs-studio/pages/#{@page.id}", params: { locale: "de" }

    assert_select "nav[aria-label='Modules'] a[href='/cs-studio?locale=de']"
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/pages?locale=de']"
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/posts?locale=de']"
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/tags?locale=de']"
  end

  test "the switcher lists enabled languages and marks missing ones" do
    get "/cs-studio/pages/#{@page.id}"
    assert_select "nav[aria-label='Languages'] a", Locales.enabled.size - 1
    assert_select "nav[aria-label='Languages'] [title='Missing required fields']"
  end

  # Fix (final-fixes round, finding 1): the switcher lives inside the
  # layout's own `<turbo-frame id="content">`, so without `_top` targeting
  # a locale switch would only ever refresh that frame -- the page tree
  # outside it (`Admin::TreeNodeComponent#title` reads the current locale)
  # would keep showing every node's title in whichever language was
  # selected before the switch.
  test "the switcher's own links target the top level, not just the content frame" do
    get "/cs-studio/pages/#{@page.id}"
    assert_select "nav[aria-label='Languages'] a[data-turbo-frame='_top']"
  end

  test "in another language the primary original is shown read-only with a translate slot" do
    get "/cs-studio/pages/#{@page.id}", params: { locale: "de" }
    assert_select "[data-original-for='title'] p", text: "About"
    assert_select "[data-translate-slot='title']"
  end

  test "saving in de leaves en untouched" do
    patch "/cs-studio/pages/#{@page.id}", params: { locale: "de", page: { title: "Über uns" }, base_updated_at: @page.updated_at.iso8601(6) }, as: :turbo_stream
    assert_equal "Über uns", @page.reload.title(locale: :de)
    assert_equal "About", @page.title(locale: :en)
  end

  # `limit` is a post_list block's own untranslated schema field (`t.field
  # :limit, :integer, min: 1` -- no `translated: true`) -- on a non-default
  # locale it is no longer an input at all but a read-only line in the card's
  # "Shared fields" list (design pass round 2, Task 7), and a forged save of
  # it must still never write a `translated_settings["de"]` entry the way a
  # *translated* field's own save would.
  test "a block's untranslated field is listed under Shared fields, and saving it in a non-default locale never creates a translated entry" do
    result = ContentBlocks::Save.call(@page.content_blocks.new, attributes: { block_type: "post_list", settings: { limit: 3 } })
    assert result.ok?, result.errors.to_sentence
    block = result.record

    get "/cs-studio/pages/#{@page.id}", params: { locale: "de" }
    assert_select "[data-field-name='limit']", count: 0
    assert_select "input[name='block[settings][limit]']", count: 0
    assert_select "details.admin-shared-fields", text: /Limit/
    assert_select "details.admin-shared-fields", text: /3/

    patch "/cs-studio/pages/#{@page.id}/content_blocks/#{block.id}",
      params: { locale: "de", block: { settings: { limit: 5 } }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success

    block.reload
    assert_equal 5, block.settings["limit"]
    assert_not block.translated_settings.key?("de")
  end

  # Carried in from Task 8's review (Task 9's own brief): the same
  # untranslated-field rule as the block-level test just above, but for a
  # post's own typed `fields` -- `test/event#venue` (`t.field :venue,
  # :string`, no `translated: true`) is `Post#fields_are_valid`'s
  # equivalent of a block's untranslated settings field, so it has to show
  # the same Shared-fields listing, with no input and no read-only original in
  # a non-default locale. `test/event#title` (a plain Mobility column, always
  # translated) is the control: it must still show its original the way
  # every other translated field already does, proving this isn't just
  # "post-level fields never show an original."
  test "a post's untranslated field is listed under Shared fields, while its translated title still shows the original" do
    with_test_types do
      post = Posts::Save.call(Post.new, attributes: { content_type: "test/event", fields: { venue: "Main Hall" } },
        translations: { Locales.default => { title: "Launch day" } }).record
      assert post.persisted?, post.errors.full_messages.to_sentence

      get "/cs-studio/posts/#{post.id}", params: { locale: "de" }

      assert_select "[data-field-name='venue']", count: 0
      assert_select "input[name='post[fields][venue]']", count: 0
      assert_select "details.admin-shared-fields", text: /Venue/
      assert_select "details.admin-shared-fields", text: /Main Hall/

      assert_select "[data-original-for='title'] p", text: "Launch day"
    end
  end
end
