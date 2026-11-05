module Blocks
  # The guard of a block component's `string(key)` (the Code block's four
  # words, the Form block's six): a theme's template calls `string` with a
  # key its author typed, and I18n's answer for a key that does not exist is
  # a sentence ("Translation missing: …") that would be a word on a public
  # page. So a component answers its own list and no other key:
  #
  #   class CodeComponent < ApplicationComponent
  #     include Blocks::FixedWords
  #     STRINGS = %i[copy copy_code copied failed].freeze
  #     def string(key) = fixed_word(key, scope: "public.blocks.code", owner: "the Code block's")
  #
  # Where a theme is written (development, test) another key raises, naming
  # the list; in production it is no word, and one log line per key for the
  # life of the process (`first_unknown_string?`, kept per component class).
  # `string` stays the component's own method, since it is a name of its
  # line in the theme contract.
  module FixedWords
    extend ActiveSupport::Concern

    LOCK = Mutex.new

    class_methods do
      # Whether this is the first time the process meets `key` for this
      # component, which keeps a mistake to one log line, not one per visitor.
      def first_unknown_string?(key)
        LOCK.synchronize { (@unknown_strings ||= Set.new).add?(key).present? }
      end
    end

    private

    # One of `self.class::STRINGS` under `scope`, in the visitor's language,
    # English where that language has none; `options` are I18n's.
    def fixed_word(key, scope:, owner:, **options)
      return refused_word(key, "#{self.class.name}#string has no #{key.to_s.to_sym.inspect}: #{owner} words are #{self.class::STRINGS.map(&:inspect).join(", ")}") unless self.class::STRINGS.include?(key.to_s.to_sym)

      PublicStrings.read("#{scope}.#{key}", **options)
    end

    # A call of `string` that is a template's mistake: raised where a theme
    # is written, otherwise no word and the message logged once per key.
    def refused_word(key, message)
      raise ArgumentError, message if Rails.env.local?

      Rails.logger.warn(message) if self.class.first_unknown_string?(key.to_s)
      ""
    end
  end
end
