require "test_helper"

# Public rendering of the JSON rich-text bodies (design spec §3.1/§4.3):
# every body renderer reads `Locales.read(record, :body)` -- a
# `RichText::Document`, falling back per language when a locale's document
# is blank -- and renders it with `to_html(locale:, urls: public_urls)`, so
# internal links follow the request's own `PublicSite::Urls` (`/preview`
# keeps its links under `/preview`).
class RichTextBodyTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
  end

  test "a rich_text block renders its JSON document as HTML" do
    @root.content_blocks.create!(block_type: :rich_text, position: 0, body_doc: rich_doc("Hello **there**"))

    get "/"

    assert_response :success
    assert_select ".content-block--rich-text strong", text: "there"
  end

  test "a post detail renders its JSON body" do
    blog = Page.create!(parent: @root, page_type: :standard, title: "Blog", published_at: Time.current)
    blog.content_blocks.create!(block_type: :post_list, position: 0)
    Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago, body_doc: rich_doc("## Section\n\nBody *text*"))

    get "/blog/hello"

    assert_select "article .cs-prose h2", text: "Section"
    assert_select "article .cs-prose em", text: "text"
  end

  test "a now list renders the latest update's JSON body" do
    Post.create!(content_type: :now_update, title: "Now", published_at: 1.day.ago, body_doc: rich_doc("Training for a half marathon"))
    @root.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "now_update" })

    get "/"

    assert_includes response.body, "Training for a half marathon"
  end

  test "a locale without a body falls back to the primary language's document" do
    @root.content_blocks.create!(block_type: :rich_text, position: 0, body_doc: rich_doc("English body"))

    get "/de"

    assert_response :success
    assert_select ".content-block--rich-text", text: /English body/
  end

  test "a locale whose document is blank falls back to the primary language" do
    block = @root.content_blocks.create!(block_type: :rich_text, position: 0, body_doc: rich_doc("English body"))
    block.assign_body({ "type" => "doc", "content" => [ { "type" => "paragraph" } ] }, locale: "de")
    block.save!

    get "/de"

    assert_select ".content-block--rich-text", text: /English body/
  end

  test "a locale with its own body renders that one, not the fallback" do
    block = @root.content_blocks.create!(block_type: :rich_text, position: 0, body_doc: rich_doc("English body"))
    block.assign_body(rich_doc("Deutscher Text"), locale: "de")
    block.save!

    get "/de"

    assert_select ".content-block--rich-text", text: /Deutscher Text/
    assert_not_includes response.body, "English body"
  end

  test "internal links resolve in the request's locale" do
    about = Page.create!(parent: @root, page_type: :standard, title: "About", published_at: Time.current)
    Mobility.with_locale(:de) { about.update!(slug: "ueber-uns") }
    @root.content_blocks.create!(block_type: :rich_text, position: 0, body_doc: rich_doc("See [about](cs:page/#{about.id})"))

    get "/de"

    assert_select ".content-block--rich-text a[href='/de/ueber-uns']", text: "about"
  end

  test "internal links in a preview stay under /preview" do
    sign_in_as(users(:one))
    draft = Page.create!(parent: @root, page_type: :standard, title: "Draft", published_at: nil)
    @root.content_blocks.create!(block_type: :rich_text, position: 0, body_doc: rich_doc("See [the draft](cs:page/#{draft.id})"))

    get "/preview"

    assert_response :success
    assert_select ".content-block--rich-text a[href='/preview/draft']", text: "the draft"
  end
end
