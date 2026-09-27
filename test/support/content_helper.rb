# Builds content through the services (spec §11), so tests exercise the same
# write path as admin, MCP and setup. No Page/Post fixtures: closure_tree
# rows and public_paths would be missing.
module ContentHelper
  def root_page
    Page.find_by(parent_id: nil) ||
      Pages::Save.call(attributes: { published: true }, translations: { Locales.default => { title: "Home", slug: "" } }).record
  end

  def create_page(title:, parent: root_page, published: true, translations: {})
    result = Pages::Save.call(attributes: { parent: parent, published: published },
      translations: { Locales.default => { title: title } }.merge(translations))
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def create_post(title:, content_type: "blog", published: true, tags: [])
    result = Posts::Save.call(attributes: { content_type: content_type, published: published, tag_names: tags },
      translations: { Locales.default => { title: title } })
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def with_locales(codes, default:)
    site_settings(:default).update!(locales: codes.map { |code| { "code" => code } }, default_locale: default)
    PublicSite::Paths.rebuild!
    yield if block_given?
  end
end
