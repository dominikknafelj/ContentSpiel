module Blocks
  # The Form block on the public site (`BlockTypes::Form`, forms plan Task 7;
  # design.md 4): the form the block names, drawn by the theme, posting to
  # its own endpoint (`FormSendsController`, `POST /forms/:id`) and sent in
  # place by `form-send` where the script runs.
  #
  # THE FORM IS READ FROM ITS ROWS: a form has no published copy and is live
  # at its Save (spec decision 3; forms plan decision 9), which moves the
  # public content version, so the page's ETag moves with it. The BLOCK is
  # the page's, read as every block is (a published view on the site, the
  # rows in a preview). A missing form, one in the trash, and one with no
  # field draw nothing (`render?`).
  #
  # THE PAGE STAYS ONE ANSWER FOR EVERY VISITOR (spec, anti-goals): nothing
  # here reads the request, a session or a cookie, and the form carries no
  # token of this application (the endpoint takes none: its head comment
  # says why that is safe). What it does carry beside the answers is the
  # visitor's language, the page's id and the signed draw time
  # (`Forms::Drawn`). THE DRAW TIME IS THE DRAW'S: a page answered 304, or
  # served by a CDN from its cache, hands the visitor the token of the draw
  # that was cached, which is older than the visit, so the minimum time
  # (`Forms::Drawn::MIN_SECONDS`) is passed sooner and never later: a cached
  # page can make a send look slower than it was, never faster, and the
  # token has no expiry, so an old one is still taken. The ETag does not
  # name the token for that reason, and is right without it.
  #
  # WITHOUT ENCRYPTION KEYS the site takes no answers (owner's ruling 2):
  # the form is drawn with its fields disabled under the line `unavailable`
  # (pre-flight R3), and `Forms::Encryption.available?` is a key of the
  # public ETag (`PagesController#show`).
  #
  # Its template is promised the names of `theme_methods` and no other; the
  # private readers below the line are help for those and no promise.
  class FormComponent < ApplicationComponent
    # The CMS's words a template may ask for (`string`), all of
    # `public.forms` (config/locales/public.en.yml): the required word, a
    # select's empty choice, the button's word while sending, the thank-you
    # a form without one says, the summary's line (`count:`), and what the
    # script says when a send had no answer.
    STRINGS = %i[required choose sending sent error_summary network].freeze

    UNKNOWN_STRINGS_LOCK = Mutex.new

    def self.first_unknown_string?(key)
      UNKNOWN_STRINGS_LOCK.synchronize { (@unknown_strings ||= Set.new).add?(key).present? }
    end

    def initialize(block:, page:)
      @block = block
      @page = page
    end

    def render? = form.present? && fields.any?

    private

    attr_reader :block, :page

    # The form the block names, kept, or nil. One statement, remembered.
    def form
      return @form if defined?(@form)

      id = block.settings.to_h["form_id"].presence
      @form = id && ::Forms::Form.kept.find_by(id: id) # public: rows (a form has no published copy: it is live at its Save, spec decision 3)
    end

    # The editor's name for the form. The default template draws it
    # nowhere: it is for editors (spec, "The form"), and a theme that shows
    # it does so knowingly.
    def form_name = form&.name

    # The visitor's language: the page's, as the request was routed.
    def locale = I18n.locale.to_s

    # The form's fields as a visitor's form draws them, their ids this
    # block's own (`place`: two placements of one form never share an id),
    # each drawn by the theme's input where the theme replaces it. A field
    # of a type no longer registered (a gem taken out) is left out rather
    # than raise on a public page.
    def fields
      @fields ||= Array(form&.fields).select { |field| ::Forms::FieldTypes.find(field.type) }.map do |field|
        ::Forms::PublicField.new(field: field, locale: locale, form_id: form.id, place: block.id,
          input: Theme.current.component_for(field.field_type, :input))
      end
    end

    # The endpoint's path: a plain `<form method="post">` lands there.
    def action = form && helpers.form_send_path(form)

    def page_id = page&.id

    # The signed draw time (see the head): read once per draw.
    def drawn = (@drawn ||= form && ::Forms::Drawn.token(form))

    # The hidden field only a script that fills every field fills.
    def honeypot = ::Forms::SpamCheck::HONEYPOT

    def submit_label = form&.submit_label_in(locale).presence || PublicStrings.read("public.forms.submit")

    def thank_you = form&.thank_you_in(locale).presence || string(:sent)

    # The line a form says above its disabled fields when the site has no
    # encryption keys and so takes no answers; nil when it takes them.
    def unavailable = (PublicStrings.read("public.forms.unavailable") unless ::Forms::Encryption.available?)

    # One of the six words of `STRINGS` in the visitor's language, English
    # where that language has none; `options` are I18n's (`count:`).
    #
    # ONLY THOSE SIX, as the Code block's `string`: a theme's template calls
    # this with a key its author typed, and I18n's answer for a missing key
    # is a sentence. Where a theme is written (development, test) another
    # key raises and names the six; in production it is no word, and one
    # line in the log per key for the life of the process.
    def string(key, **options)
      return unknown_string(key) unless STRINGS.include?(key.to_s.to_sym)

      PublicStrings.read("public.forms.#{key}", **options)
    end

    def unknown_string(key)
      message = "Blocks::FormComponent#string has no #{key.to_s.to_sym.inspect}: the Form block's words are #{STRINGS.map(&:inspect).join(", ")}"
      raise ArgumentError, message if Rails.env.local?

      Rails.logger.warn(message) if self.class.first_unknown_string?(key.to_s)
      ""
    end
  end
end
