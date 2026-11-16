# One post of a declared content type, filled from its definition's sample
# (post types spec, §10), so every shared test builds it the same way and a
# type nobody wrote a row for is in them from the day it is declared.
#
# Written and published through `Posts::Save`, as an editor's save is: the
# sample's Markdown body becomes the document a post stores. A post of a type
# the site has not switched on is dormant and refused every write, so a type
# is switched on for the test first (the other types' switches are kept).
module PostSamples
  # Every declared type: the contract is the code's, whatever a site switches on.
  def sample_post_types = ContentTypes.all

  def sample_post(type, published: true)
    definition = ContentTypes.fetch(type)
    sample = definition.sample or flunk("#{definition.name} declares no sample")
    switch_on_content_types(*(SiteSetting.instance.content_types | [ definition.name.to_s ]))

    translated = { title: sample.title, excerpt: sample.excerpt, body: (rich_doc(sample.body) if sample.body) }.compact
    result = Posts::Save.call(attributes: { content_type: definition.name, published: published, fields: sample.fields },
      translations: { Locales.default => translated })
    assert result.ok?, "the sample of #{definition.name} does not save: #{result.errors.to_sentence}"
    result.record
  end

  # A published post of every declared type, each switched on.
  def sample_every_post_type
    switch_on_content_types(*sample_post_types.map { |definition| definition.name.to_s })
    sample_post_types.map { |definition| sample_post(definition.name) }
  end
end
