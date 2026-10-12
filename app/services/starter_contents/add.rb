module StarterContents
  # Adds the starter pages and sample posts in the site's default language
  # (`locale:` says another, for a test or a console): the setup wizard's
  # starter-content step and CS Studio's "Create starter pages" both.
  # `record` is true when it created the sections, false when they were
  # already there.
  #
  # Every step is idempotent: records are looked up first, through
  # `StarterContent`'s finders, which span every enabled locale (see its
  # comment), and only what is missing is created, in `locale` only.
  #
  # Two requests at once (two tabs, a double submit) would both pass
  # `StarterContent.added?` and race each other into the same section slugs,
  # the loser raising on slug uniqueness after possibly half-building a
  # section. So the check and the creation run in one transaction holding the
  # `SiteSetting` singleton's row lock: the second request waits for the
  # first to commit, then re-checks inside the lock and finds the sections
  # there. A failure that still gets through (a hand-made page already owning
  # a starter slug) rolls the whole attempt back and answers the one failure
  # message below.
  #
  # Permissions (access-control design spec §3.3): starter content is
  # pages, blocks and posts, each written through its own service
  # (`Pages::Save`, `ContentBlocks::Save`, `Posts::Save`), which authorize
  # and audit themselves. Those checks run *inside* this
  # service's transaction, though, and a refusal there becomes a `StarterContent::
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

    def initialize(actor: Current.actor, locale: Locales.default)
      @actor = actor
      @locale = locale
    end

    def call
      refused = refusal
      return denied(*refused) if refused

      created = SiteSetting.transaction do
        SiteSetting.instance.lock!
        next false if StarterContent.added?(locale: @locale)

        create_pages_and_posts!
        record_event("starter_content.added", metadata: { "locale" => @locale })
        true
      end

      success(created)
    rescue StarterContent::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      Rails.logger.warn("[starter content] #{error.class}: #{error.message}")
      failure(nil, [ FAILURE_MESSAGE ])
    end

    # Would `call` get past its permission checks? For the Pages home,
    # which offers "Create starter pages" only when it would (access-control
    # design spec §5 "Everywhere") -- the same checks, so the button and
    # the refusal can't disagree. Asks only; records nothing.
    def permitted? = refusal.nil?

    private

    def create_pages_and_posts!
      home = StarterContent.raise!(EnsureHome.call(locale: @locale, actor: actor))

      StarterContent.sections.each do |section|
        find_or_create_section_page!(home, section)
        find_or_create_sample_post!(section)
      end
    end

    def find_or_create_section_page!(home, section)
      StarterContent.find_section_page(home, section) || begin
        page = StarterContent.raise!(Pages::Save.call(attributes: { parent: home, published: true },
          translations: { @locale => section[:section].slice(:title, :slug) }))

        StarterContent.raise!(ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list",
          settings: { "content_type" => section[:content_type] } }))
        # The copy taken at publication has no list block yet (see `EnsureHome`).
        StarterContent.raise!(Publishing::PublishChanges.call(page, actor: actor))

        page
      end
    end

    def find_or_create_sample_post!(section)
      StarterContent.find_sample_post(section) || begin
        sample = section[:sample]
        translated = sample.slice(:title, :excerpt)
        translated[:body] = StarterContent.document(sample[:body]) if sample.key?(:body)
        attributes = sample.except(:title, :excerpt, :body).merge(content_type: section[:content_type], published: true)

        StarterContent.raise!(Posts::Save.call(attributes: attributes, translations: { @locale => translated }))
      end
    end

    # The first `[key, record]` the actor lacks, or nil.
    def refusal
      home = Page.find_by(parent_id: nil)
      section_page = Page.new(parent: home, published_at: Time.current)
      checks = EnsureHome.new(locale: @locale, actor: actor).checks # the homepage and its welcome block
      checks += %w[pages.create pages.edit pages.publish].map { |key| [ key, section_page ] }
      StarterContent.sections.each do |section|
        post = Post.new(content_type: section[:content_type], author_id: actor_user&.id, published_at: Time.current)
        checks += %w[posts.create posts.publish].map { |key| [ key, post ] }
      end

      checks.find { |key, record| !authorize!(key, record) }
    end
  end
end
