# One valid call of every `ApplicationService`, for the behavioural contract
# (`test/services/service_behaviour_contract_test.rb`).
#
# HOW TO ADD A SERVICE. A new `ApplicationService` subclass fails the contract
# until it has an entry in FACTORIES (or in OWN_RESULT below, with a reason),
# and its name is added to the expected list in the contract test. An entry
# is a lambda run on the test instance (so it may use `ContentHelper`,
# fixtures and `with_locales`) that builds the records the call needs -- as
# the trusted nil actor, before the test switches to the actor under test --
# and returns:
#
#   call:       -> { Tags::Rename.call(tag, name: "new") }  # the service call; nothing is built here
#   permission: "tags.manage"      # the key the service must refuse this call with
#   on:         tag                # what the refusal names: the persisted record, its class for a
#                                  # refused create (an unsaved record), nil for none
#
# Optional: `control_actor:` (a user to run the control as, for a service
# with a User-only rule: the control then runs on the :admin channel) and `control_audit_only:` (a reason, for a call that
# legitimately writes nothing but the audit log) and `control_unaudited:` (a
# reason, for a service that says `# audit: none`: the control must then
# record nothing).
#
# Two runs prove the call:
#
# - REFUSED: as an actor with no grants the call is denied for `permission`
#   on `on`, writes one audit row, and changes NO table (a digest of every
#   table but the audit log, before and after -- no hand-written list that
#   could miss one);
# - CONTROL: the same call as the trusted actor (or `control_actor`), in a
#   savepoint that is rolled back, answers ok and changes at least one
#   table. A call that changes nothing even when allowed would make the
#   refusal run above prove nothing, so the factory must be made to change
#   something: build the records the service's branches write (a tag needs
#   a `post_list` block naming it, a translation an original edited after
#   it was made, a trashed page a child and an image).
#
# A service with several ways in (create and update) can add a variant to
# VARIANTS: the contract runs it too, as "<Service> (<variant>)".
#
# A SELF_SERVICE entry also returns `owner:` (the user whose own record
# `own:` changes), `own:` (the call made on that user's record) and
# `own_event:` (the audit action it records).
module ServiceCalls
  # The four services open to any signed-in user for their OWN record.
  # `manager_may:` is what a holder of the right to manage others (the Admin
  # group) gets when acting on someone else's record: the call, or a refusal
  # (`Users::UpdateProfile`'s anyone else goes through `Users::Save`, even
  # for a `users.manage` holder).
  SELF_SERVICE = {
    "ApiTokens::Issue" => { manager_may: true, reason: "any signed-in user may issue a token for themselves; anyone else needs tokens.manage" },
    "ApiTokens::Revoke" => { manager_may: true, reason: "any signed-in user may revoke their own token; anyone else needs tokens.manage" },
    "Users::UpdatePassword" => { manager_may: true, reason: "any signed-in user may change their own password; anyone else needs users.manage" },
    "Users::UpdateProfile" => { manager_may: false, reason: "any signed-in user may change their own name and notes settings; anyone else's name goes through Users::Save, and nobody changes someone else's settings" }
  }.freeze

  # The two bulk services answer with their own result (no `denied?`): an id
  # the actor cannot read is NOT FOUND, never refused, and a post they can
  # read but not act on is refused by the single-record service the bulk one
  # runs. They authorize and audit nothing themselves -- `Posts::Save` /
  # `Trash::Move` / `Trash::Restore` do, once per post.
  OWN_RESULT = {
    "Posts::Bulk" => "ids load through AccessControl.scope; each post is authorized and audited by Posts::Save or Trash::Move",
    "Posts::BulkRestore" => "ids load through AccessControl.scope; each post is authorized and audited by Trash::Restore"
  }.freeze

  # Services a token reaches through MCP (`app/mcp/mcp/tools/`): for these the
  # contract also runs the call as a token on the :mcp channel, once with each
  # half of the intersection (group and user) lacking the right.
  MCP_REACHABLE = {
    "Posts::Save" => "the create_post and update_post tools"
  }.freeze

  # `ApplicationService` subclasses that are not services of their own (a
  # base class other services inherit from).
  ABSTRACT = [].freeze

  PASSWORD = "a-long-password-1".freeze

  # Tables the digest leaves out: the audit log (what a refusal writes, and
  # an allowed call too) and Rails' own bookkeeping.
  IGNORED_TABLES = %w[audit_events schema_migrations ar_internal_metadata].freeze

  def self.for(service_class, test, variant: nil)
    name = service_class.name
    factory = variant ? VARIANTS.dig(name, variant) : FACTORIES[name]
    raise ArgumentError, "add a call factory for #{service_class} to test/support/service_calls.rb" unless factory

    test.instance_exec(&factory)
  end

  def self.variants(service_class) = VARIANTS.fetch(service_class.name, {}).keys

  def self.exempt?(service_class)
    SELF_SERVICE.key?(service_class.name) || OWN_RESULT.key?(service_class.name) || ABSTRACT.include?(service_class.name)
  end

  # One digest per table: md5 over every row's text, in a stable order. Any
  # insert, update or delete in any table changes its digest.
  def self.digests(except: IGNORED_TABLES)
    connection = ActiveRecord::Base.connection
    (connection.tables - except).sort.index_with do |table|
      quoted = connection.quote_table_name(table)
      connection.select_value("SELECT md5(coalesce(string_agg(t::text, '' ORDER BY t::text), '')) FROM #{quoted} t")
    end
  end

  # A stand-in AI provider, so `AI::Translate` can be allowed.
  class StubProvider
    def initialize(api_key:, model:); end

    def translate(texts:, from:, to:, format:) = texts.map { |text| "[#{to}] #{text}" }
  end

  # Helpers the factories share, mixed into the test.
  module Builders
    def draft_page_with_blocks(count: 1)
      page = create_page(title: "Blocks", published: false)
      blocks = Array.new(count) do
        ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }).record
      end
      [ page, blocks ]
    end

    # A draft page with a three-column section holding `count` blocks in
    # column 3: what a fold, a lift and a delete of a section all write.
    def draft_page_with_section(count: 2)
      page = create_page(title: "Section", published: false)
      section = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "section", settings: { "layout" => "three" } }).record
      blocks = Array.new(count) do
        ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text", section_id: section.id, section_column: 3 }).record
      end
      [ page, section, blocks ]
    end

    # A post tagged `name`, and a page whose `post_list` block names the tag:
    # what a tag service writes beyond the tag itself (the block's settings,
    # its page, the public paths of the listed posts).
    def tagged_post_with_listing(name)
      post = create_post(title: "Tagged #{name}", tags: [ name ])
      page = create_page(title: "Listing #{name}")
      result = ContentBlocks::Save.call(ContentBlock.new(owner: page),
        attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => name } })
      assert result.ok?, result.errors.to_sentence
      post
    end

    def tag_named(name)
      Tag.find_by!(name: name)
    end

    def trashed(record)
      assert Trash::Move.call(record).ok?
      record.reload
    end

    # A draft page with a child and a library image as its hero: what the
    # trash services write beyond the page itself.
    def draft_branch_with_image
      asset = create_media_asset
      page = Pages::Save.call(attributes: { parent: root_page, published: false, hero_media_asset_id: asset.id },
        translations: { "en" => { title: "Branch" } }).record
      child = create_page(title: "Leaf", parent: page, published: false)
      [ page, child, asset ]
    end

    def two_locales(&block) = with_locales(%w[en de], default: "en", &block)

    def stranger_target(email: "target@example.com")
      User.create!(email_address: email, password: PASSWORD)
    end

    def png_upload = Rack::Test::UploadedFile.new(file_fixture("tiny.png"), "image/png")

    # A thread on `subject` with its first message, written by `by` (a user
    # who may read it): what the notes services act on.
    def note_on(subject, by: users(:one), body: "A question")
      result = as(by) { Notes::Start.call(subject, body: body) }
      assert result.ok?, result.errors.to_sentence
      result.record
    end
  end

  FACTORIES = {
    # A request the holder's tab did not answer in time: the call that passes the
    # block over, which is the one that writes an event. The control is the
    # requester, a person: a take-over has no meaning for the trusted actor.
    "Editing::TakeOver" => lambda {
      page, (block,) = draft_page_with_blocks
      Editing::Reservation.claim(subject: block, record: page, user: users(:two), tab: "tab-holder-01", now: 20.seconds.ago)
      Editing::Reservation.request(subject: block, by: users(:one), tab: "tab-asker-001", now: 10.seconds.ago)
      { call: -> { Editing::TakeOver.call(block, record: page, tab: "tab-asker-001") }, permission: "pages.edit", on: page, control_actor: users(:one) }
    },

    # Allowed, it only suggests: it writes the audit event and nothing else.
    "AI::Translate" => lambda {
      two_locales
      AI::Providers.register("test/stub", ServiceCalls::StubProvider)
      Current.site.update!(ai_provider: "test/stub", ai_api_key: "sk-test")
      @ai_providers_registered = true
      page = create_page(title: "Hello")
      { call: -> { AI::Translate.call(page, fields: [ "title" ], to: "de") }, permission: "ai.translate", on: nil,
        control_audit_only: "suggestions only: AI::Translate never saves, it records ai.translated" }
    },

    "ApiTokens::Issue" => lambda {
      target = users(:author)
      group = access_control_groups(:read_only)
      { call: -> { ApiTokens::Issue.call(target, group: group) }, permission: "tokens.manage", on: target,
        owner: target, own: -> { ApiTokens::Issue.call(target, group: group) }, own_event: "token.issued" }
    },

    "ApiTokens::Revoke" => lambda {
      target = users(:author)
      token, = ApiToken.generate!(target, group: access_control_groups(:read_only))
      mine, = ApiToken.generate!(target, group: access_control_groups(:read_only))
      { call: -> { ApiTokens::Revoke.call(token) }, permission: "tokens.manage", on: token,
        owner: target, own: -> { ApiTokens::Revoke.call(mine) }, own_event: "token.revoked" }
    },

    "ContentBlocks::Destroy" => lambda {
      _page, (block,) = draft_page_with_blocks
      { call: -> { ContentBlocks::Destroy.call(block) }, permission: "pages.edit", on: block }
    },

    "ContentBlocks::Duplicate" => lambda {
      _page, section, = draft_page_with_section
      { call: -> { ContentBlocks::Duplicate.call(section) }, permission: "pages.edit", on: section }
    },

    "ContentBlocks::Reorder" => lambda {
      page, (first, second) = draft_page_with_blocks(count: 2)
      { call: -> { ContentBlocks::Reorder.call(page, [ second.id, first.id ]) }, permission: "pages.edit", on: page }
    },

    "ContentBlocks::Save" => lambda {
      _page, (block,) = draft_page_with_blocks
      { call: -> { ContentBlocks::Save.call(block, attributes: { settings: {} }, translations: { "en" => { caption: "x" } }) },
        permission: "pages.edit", on: block }
    },

    "Groups::Destroy" => lambda {
      group = AccessControl::Group.create!(name: "Doomed")
      AccessControl::Grant.create!(group: group, permission: "posts.read", scope: {})
      AccessControl::Membership.create!(group: group, user: users(:author))
      ApiToken.generate!(users(:one), group: group)
      { call: -> { Groups::Destroy.call(group) }, permission: "groups.manage", on: group }
    },

    "Groups::Save" => lambda {
      group = AccessControl::Group.create!(name: "Editors of things")
      AccessControl::Grant.create!(group: group, permission: "posts.read", scope: {})
      AccessControl::Membership.create!(group: group, user: users(:author))
      { call: -> { Groups::Save.call(group, attributes: { name: "Renamed", grants: [ { permission: "posts.edit", scope: {} } ], member_ids: [ users(:reader).id ] }) },
        permission: "groups.manage", on: group }
    },

    "Locales::Configure" => lambda {
      two_locales
      create_page(title: "Something translated")
      { call: -> { Locales::Configure.call([ { code: "en" }, { code: "de", fallbacks: [ "en" ] } ]) }, permission: "languages.manage", on: Current.site.reload }
    },

    "Locales::Disable" => lambda {
      two_locales
      create_page(title: "Something translated")
      { call: -> { Locales::Disable.call("de") }, permission: "languages.manage", on: Current.site.reload }
    },

    "Locales::Enable" => lambda {
      two_locales
      create_page(title: "Something translated")
      { call: -> { Locales::Enable.call("es") }, permission: "languages.manage", on: Current.site.reload }
    },

    "Locales::MakeDefault" => lambda {
      two_locales
      create_page(title: "Something translated")
      { call: -> { Locales::MakeDefault.call("de") }, permission: "languages.manage", on: Current.site.reload }
    },

    "Media::Save" => lambda {
      asset = create_media_asset
      { call: -> { Media::Save.call(asset, attributes: { title: "Renamed" }, translations: { "en" => { alt: "Alt" } }) },
        permission: "media.manage", on: asset }
    },

    "Media::Upload" => lambda {
      file = png_upload
      { call: -> { Media::Upload.call(file: file) }, permission: "media.upload", on: Media::Asset }
    },

    # A message someone else wrote: deleting it is moderation, which the
    # trusted actor may; the stranger is refused for the read right first.
    "Notes::DeleteMessage" => lambda {
      page = create_page(title: "Noted", published: false)
      message = note_on(page).first_message
      { call: -> { Notes::DeleteMessage.call(message) }, permission: "pages.read", on: page }
    },

    # Only its author may edit a message, so the control runs as the author.
    "Notes::EditMessage" => lambda {
      page = create_page(title: "Noted", published: false)
      message = note_on(page, by: users(:one)).first_message
      { call: -> { Notes::EditMessage.call(message, body: "Reworded") }, permission: "pages.read", on: page, control_actor: users(:one) }
    },

    # The actor's own inbox rows: the control runs as the person told.
    "Notes::MarkRead" => lambda {
      page = create_page(title: "Noted", published: false)
      note_on(page, by: users(:one), body: "Look, @[#{users(:two).id}]")
      { call: -> { Notes::MarkRead.call(container: page) }, permission: "pages.read", on: page, control_actor: users(:two),
        control_unaudited: "a read mark is the reader's own bookkeeping, not a change to content" }
    },

    "Notes::Pin" => lambda {
      page = create_page(title: "Noted", published: false)
      thread = note_on(page)
      { call: -> { Notes::Pin.call(thread) }, permission: "pages.edit", on: page }
    },

    # Whoever may read the record may react; the control is someone else's
    # reaction to the owner's note.
    "Notes::React" => lambda {
      page = create_page(title: "Noted", published: false)
      note = note_on(page).first_message
      { call: -> { Notes::React.call(note, emoji: "👍", on: true) }, permission: "pages.read", on: page, control_actor: users(:two),
        control_unaudited: "a reaction is an acknowledgement, not a change to content or to a note's text" }
    },

    "Notes::Remove" => lambda {
      page = create_page(title: "Noted", published: false)
      note_on(page)
      trashed(page)
      { call: -> { Notes::Remove.call(page) }, permission: "pages.delete", on: page }
    },

    "Notes::Reopen" => lambda {
      page = create_page(title: "Noted", published: false)
      thread = note_on(page)
      assert Notes::Resolve.call(thread).ok?
      { call: -> { Notes::Reopen.call(thread) }, permission: "pages.read", on: page }
    },

    "Notes::Reply" => lambda {
      page = create_page(title: "Noted", published: false)
      thread = note_on(page)
      { call: -> { Notes::Reply.call(thread, body: "An answer") }, permission: "pages.read", on: page }
    },

    "Notes::Resolve" => lambda {
      page = create_page(title: "Noted", published: false)
      thread = note_on(page)
      { call: -> { Notes::Resolve.call(thread) }, permission: "pages.read", on: page }
    },

    # A person's own follow row: the control runs as someone who never wrote in the thread.
    "Notes::SetFollowing" => lambda {
      page = create_page(title: "Noted", published: false)
      thread = note_on(page, by: users(:one))
      { call: -> { Notes::SetFollowing.call(thread, following: true) }, permission: "pages.read", on: page, control_actor: users(:two),
        control_unaudited: "following a thread changes who is told, not the content or the thread" }
    },

    "Notes::Start" => lambda {
      page = create_page(title: "Noted", published: false)
      { call: -> { Notes::Start.call(page, body: "A question") }, permission: "pages.read", on: page }
    },

    "Notes::Unpin" => lambda {
      page = create_page(title: "Noted", published: false)
      thread = note_on(page)
      assert Notes::Pin.call(thread).ok?
      { call: -> { Notes::Unpin.call(thread) }, permission: "pages.edit", on: page }
    },

    "Pages::Move" => lambda {
      target = create_page(title: "Target")
      create_page(title: "Sibling", parent: target)
      moving = create_page(title: "Moving")
      { call: -> { Pages::Move.call(moving, parent: target, position: 0) }, permission: "pages.move", on: moving }
    },

    "Pages::Save" => lambda {
      page = create_page(title: "Edit me", published: false)
      { call: -> { Pages::Save.call(page, attributes: { published: true }, translations: { "en" => { title: "Edited" } }) },
        permission: "pages.edit", on: page }
    },

    "Posts::Save" => lambda {
      post = create_post(title: "Edit me", published: false, tags: [ "kept" ])
      { call: -> { Posts::Save.call(post, attributes: { published: true, tag_names: [ "other" ] }, translations: { "en" => { title: "Edited" } }) },
        permission: "posts.edit", on: post }
    },

    "Settings::Save" => lambda {
      { call: -> { Settings::Save.call(Current.site, attributes: { time_zone: "Europe/Berlin" }, translations: { "en" => { title: "Renamed" } }) },
        permission: "settings.manage", on: Current.site.reload }
    },

    # A homepage with no block is what makes it ask for rights (the edit it
    # needs for the welcome block); with a block it would ask for none.
    "StarterContents::EnsureHome" => lambda {
      home = root_page
      home.content_blocks.delete_all
      { call: -> { StarterContents::EnsureHome.call(locale: "en") }, permission: "pages.edit", on: home }
    },

    # No homepage yet: the first right it needs is creating the root.
    "StarterContents::Add" => lambda {
      { call: -> { StarterContents::Add.call }, permission: "pages.create", on: Page }
    },

    "Tags::Destroy" => lambda {
      tagged_post_with_listing("doomed")
      tag = tag_named("doomed")
      { call: -> { Tags::Destroy.call(tag) }, permission: "tags.manage", on: tag }
    },

    "Tags::Merge" => lambda {
      tagged_post_with_listing("source")
      create_post(title: "Other", tags: [ "into" ])
      source = tag_named("source")
      into = tag_named("into")
      { call: -> { Tags::Merge.call(source, into: into) }, permission: "tags.manage", on: source }
    },

    "Tags::Rename" => lambda {
      tagged_post_with_listing("old")
      tag = tag_named("old")
      { call: -> { Tags::Rename.call(tag, name: "new") }, permission: "tags.manage", on: tag }
    },

    # The German title was made from "Hello"; the original has since changed,
    # so it is really outdated and confirming it writes the stored source.
    "Translations::Confirm" => lambda {
      two_locales
      page = create_page(title: "Hello", translations: { "de" => { title: "Hallo" } })
      assert Pages::Save.call(page, translations: { "en" => { title: "Hello again" } }).ok?
      { call: -> { Translations::Confirm.call(page, field: "title", locale: "de") }, permission: "pages.edit", on: page }
    },

    "Trash::Empty" => lambda {
      page, = draft_branch_with_image
      trashed(page)
      trashed(create_post(title: "Gone post", published: false))
      { call: -> { Trash::Empty.call }, permission: "trash.empty", on: nil }
    },

    "Trash::Move" => lambda {
      page, = draft_branch_with_image
      { call: -> { Trash::Move.call(page) }, permission: "pages.delete", on: page }
    },

    # The branch goes to the trash with its image; restoring brings back the
    # page, its child and the image.
    "Trash::Restore" => lambda {
      page, _child, asset = draft_branch_with_image
      trashed(page)
      trashed(asset)
      { call: -> { Trash::Restore.call(page) }, permission: "pages.delete", on: page }
    },

    "Trash::Purge" => lambda {
      page, = draft_branch_with_image
      trashed(page)
      { call: -> { Trash::Purge.call(page) }, permission: "pages.delete", on: page }
    },

    # Nullifies what the user owns (a post's author, an image's uploader) and
    # deletes their tokens, sessions and memberships.
    "Users::Destroy" => lambda {
      target = stranger_target
      ApiToken.generate!(target, group: access_control_groups(:read_only))
      AccessControl::Membership.create!(group: access_control_groups(:read_only), user: target)
      target.sessions.create!
      create_post(title: "Theirs", published: false).update_columns(author_id: target.id)
      create_media_asset.update_columns(created_by_id: target.id)
      { call: -> { Users::Destroy.call(target) }, permission: "users.manage", on: target }
    },

    "Users::Save" => lambda {
      target = stranger_target
      { call: -> { Users::Save.call(target, attributes: { name: "Renamed", group_ids: [ access_control_groups(:read_only).id ] }) },
        permission: "users.manage", on: target }
    },

    "Users::UpdatePassword" => lambda {
      target = stranger_target
      target.sessions.create!
      mine = stranger_target(email: "mine@example.com")
      change = ->(user) { Users::UpdatePassword.call(user, password: "a-new-long-password-2", password_confirmation: "a-new-long-password-2") }
      { call: -> { change.call(target) }, permission: "users.manage", on: target,
        owner: mine, own: -> { change.call(mine) }, own_event: "user.updated" }
    },

    # User-only rule: the trusted nil actor and a manager are refused too, so its control runs as the user themselves.
    "Users::UpdateProfile" => lambda {
      target = stranger_target
      mine = stranger_target(email: "mine@example.com")
      { call: -> { Users::UpdateProfile.call(target, name: "Renamed") }, permission: "users.manage", on: target,
        control_actor: target,
        owner: mine, own: -> { Users::UpdateProfile.call(mine, name: "Me") }, own_event: "user.updated" }
    },

    # The two bulk services: see OWN_RESULT. `ids` are real posts.
    "Posts::Bulk" => lambda {
      posts = [ create_post(title: "One", published: false), create_post(title: "Two", published: false) ]
      { call: -> { Posts::Bulk.call(action: "publish", ids: posts.map(&:id)) }, ids: posts.map(&:id), posts: posts }
    },

    "Posts::BulkRestore" => lambda {
      posts = [ trashed(create_post(title: "One", published: false)), trashed(create_post(title: "Two", published: false)) ]
      { call: -> { Posts::BulkRestore.call(ids: posts.map(&:id)) }, ids: posts.map(&:id), posts: posts }
    }
  }.freeze

  # Services with more than one way in. The base entry above covers the
  # update; these cover the create, which a refusal handles differently (an
  # unsaved record is no audit subject, only its type goes in the metadata).
  VARIANTS = {
    "Pages::Save" => {
      "creating" => lambda {
        # Built here, as the trusted actor: inside `call` it would be created
        # (and refused) as the actor under test.
        root = root_page
        { call: -> { Pages::Save.call(attributes: { parent: root }, translations: { "en" => { title: "New" } }) },
          permission: "pages.create", on: Page }
      }
    },
    "Posts::Save" => {
      "creating" => lambda {
        { call: -> { Posts::Save.call(attributes: { content_type: "blog" }, translations: { "en" => { title: "New" } }) },
          permission: "posts.create", on: Post }
      }
    },
    "ContentBlocks::Save" => {
      "creating" => lambda {
        page = create_page(title: "Blocks", published: false)
        { call: -> { ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }) },
          permission: "pages.edit", on: ContentBlock }
      },
      "creating in a column" => lambda {
        page, section, = draft_page_with_section
        { call: -> { ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text", section_id: section.id, section_column: 1 }) },
          permission: "pages.edit", on: ContentBlock }
      },
      "folding a section's columns" => lambda {
        _page, section, = draft_page_with_section
        { call: -> { ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "one" } }) }, permission: "pages.edit", on: section }
      }
    },
    "ContentBlocks::Destroy" => {
      "a section, keeping its blocks" => lambda {
        _page, section, = draft_page_with_section
        { call: -> { ContentBlocks::Destroy.call(section, keep_blocks: true) }, permission: "pages.edit", on: section }
      },
      "a section with its blocks" => lambda {
        _page, section, = draft_page_with_section
        { call: -> { ContentBlocks::Destroy.call(section) }, permission: "pages.edit", on: section }
      }
    },
    "ContentBlocks::Reorder" => {
      "moving a block out of a section" => lambda {
        page, section, (block,) = draft_page_with_section
        { call: -> { ContentBlocks::Reorder.call(page, [ section.id, block.id ], moved_from: { block.id => { section_id: section.id, column: 3 } }) },
          permission: "pages.edit", on: page }
      }
    },
    "Groups::Save" => {
      "creating" => lambda {
        { call: -> { Groups::Save.call(attributes: { name: "Brand new", grants: [ { permission: "posts.read", scope: {} } ] }) },
          permission: "groups.manage", on: AccessControl::Group }
      }
    },
    "Users::Save" => {
      "creating" => lambda {
        { call: -> { Users::Save.call(attributes: { email_address: "new@example.com", password: PASSWORD, password_confirmation: PASSWORD }) },
          permission: "users.manage", on: User }
      }
    }
  }.freeze
end
