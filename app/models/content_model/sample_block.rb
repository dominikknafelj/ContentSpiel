module ContentModel
  # What `ContentBlocks::Save` is handed for one block of a type, filled from
  # the type's declared sample (`BlockTypeDefinition#sample`, block types
  # spec, decision 14). The shared tests' `sample_block`
  # (test/support/block_samples.rb) and the development seed's showcase
  # (db/seeds/showcase.rb) both build through it, so a sample is the same
  # block in both places.
  #
  # Where each value goes, as an editor's save sends it: a translated schema
  # field of the default language is saved with the untranslated ones in
  # `settings` (the default-language card sends them together), and in
  # another language in that language's `settings`; `caption` and `alt` are
  # the columns; `body` is the sample's Markdown, written in the default
  # language. What the sample asks for that is a record of its own the caller
  # makes and hands in: `media_asset_id:` for `image: true`, `form_id:` for
  # `form: true` (named in the type's `:form` field), `media_asset_ids:` for
  # `images: n` (exactly n ids, written in order into the type's `:media_list`
  # field; the sample writes its `:media_texts` by position, "1" for the first
  # image, and they are re-keyed to the ids here, since a text follows its
  # image by id). `settings:` is merged
  # over the sample's (the showcase draws a Note of every kind from the one
  # sample). `locales:`, when given, keeps the translations of those
  # languages only, as a save under a language that is off would not be
  # asked for.
  #
  # The sample is fixed data, so anything it cannot be built from raises
  # `ArgumentError`, and Markdown that converts with a warning is refused
  # rather than saved half-converted.
  module SampleBlock
    module_function

    # => [attributes, translations]
    def arguments(definition, default:, locales: nil, settings: {}, media_asset_id: nil, media_asset_ids: [], form_id: nil, section: nil, column: 1)
      sample = definition.sample or raise ArgumentError, "#{definition.name} declares no sample"
      fields = definition.fields.map(&:name)

      if media_asset_ids.size != sample.images
        raise ArgumentError, "#{definition.name}'s sample shows #{sample.images} images: hand in their ids as media_asset_ids (got #{media_asset_ids.size})"
      end
      list_field = definition.fields.find { |field| field.type == :media_list }
      raise ArgumentError, "#{definition.name}'s sample shows images, and it has no :media_list field to name them in" if sample.images.positive? && list_field.nil?

      own_default = by_ids(definition, sample.translations.fetch(default, {}).transform_keys(&:to_s).slice(*fields), media_asset_ids)
      attributes = { block_type: definition.name,
                     settings: by_ids(definition, sample.settings, media_asset_ids).merge(own_default).merge(settings.transform_keys(&:to_s)) }
      attributes[:settings] = attributes[:settings].merge(list_field.name => media_asset_ids) if sample.images.positive?
      attributes.merge!(section_id: section.id, section_column: column) if section
      if sample.image
        raise ArgumentError, "#{definition.name}'s sample shows an image: hand in its media_asset_id" if media_asset_id.nil?

        attributes[:media_asset_id] = media_asset_id
      end
      if sample.form
        form_field = definition.fields.find { |field| field.type == :form } or raise ArgumentError, "#{definition.name}'s sample makes a form, and it has no :form field to name it in"
        raise ArgumentError, "#{definition.name}'s sample makes a form: hand in its form_id" if form_id.nil?

        attributes[:settings] = attributes[:settings].merge(form_field.name => form_id.to_s)
      end

      chosen = locales ? sample.translations.slice(*locales.map(&:to_s)) : sample.translations
      translations = chosen.to_h do |locale, values|
        values = values.transform_keys(&:to_s)
        own = locale == default ? {} : by_ids(definition, values.slice(*fields), media_asset_ids)
        [ locale, values.except(*fields).transform_keys(&:to_sym).merge(own.any? ? { settings: own } : {}) ]
      end
      translations[default] = (translations[default] || {}).merge(body: body_of(definition, sample)) if sample.body

      [ attributes, translations ]
    end

    # `values` with each `:media_texts` field's keys, the positions "1".."n"
    # of the sample's images, replaced by those images' ids.
    def by_ids(definition, values, media_asset_ids)
      definition.fields.select { |field| field.type == :media_texts }.each_with_object(values.dup) do |field, rekeyed|
        texts = values[field.name] or next
        rekeyed[field.name] = texts.to_h do |position, pair|
          id = media_asset_ids[position.to_s.to_i - 1] if position.to_s.match?(/\A[1-9]\d*\z/)
          raise ArgumentError, "#{definition.name}'s sample writes #{field.name} for position #{position}, past its #{media_asset_ids.size} images" if id.nil?

          [ id.to_s, pair ]
        end
      end
    end

    def body_of(definition, sample)
      document, warnings = RichText::Document.from_markdown(sample.body, tables: definition.body_content == :table)
      raise ArgumentError, "#{definition.name}'s sample body converts with warnings: #{warnings.to_sentence}" if warnings.any?

      document.to_h
    end
  end
end
