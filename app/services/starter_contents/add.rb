module StarterContents
  # Adds the starter pages and sample posts (`StarterContent.add_once!`,
  # locked and idempotent -- see its own comment) in the site's default
  # language: the setup wizard's starter-content step and CS Studio's
  # "Create starter pages" both. `record` is true when it created the
  # sections, false when they were already there.
  #
  # Permissions (access-control design spec §3.3): starter content is
  # pages, blocks and posts, each written through its own service
  # (`Pages::Save`, `ContentBlocks::Save`, `Posts::Save`), which authorize
  # and audit themselves. Those checks run *inside* `add_once!`'s
  # transaction, though, and a refusal there becomes a `StarterContent::
  # Error` that rolls the whole attempt back -- the `access.denied` it
  # recorded included. So every right the inner writes will need is
  # checked here first, up front, against the records they'll create: a
  # published section page under the homepage (`pages.create`,
  # `pages.edit` for its listing block, `pages.publish`), and a published
  # sample post of each starter content type (`posts.create`,
  # `posts.publish`). The homepage itself, when it doesn't exist yet, is
  # the root: `pages.create` with no parent, which only an unscoped grant
  # matches; an existing homepage without blocks gets a welcome block,
  # which is editing it.
  #
  # Recorded as `starter_content.added` (no subject: it spans many
  # records, each with its own `*.created` event), only when it created
  # something.
  class Add < ApplicationService
    FAILURE_MESSAGE = "Starter content couldn't be added — a page may already use one of its addresses".freeze

    def initialize(actor: Current.actor)
      @actor = actor
    end

    def call
      refused = refusal
      return denied(*refused) if refused

      created = SiteSetting.transaction do
        added = StarterContent.add_once!(locale: Locales.default)
        record_event("starter_content.added", metadata: { "locale" => Locales.default }) if added
        added
      end

      success(created)
    rescue StarterContent::Error => error
      Rails.logger.warn("[starter content] #{error.class}: #{error.message}")
      failure(nil, [ FAILURE_MESSAGE ])
    end

    # Would `call` get past its permission checks? For the Pages home,
    # which offers "Create starter pages" only when it would (access-control
    # design spec §5 "Everywhere") -- the same checks, so the button and
    # the refusal can't disagree. Asks only; records nothing.
    def permitted? = refusal.nil?

    private

    # The first `[key, record]` the actor lacks, or nil.
    def refusal
      home = Page.find_by(parent_id: nil)
      section_page = Page.new(parent: home, published_at: Time.current)
      checks = []
      checks << [ "pages.create", Page.new ] if home.nil?
      if home && home.content_blocks.none? # `ensure_home!` adds its welcome block
        checks += [ [ "pages.edit", home ], ([ "pages.publish", home ] if home.published_at) ].compact
      end
      checks += %w[pages.create pages.edit pages.publish].map { |key| [ key, section_page ] }
      StarterContent.sections.each do |section|
        post = Post.new(content_type: section[:content_type], author_id: actor_user&.id, published_at: Time.current)
        checks += %w[posts.create posts.publish].map { |key| [ key, post ] }
      end

      checks.find { |key, record| !authorize!(key, record) }
    end
  end
end
