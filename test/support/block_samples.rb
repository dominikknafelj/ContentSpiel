# One block of a type, filled from its definition's sample (block types spec,
# decision 14), so every shared test builds it the same way and a type nobody
# wrote a row for is in every shared test from the day it is registered.
#
# Written through `ContentBlocks::Save`, as an editor's save is: a translated
# schema field goes in its language's `settings`, `caption` and `alt` are the
# columns, `body` is Markdown written in the default language, `image: true`
# attaches a new library image.
#
# `assert_every_type_built` ends each shared test: it compares the types this
# test built with the registry, in the test and not after the run, because
# the suite runs in parallel workers. It records names, not places: it says
# a test built a block of each type somewhere, which catches a shared test
# that forgot the helper, and not whether the block sat at the top level or
# in a column (the smoke test checks that by what the page draws).
module BlockSamples
  # THE TRANSITION (block types plan, Task 10 makes this BlockTypes.all): the
  # types that declare a sample yet.
  def sampled_types = BlockTypes.all.select(&:sample)

  def sample_block(page, type, section: nil)
    definition = BlockTypes.fetch(type)
    sample = definition.sample or flunk("#{definition.name} declares no sample")
    fields = definition.fields.map(&:name)

    default = Locales.default
    # A translated schema field of the default language is saved with the
    # untranslated ones, as the editor's default-language card sends it; in
    # another language it goes in that language's `settings`.
    own_default = sample.translations.fetch(default, {}).transform_keys(&:to_s).slice(*fields)
    attributes = { block_type: definition.name, settings: sample.settings.merge(own_default) }
    attributes.merge!(section_id: section.id, section_column: 1) if section
    attributes[:media_asset_id] = create_media_asset.id if sample.image

    translations = sample.translations.to_h do |locale, values|
      values = values.transform_keys(&:to_s)
      own = locale == default ? {} : values.slice(*fields)
      [ locale, values.except(*fields).transform_keys(&:to_sym).merge(own.any? ? { settings: own } : {}) ]
    end
    translations[default] = (translations[default] || {}).merge(body: rich_doc(sample.body)) if sample.body

    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: attributes, translations: translations)
    assert result.ok?, "the sample of #{definition.name} does not save: #{result.errors.to_sentence}"
    (@built_block_types ||= []) << definition.name
    result.record
  end

  def sample_every_type(page)
    containers, others = sampled_types.partition { |definition| definition.capability?(:container) }
    others.each { |definition| sample_block(page, definition.name) }
    containers.each do |container|
      section = sample_block(page, container.name)
      others.each { |definition| sample_block(page, definition.name, section: section) }
    end
  end

  def assert_every_type_built(names = sampled_types.map(&:name))
    missing = names - Array(@built_block_types).uniq
    assert_empty missing, "this shared test built no block of #{missing.join(", ")}: build every type with sample_block or sample_every_type"
  end
end

# `with_every_type { … }`: every registered type for a block: the built-ins,
# `test/quote` (a type with an owner's name, test/support/test_types.rb) and
# `gallery/album` (an outside type through the plugin hook,
# test/support/gallery_album.rb). `with_gallery_album` goes outside: it
# prepares the registries again, which would drop a type `with_test_types`
# had registered before it. Included by the shared tests that can run the
# test types; the canary and the scaffold build the built-ins alone.
module EveryBlockType
  include TestTypes
  include GalleryAlbum

  def with_every_type(&block) = with_gallery_album { with_test_types(&block) }
end
