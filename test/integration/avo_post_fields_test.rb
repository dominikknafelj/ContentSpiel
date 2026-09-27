require "test_helper"

# Covers the Post form's typed content-type fields (open-types spec §6):
# `content_type` itself comes from the `ContentTypes` registry, and each
# content type's own fields (resume_entry's company/role_type/etc.) are
# edited through a small custom resource tool rather than a plain Avo field
# -- see the comment on Avo::Resources::Post#fields for why. Tested against
# the real rendered form and the real submit path, same rationale as
# AvoPageEditingTest and AvoPostTranslationsTest.
class AvoPostFieldsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "editor@example.com", password: "password123")
    sign_in_as(@user)
  end

  test "the content_type select offers every registered content type" do
    get "/avo/resources/posts/new"

    assert_response :success
    ContentTypes.all.each do |definition|
      assert_includes response.body, %(<option value="#{definition.name}">#{definition.label}</option>)
    end
  end

  test "the post form renders one input per field the record's own content type declares" do
    post = Post.create!(content_type: :resume_entry, title: "Staff Engineer",
      metadata: { "company" => "Acme", "role_type" => "lead" })

    get "/avo/resources/posts/#{post.id}/edit"

    assert_response :success
    assert_includes response.body, %(name="post[fields][company]")
    assert_includes response.body, %(name="post[fields][role_type]")
    assert_includes response.body, %(name="post[fields][start_date]")
    assert_match(/name="post\[fields\]\[company\]"[^>]*value="Acme"/, response.body)
  end

  # A content type with no fields (blog) offers none of these inputs -- there
  # is nothing for the typed-fields tool to render.
  test "a blog post's form renders no typed field inputs" do
    post = Post.create!(content_type: :blog, title: "Hello")

    get "/avo/resources/posts/#{post.id}/edit"

    assert_response :success
    assert_not_includes response.body, "post[fields]"
  end

  test "editing a resume_entry post saves company through the typed inputs" do
    post = Post.create!(content_type: :resume_entry, title: "Staff Engineer",
      metadata: { "company" => "Acme", "role_type" => "lead" })

    put "/avo/resources/posts/#{post.id}", params: { post: {
      content_type: "resume_entry",
      fields: { company: "Globex", role_type: "manager", start_date: "2023-01-01" }
    } }

    assert_response :redirect

    post.reload
    assert_equal "Globex", post.fields.company
    assert_equal "manager", post.fields.role_type
    assert_equal Date.new(2023, 1, 1), post.fields.start_date
  end

  # A Hash `options:` (the schema convention is `{value => label}`, e.g.
  # ResumeEntry::ROLE_TYPES) has to come out the other way round for
  # `options_for_select` ({label => value}, i.e. [text, value] pairs) -- get
  # the flip backwards and the select shows the raw stored value as text,
  # submits the label as the value, and never preselects the stored value
  # (its value attribute holds the label, which never matches). Checked
  # against the real rendered <option> markup, not just the round trip,
  # since a same-value submission (e.g. re-submitting "lead") could pass
  # even with the flip backwards if both sides happened to agree by luck.
  test "the resume_entry role_type select renders label/value pairs the right way round and preselects the stored value" do
    post = Post.create!(content_type: :resume_entry, title: "Staff Engineer",
      metadata: { "role_type" => "lead" })

    get "/avo/resources/posts/#{post.id}/edit"
    assert_response :success

    doc = Nokogiri::HTML::Document.parse(response.body)
    select = doc.at_css('select[name="post[fields][role_type]"]')
    assert select, "expected a role_type select"

    # An unselected option's markup is a literal, un-attribute-decorated
    # <option value="...">...</option> -- the exact "value=key, text=label"
    # shape the flip is about -- while the *selected* one also carries a
    # `selected` attribute Rails renders before `value`, so it's checked
    # separately below via the parsed tree rather than another literal
    # substring.
    assert_includes select.to_html, %(<option value="manager">Manager</option>)

    selected_option = select.at_css("option[selected]")
    assert selected_option, "expected the stored value to be preselected"
    assert_equal "lead", selected_option["value"]

    # Submit a value taken straight from the rendered select's own options,
    # not a hand-typed literal, so the assertion actually exercises what a
    # browser would submit.
    other_value = select.css("option").map { |option| option["value"] }.find { |value| value.present? && value != "lead" }
    assert other_value, "expected another role_type option to submit"

    put "/avo/resources/posts/#{post.id}", params: { post: {
      content_type: "resume_entry", fields: { role_type: other_value }
    } }

    assert_response :redirect
    assert_equal other_value, post.reload.fields.role_type
  end

  # `Avo::ResourceTools::TypedFields#current_values` used to read at the
  # ambient `I18n.locale` (Rails' own default, `:en`, since Avo's admin
  # locale doesn't follow the site's) while the write side
  # (`Post#fields=`/`assign_fields`) always writes a translated field at
  # `Locales.default` -- so on a site whose default locale *isn't* English,
  # a just-saved translated field would read back blank on redisplay: the
  # write landed under "de" but the read still checked "en". A test-only
  # type with a translated field is what exercises this, since none of the
  # built-ins have one.
  test "a translated field redisplays in the form when the site's default locale isn't English" do
    with_locales(%w[de en], default: "de") do
      saved = ContentTypes.all.dup
      begin
        ContentTypes.register(:test_note) do |t|
          t.label "Test note"
          t.field :headline, :string, translated: true
        end

        post = Post.create!(content_type: :test_note, title: "A note")
        post.assign_fields({ headline: "Wichtig" }, locale: "de")
        post.save!

        get "/avo/resources/posts/#{post.id}/edit"

        assert_response :success
        assert_match(/name="post\[fields\]\[headline\]"[^>]*value="Wichtig"/, response.body)
      ensure
        ContentTypes.reset!
        saved.each { |definition| ContentTypes.registry_put(definition) }
      end
    end
  end

  test "an invalid typed field value comes back as a form error" do
    post = Post.create!(content_type: :resume_entry, title: "Staff Engineer")

    put "/avo/resources/posts/#{post.id}", params: { post: {
      content_type: "resume_entry", fields: { role_type: "boss" }
    } }

    assert_response :unprocessable_entity
    assert_includes response.body, "is not included in the list"
  end
end
