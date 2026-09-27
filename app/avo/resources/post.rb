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

  def fields
    field :id, as: :id
    # field :avatar, as: :avatar
    field :content_type, as: :select, options: ::ContentTypes.names.index_by(&:humanize)

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
    field :metadata, as: :code
    field :tags, as: :has_many, through: :post_tags
    field :related_posts, as: :has_many, through: :post_relations
  end

  def filters
    filter Avo::Filters::ContentType
  end
end
