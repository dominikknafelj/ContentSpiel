require "test_helper"

class LocalesTest < ActiveSupport::TestCase
  setup do
    Current.reset
    site_settings(:default).update!(default_locale: "de",
      locales: [ { "code" => "de" }, { "code" => "en", "fallbacks" => [ "de" ] }, { "code" => "es" } ])
  end

  test "enabled lists the configured codes in order" do
    assert_equal %w[de en es], Locales.enabled
    assert_equal "de", Locales.default
    assert Locales.enabled?(:en)
    assert_not Locales.enabled?("fr")
  end

  test "fallback chain is own code, configured fallbacks, default, then the rest" do
    assert_equal %w[en de es], Locales.fallback_chain("en")
    assert_equal %w[es de en], Locales.fallback_chain("es")
    assert_equal %w[de en es], Locales.fallback_chain("de")
  end

  test "names come from the supported list" do
    assert_equal "German", Locales.name("de")
    assert_equal "Deutsch", Locales.name("de", native: true)
    assert_equal "XX", Locales.name("xx")
  end

  test "Current.site is reloaded after the site setting changes" do
    assert_equal "de", Current.site.default_locale
    site_settings(:default).update!(default_locale: "en")
    assert_equal "en", Current.site.default_locale
  end

  test "read walks the fallback chain and plain readers no longer fall back" do
    site_settings(:default).update!(default_locale: "de")
    post = Mobility.with_locale(:de) { Post.create!(content_type: :blog, title: "Hallo") }

    assert_nil Mobility.with_locale(:en) { post.title }
    assert_equal "Hallo", Locales.read(post, :title, locale: "en")
    assert_nil Locales.read(nil, :title)
  end

  test "read returns the body as a RichText::Document, falling back when blank" do
    site_settings(:default).update!(default_locale: "de")
    post = Mobility.with_locale(:de) { Post.create!(content_type: :blog, title: "Hallo", body: rich_doc("Text")) }

    document = Locales.read(post, :body, locale: "es")
    assert_kind_of RichText::Document, document
    assert_equal rich_doc("Text"), document.to_h
  end

  # "Blank" is `RichText::Document#blank?` -- an empty paragraph left behind
  # by an editor counts as no translation, not as content to render.
  test "read treats a blank body document as missing" do
    post = Post.create!(content_type: :blog, title: "Hello", body: rich_doc("English"))
    post.assign_body({ "type" => "doc", "content" => [ { "type" => "paragraph" } ] }, locale: "de")
    post.save!

    assert_equal rich_doc("English"), Locales.read(post, :body, locale: "de").to_h
  end

  test "read returns an empty document when no locale has a body" do
    post = Post.create!(content_type: :blog, title: "Hello")

    assert Locales.read(post, :body).blank?
  end
end
