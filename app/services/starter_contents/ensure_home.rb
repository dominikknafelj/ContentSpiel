module StarterContents
  # Makes sure the homepage exists and has something on it: a published root
  # page, and, while it has no block at all, a welcome block in `locale`. An
  # existing homepage and its blocks are kept as they are. Always run when
  # setup finishes (the review step), so "/" is never a 404 on a new site,
  # and first by `StarterContents::Add`. `record` is the homepage.
  #
  # Every write goes through `Pages::Save` and `ContentBlocks::Save`, which
  # authorize and audit it themselves (`page.created`, `block.created`); this
  # service records no event of its own, and checks up front the rights those
  # two will ask for (`#checks`), so a refusal is one `access.denied` here
  # rather than an exception out of the middle of a transaction. Setup runs it
  # as the signed-in owner (`SetupController#act_as_signed_in_user`).
  #
  # The input is fixed (see `StarterContent`), so a failed inner `Result`
  # means this code is broken, not that an editor typed something: it is
  # raised as `StarterContent::Error`, never answered as a failure.
  class EnsureHome < ApplicationService
    # audit: none (Pages::Save records page.created and ContentBlocks::Save block.created for what is written)

    def initialize(locale:, actor: Current.actor)
      @locale = locale
      @actor = actor
    end

    def call
      refused = checks.find { |key, record| !authorize!(key, record) }
      return denied(*refused) if refused

      success(ensure_home!)
    end

    # The `[permission key, record]` pairs the writes below will need, as
    # things stand now: creating the root when there is none (which only an
    # unscoped `pages.create` matches), else editing the existing homepage
    # for its welcome block -- and publishing it, when it is live, since
    # editing a live record needs `publish` too. `StarterContents::Add` asks
    # the same, ahead of its own writes.
    def checks
      home = Page.find_by(parent_id: nil)
      return [ [ "pages.create", Page.new ] ] if home.nil?
      return [] unless home.content_blocks.none?

      [ [ "pages.edit", home ], ([ "pages.publish", home ] if home.published_at) ].compact
    end

    private

    def publish_what_was_written(home)
      return if home.reload.published_at.nil?

      StarterContent.raise!(Publishing::PublishChanges.call(home, actor: actor))
    end

    def ensure_home!
      home = Page.find_by(parent_id: nil) ||
        StarterContent.raise!(Pages::Save.call(attributes: { published: true }, translations: { @locale => { title: "Home", slug: "" } }))

      if home.content_blocks.none?
        StarterContent.raise!(ContentBlocks::Save.call(ContentBlock.new(owner: home), attributes: { block_type: "rich_text" },
          translations: { @locale => { body: StarterContent.document(StarterContent::WELCOME_MARKDOWN) } }))
        # The copy taken when the homepage was published is empty: the visitor
        # sees a live page as it was last published, so publish what was just
        # written (a homepage that is not live has nothing on the site to change).
        publish_what_was_written(home)
      end

      home
    end
  end
end
