class Avo::Resources::Post < Avo::BaseResource
  self.icon = "tabler/outline/ballpen"
  # self.avatar = {
  #   source: :avatar
  # }
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  # `fields` no longer has a field of its own (the typed-fields tool below
  # writes it instead), so nothing else would tell Avo to let this key
  # through `permitted_params` -- same reason `Avo::Resources::Page` permits
  # `content_blocks_attributes` for its own resource tool. Lands on
  # `Post#fields=`, which routes it through `assign_fields` rather than a
  # raw column writer -- there is no raw `fields` column to fall back to the
  # way `ContentBlock#normalize_settings` does for `settings`.
  self.extra_params = [ { fields: {} } ]

  def fields
    field :id, as: :id
    # field :avatar, as: :avatar
    # {label => value}: Avo's `:select` field takes its `options:` Hash this
    # way round (no invert step, unlike the content-type filter's own
    # `options` -- see the comment there for why the two are opposite).
    field :content_type, as: :select, options: ::ContentTypes.all.to_h { |definition| [ definition.label, definition.name ] }

    # The index is a list, not an editor, so it shows one column of titles --
    # in whichever locale the admin is currently browsing. Editing happens in
    # the per-locale tabs below, which the index does not render.
    field :title, as: :text, only_on: :index

    # Avo 4.2.3 ships no Mobility integration of its own (there is no mention
    # of Mobility anywhere in the gem), so the locale switcher is built out of
    # Avo's own tabs plus Mobility's locale accessors: `title_de` and friends,
    # defined by the `locale_accessors` plugin. Those accessors read and write
    # one specific locale and deliberately skip fallbacks, so an untranslated
    # tab shows up empty instead of echoing the English text back at the editor
    # and tricking them into saving a copy of it.
    tabs do
      ::Locales.enabled.each do |locale|
        tab title: locale.to_s.upcase do
          # `normalize_locale_accessor` is what Mobility itself uses to name
          # these methods, so it stays correct for a region-qualified locale
          # like :"pt-BR" (whose accessor is `title_pt_br`, not `title_pt-BR`).
          field ::Mobility.normalize_locale_accessor(:title, locale).to_sym, as: :text, name: "Title"
          field ::Mobility.normalize_locale_accessor(:slug, locale).to_sym, as: :text, name: "Slug"
          field ::Mobility.normalize_locale_accessor(:excerpt, locale).to_sym, as: :textarea, name: "Excerpt"
          field ::Mobility.normalize_locale_accessor(:body, locale).to_sym, as: :trix, name: "Body"
        end
      end
    end

    field :published_at, as: :date_time
    field :tags, as: :has_many, through: :post_tags
    field :related_posts, as: :has_many, through: :post_relations

    # One typed input per field the record's own `content_type` actually
    # declares (open-types spec §6), replacing the raw `metadata` code
    # editor this used to be. A plain Avo `:text`/`:select` field per field
    # name isn't workable here: Avo only calls a field's `update_using` (and
    # so only ever attempts a write at all) when the record already responds
    # to a real `<name>=` method (`Avo::Fields::BaseField#fill_field` ->
    # `#has_attribute?`, checked via `record.methods.include?`, which
    # `respond_to_missing?` does not satisfy) -- Post has no such method per
    # field name, and manufacturing one per registered field would put
    # type-specific knowledge back onto Post, which the open-types refactor
    # deliberately moved off of it. This resource tool instead submits the
    # whole hash at once into `Post#fields=`, which already exists and
    # already routes through `assign_fields`.
    tool Avo::ResourceTools::TypedFields, show_on: :forms
  end

  def filters
    filter Avo::Filters::ContentType
  end
end
