# AI translation (translation helpers spec §6): a provider registry
# (`AI::Providers`), the built-in Anthropic provider (`AI::Providers::
# Anthropic`) and, here, the two questions the rest of the app asks --
# "is AI set up?" and "give me the configured provider".
#
# Everything is configured on the one `SiteSetting` row (`ai_provider`,
# `ai_model`, `ai_api_key`, CS Studio's Settings → "AI translation"); the
# key is stored with `encrypts` and never rendered, logged or audited
# (global constraints). Nothing in this module saves anything: a provider
# only ever *suggests* text, and the editor's own autosave is the only
# write (spec §6.4).
module AI
  # A user-facing failure: its message is shown as-is under the button
  # that asked (Test connection, Translate), so it must say what went wrong
  # in plain words and never carry a key, a request body or a stack trace.
  class Error < StandardError; end

  # `AI::Providers.register` for a name that's already taken -- a developer
  # error caught at boot, like `ContentModel::DuplicateType`. The one
  # legitimate re-registration, a `to_prepare` reload, calls `reset!` first
  # (config/initializers/types.rb).
  class DuplicateProvider < StandardError; end

  # Used when the Settings model field is left blank (spec §6.1, global
  # constraints), and shown as that field's placeholder.
  DEFAULT_MODEL = "claude-sonnet-5".freeze

  NOT_CONFIGURED = "AI translation isn't set up — choose a provider and add an API key in Settings.".freeze

  # True when there's a provider, a class registered under its name (a
  # plugin provider whose plugin is gone isn't usable) and a key (spec
  # §6.2). Callers that offer AI (the Translate buttons) check this; it
  # never builds a client or touches the network.
  def self.configured?(site = Current.site)
    site.ai_provider.present? && Providers.find(site.ai_provider).present? && site.ai_api_key_set?
  end

  # A provider instance built from the settings, the model defaulting to
  # `DEFAULT_MODEL`. Raises `AI::Error` when AI isn't configured, so a
  # caller that skipped `configured?` still gets a message it can show.
  def self.provider(site = Current.site)
    raise Error, NOT_CONFIGURED unless configured?(site)

    Providers.find(site.ai_provider).new(api_key: readable_api_key(site), model: model(site))
  end

  # The model a provider is built with -- what `AI::Translate` records in
  # its `ai.translated` event, read from the same place so the log names
  # the model actually asked.
  def self.model(site = Current.site) = site.ai_model.presence || DEFAULT_MODEL

  # The one place the key is decrypted. A key stored under encryption keys
  # this server no longer has (or never had) can't be read; the fix is
  # entering it again, which the Settings screen still allows
  # (`SiteSetting#ai_api_key_set?`).
  def self.readable_api_key(site)
    site.ai_api_key
  rescue ActiveRecord::Encryption::Errors::Base
    raise Error, "The stored API key can't be read — enter it again in Settings."
  end
  private_class_method :readable_api_key
end
