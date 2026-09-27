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

  test "an invalid typed field value comes back as a form error" do
    post = Post.create!(content_type: :resume_entry, title: "Staff Engineer")

    put "/avo/resources/posts/#{post.id}", params: { post: {
      content_type: "resume_entry", fields: { role_type: "boss" }
    } }

    assert_response :unprocessable_entity
    assert_includes response.body, "is not included in the list"
  end
end
