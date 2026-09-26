class Avo::Resources::SiteSetting < Avo::BaseResource
  # self.icon = "tabler/outline/users"
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
    field :title, as: :text
    field :tagline, as: :text
    field :social_links, as: :key_value, key_label: "Network", value_label: "URL"
    # The locale served with no prefix at all (e.g. plain "/about") --
    # PagesController#redirect_default_locale_prefix reads this per request,
    # so changing it here takes effect immediately, no deploy required.
    #
    # Avo's :select field wants { "Label" => stored_value }, not the other
    # way around -- confirmed against avo/fields/select_field.rb, which
    # inverts the hash to look a stored value's label back up.
    field :default_locale, as: :select,
      options: ::I18n.available_locales.to_h { |locale| [ locale.to_s.upcase, locale.to_s ] }
    field :logo, as: :file
  end
end
