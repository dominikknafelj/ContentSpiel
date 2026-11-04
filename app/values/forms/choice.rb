module Forms
  # One choice of a choice field: a key that never changes and a label per
  # language (so rewording a choice or reordering the list changes no key an
  # old submission holds).
  Choice = Data.define(:key, :label)

  class Choice
    KEY_FORMAT = /\Ac_[a-z0-9]{8}\z/

    def self.new_key = "c_#{SecureRandom.alphanumeric(8).downcase}"

    # The language's label, else the default language's, else nil.
    def label_in(locale) = Field.text_in(label, locale)
  end
end
