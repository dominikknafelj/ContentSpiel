# One valid call of every `ApplicationService`, for the behavioural contract
# (`test/services/service_behaviour_contract_test.rb`).
#
# HOW TO ADD A SERVICE. A new `ApplicationService` subclass fails the contract
# until it has an entry in FACTORIES (or in SELF_SERVICE / OWN_RESULT below,
# with a reason). An entry is a lambda run on the test instance (so it may use
# `ContentHelper`, fixtures and `with_locales`) that builds the records the
# call needs -- as the trusted nil actor, before the test switches to the
# actor under test -- and returns:
#
#   call:    -> { Tags::Rename.call(tag, name: "new") }   # the service call; nothing is built here
#   subject: record_or_nil                                # the record the service changes (nil for a create)
#   tables:  [Tag, PostTag]                               # EVERY table the service can write
#   also:    [post]                                       # other records it could change (optional)
#
# The contract proves a refusal changes nothing by comparing row counts of
# `tables`, and the attributes of `subject` and each of `also`, before and
# after. A factory that names too few tables makes that proof blind: read the
# service, and name everything it, the services it calls and the callbacks of
# the models it saves can write (a page save writes `public_paths`, media
# usages and translation states too). Name a record in `also:` whenever the
# service changes a SECOND record that a row count would not show (a tag's
# posts, a page's blocks, a revoked token).
#
# A service with several ways in (create and update) can add a variant to
# VARIANTS: the contract runs it too, as "<Service> (<variant>)".
#
# A SELF_SERVICE entry also returns `owner:` (the user whose own record `own:`
# changes), `own:` (the call made on that user's record) and `own_event:` (the
# audit action it records); `own_subject:` names the record `own` changes when
# that is not the owner.
module ServiceCalls
  # The four services open to any signed-in user for their OWN record. For a
  # stranger they are refused like any other; the contract runs the factory's
  # `call` as a stranger (a user with no grants, acting on someone else's
  # record) and the factory's `own:` as the record's own user, who succeeds
  # and is audited as `own_event`.
  SELF_SERVICE = {
    "ApiTokens::Issue" => "any signed-in user may issue a token for themselves; anyone else needs tokens.manage",
    "ApiTokens::Revoke" => "any signed-in user may revoke their own token; anyone else needs tokens.manage",
    "Users::UpdatePassword" => "any signed-in user may change their own password; anyone else needs users.manage",
    "Users::UpdateProfile" => "any signed-in user may change their own name; anyone else's goes through Users::Save"
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
  # contract also runs the call as an API token of the user with no grants,
  # on the :mcp channel (a token is judged on its group AND its user).
  MCP_REACHABLE = {
    "Posts::Save" => "the create_post and update_post tools"
  }.freeze

  # `ApplicationService` subclasses that are not services of their own (a
  # base class other services inherit from).
  ABSTRACT = [].freeze

  PASSWORD = "a-long-password-1".freeze

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

  # Helpers the factories share, mixed into the test.
  module Builders
    def draft_page_with_blocks(count: 1)
      page = create_page(title: "Blocks", published: false)
      blocks = Array.new(count) do
        ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }).record
      end
      [ page, blocks ]
    end

    def tag_named(name)
      Tag.find_by!(name: name)
    end

    def trashed(record)
      assert Trash::Move.call(record).ok?
      record.reload
    end

    def two_locales(&block) = with_locales(%w[en de], default: "en", &block)

    def stranger_target(email: "target@example.com")
      User.create!(email_address: email, password: PASSWORD)
    end

    def png_upload = Rack::Test::UploadedFile.new(file_fixture("tiny.png"), "image/png")
  end

  TABLES_OF_A_PAGE = -> { [ Page, Page.hierarchy_class, PublicPath, ContentBlock, Media::Usage, Translations::State ] }
  TABLES_OF_A_POST = -> { [ Post, Tag, PostTag, PostRelation, PublicPath, Media::Usage, Translations::State ] }
  TABLES_OF_THE_SITE = -> { [ SiteSetting, Translations::State, PublicPath, Page, Post ] }

  FACTORIES = {
    "AI::Translate" => lambda {
      two_locales
      page = create_page(title: "Hello")
      { call: -> { AI::Translate.call(page, fields: [ "title" ], to: "de") }, subject: page,
        tables: [ Page, ContentBlock, Translations::State ] }
    },

    "ApiTokens::Issue" => lambda {
      target = users(:author)
      group = access_control_groups(:read_only)
      { call: -> { ApiTokens::Issue.call(target, group: group) }, subject: target, tables: [ ApiToken ],
        owner: target, own: -> { ApiTokens::Issue.call(target, group: group) }, own_event: "token.issued" }
    },

    "ApiTokens::Revoke" => lambda {
      target = users(:author)
      token, = ApiToken.generate!(target, group: access_control_groups(:read_only))
      mine, = ApiToken.generate!(target, group: access_control_groups(:read_only))
      { call: -> { ApiTokens::Revoke.call(token) }, subject: token, tables: [ ApiToken ],
        owner: target, own: -> { ApiTokens::Revoke.call(mine) }, own_event: "token.revoked" }
    },

    "ContentBlocks::Destroy" => lambda {
      page, (block,) = draft_page_with_blocks
      { call: -> { ContentBlocks::Destroy.call(block) }, subject: block, also: [ page ],
        tables: [ ContentBlock, Media::Usage, Translations::State, PublicPath ] }
    },

    "ContentBlocks::Reorder" => lambda {
      page, (first, second) = draft_page_with_blocks(count: 2)
      { call: -> { ContentBlocks::Reorder.call(page, [ second.id, first.id ]) }, subject: page, also: [ first, second ],
        tables: [ ContentBlock ] }
    },

    "ContentBlocks::Save" => lambda {
      page, (block,) = draft_page_with_blocks
      { call: -> { ContentBlocks::Save.call(block, attributes: { settings: {} }, translations: { "en" => { caption: "x" } }) },
        subject: block, also: [ page ], tables: [ ContentBlock, Media::Usage, Translations::State, PublicPath ] }
    },

    "Groups::Destroy" => lambda {
      group = AccessControl::Group.create!(name: "Doomed")
      AccessControl::Grant.create!(group: group, permission: "posts.read", scope: {})
      AccessControl::Membership.create!(group: group, user: users(:author))
      token, = ApiToken.generate!(users(:one), group: group)
      { call: -> { Groups::Destroy.call(group) }, subject: group, also: [ token ],
        tables: [ AccessControl::Group, AccessControl::Grant, AccessControl::Membership, ApiToken ] }
    },

    "Groups::Save" => lambda {
      group = AccessControl::Group.create!(name: "Editors of things")
      AccessControl::Grant.create!(group: group, permission: "posts.read", scope: {})
      AccessControl::Membership.create!(group: group, user: users(:author))
      { call: -> { Groups::Save.call(group, attributes: { name: "Renamed", grants: [ { permission: "posts.edit", scope: {} } ], member_ids: [ users(:reader).id ] }) },
        subject: group, tables: [ AccessControl::Group, AccessControl::Grant, AccessControl::Membership ] }
    },

    "Locales::Configure" => lambda {
      two_locales
      { call: -> { Locales::Configure.call([ { code: "en" }, { code: "de", fallbacks: [ "en" ] } ]) }, subject: Current.site.reload,
        tables: TABLES_OF_THE_SITE.call }
    },

    "Locales::Disable" => lambda {
      two_locales
      { call: -> { Locales::Disable.call("de") }, subject: Current.site.reload, tables: TABLES_OF_THE_SITE.call }
    },

    "Locales::Enable" => lambda {
      two_locales
      { call: -> { Locales::Enable.call("es") }, subject: Current.site.reload, tables: TABLES_OF_THE_SITE.call }
    },

    "Locales::MakeDefault" => lambda {
      two_locales
      { call: -> { Locales::MakeDefault.call("de") }, subject: Current.site.reload, tables: TABLES_OF_THE_SITE.call }
    },

    "Media::Save" => lambda {
      asset = create_media_asset
      { call: -> { Media::Save.call(asset, attributes: { title: "Renamed" }, translations: { "en" => { alt: "Alt" } }) },
        subject: asset, tables: [ Media::Asset, Media::Usage, Translations::State, ActiveStorage::Attachment, ActiveStorage::Blob ] }
    },

    "Media::Upload" => lambda {
      file = png_upload
      { call: -> { Media::Upload.call(file: file) }, subject: nil,
        tables: [ Media::Asset, Media::Usage, Translations::State, ActiveStorage::Attachment, ActiveStorage::Blob, ActiveStorage::VariantRecord ] }
    },

    "Pages::Move" => lambda {
      target = create_page(title: "Target")
      sibling = create_page(title: "Sibling", parent: target)
      moving = create_page(title: "Moving")
      { call: -> { Pages::Move.call(moving, parent: target, position: 0) }, subject: moving, also: [ target, sibling, root_page ],
        tables: TABLES_OF_A_PAGE.call }
    },

    "Pages::Save" => lambda {
      page = create_page(title: "Edit me", published: false)
      { call: -> { Pages::Save.call(page, attributes: { published: true }, translations: { "en" => { title: "Edited" } }) },
        subject: page, also: [ root_page ], tables: TABLES_OF_A_PAGE.call + [ Post ] }
    },

    "Posts::Save" => lambda {
      post = create_post(title: "Edit me", published: false, tags: [ "kept" ])
      { call: -> { Posts::Save.call(post, attributes: { published: true, tag_names: [ "other" ] }, translations: { "en" => { title: "Edited" } }) },
        subject: post, tables: TABLES_OF_A_POST.call }
    },

    "Settings::Save" => lambda {
      { call: -> { Settings::Save.call(Current.site, attributes: { time_zone: "Europe/Berlin" }, translations: { "en" => { title: "Renamed" } }) },
        subject: Current.site.reload, tables: [ SiteSetting, Translations::State, PublicPath ] }
    },

    # A homepage with no block is what makes it ask for rights (the edit it
    # needs for the welcome block); with a block it would ask for none.
    "StarterContents::EnsureHome" => lambda {
      root_page.content_blocks.delete_all
      { call: -> { StarterContents::EnsureHome.call(locale: "en") }, subject: root_page,
        tables: [ Page, ContentBlock, PublicPath, Media::Usage, Translations::State ] }
    },

    "StarterContents::Add" => lambda {
      { call: -> { StarterContents::Add.call }, subject: nil,
        tables: [ Page, Post, ContentBlock, PublicPath, Media::Usage, Translations::State, Tag, PostTag ] }
    },

    "Tags::Destroy" => lambda {
      post = create_post(title: "Tagged", tags: [ "doomed" ])
      tag = tag_named("doomed")
      { call: -> { Tags::Destroy.call(tag) }, subject: tag, also: [ post ], tables: [ Tag, PostTag, Post ] }
    },

    "Tags::Merge" => lambda {
      post = create_post(title: "Tagged", tags: [ "source" ])
      create_post(title: "Other", tags: [ "into" ])
      source = tag_named("source")
      into = tag_named("into")
      { call: -> { Tags::Merge.call(source, into: into) }, subject: source, also: [ post, into ], tables: [ Tag, PostTag, Post ] }
    },

    "Tags::Rename" => lambda {
      post = create_post(title: "Tagged", tags: [ "old" ])
      tag = tag_named("old")
      { call: -> { Tags::Rename.call(tag, name: "new") }, subject: tag, also: [ post ], tables: [ Tag, PostTag, Post ] }
    },

    "Translations::Confirm" => lambda {
      two_locales
      page = create_page(title: "Hello", translations: { "de" => { title: "Hallo" } })
      { call: -> { Translations::Confirm.call(page, field: "title", locale: "de") }, subject: page,
        tables: [ Page, Translations::State ] }
    },

    "Trash::Empty" => lambda {
      trashed_page = trashed(create_page(title: "Gone page", published: false))
      trashed_post = trashed(create_post(title: "Gone post", published: false))
      { call: -> { Trash::Empty.call }, subject: trashed_page, also: [ trashed_post ],
        tables: TABLES_OF_A_PAGE.call + TABLES_OF_A_POST.call + [ Media::Asset, ActiveStorage::Attachment, ActiveStorage::Blob ] }
    },

    "Trash::Move" => lambda {
      page = create_page(title: "Branch", published: false)
      child = create_page(title: "Leaf", parent: page, published: false)
      { call: -> { Trash::Move.call(page) }, subject: page, also: [ child ], tables: TABLES_OF_A_PAGE.call + [ Post ] }
    },

    "Trash::Purge" => lambda {
      page = trashed(create_page(title: "Branch", published: false))
      { call: -> { Trash::Purge.call(page) }, subject: page, tables: TABLES_OF_A_PAGE.call + [ Post ] }
    },

    "Trash::Restore" => lambda {
      page = trashed(create_page(title: "Branch", published: false))
      { call: -> { Trash::Restore.call(page) }, subject: page, tables: TABLES_OF_A_PAGE.call + [ Post ] }
    },

    "Users::Destroy" => lambda {
      target = stranger_target
      token, = ApiToken.generate!(target, group: access_control_groups(:read_only))
      AccessControl::Membership.create!(group: access_control_groups(:read_only), user: target)
      target.sessions.create!
      { call: -> { Users::Destroy.call(target) }, subject: target, also: [ token ],
        tables: [ User, ApiToken, Session, AccessControl::Membership ] }
    },

    "Users::Save" => lambda {
      target = stranger_target
      { call: -> { Users::Save.call(target, attributes: { name: "Renamed", group_ids: [ access_control_groups(:read_only).id ] }) },
        subject: target, tables: [ User, Session, AccessControl::Membership ] }
    },

    "Users::UpdatePassword" => lambda {
      target = stranger_target
      target.sessions.create!
      mine = stranger_target(email: "mine@example.com")
      change = ->(user) { Users::UpdatePassword.call(user, password: "a-new-long-password-2", password_confirmation: "a-new-long-password-2") }
      { call: -> { change.call(target) }, subject: target, tables: [ User, Session ],
        owner: mine, own: -> { change.call(mine) }, own_event: "user.updated" }
    },

    "Users::UpdateProfile" => lambda {
      target = stranger_target
      mine = stranger_target(email: "mine@example.com")
      { call: -> { Users::UpdateProfile.call(target, name: "Hijacked") }, subject: target, tables: [ User ],
        owner: mine, own: -> { Users::UpdateProfile.call(mine, name: "Me") }, own_event: "user.updated" }
    },

    # The two bulk services: see OWN_RESULT. `ids` are real records the actor
    # under test cannot read.
    "Posts::Bulk" => lambda {
      posts = [ create_post(title: "One", published: false), create_post(title: "Two", published: false) ]
      { call: -> { Posts::Bulk.call(action: "publish", ids: posts.map(&:id)) }, subject: posts.first, also: [ posts.last ],
        ids: posts.map(&:id), tables: [ Post, PublicPath, Media::Usage, Translations::State ] }
    },

    "Posts::BulkRestore" => lambda {
      posts = [ trashed(create_post(title: "One", published: false)), trashed(create_post(title: "Two", published: false)) ]
      { call: -> { Posts::BulkRestore.call(ids: posts.map(&:id)) }, subject: posts.first, also: [ posts.last ],
        ids: posts.map(&:id), tables: [ Post, PublicPath, Media::Usage, Translations::State ] }
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
        { call: -> { Pages::Save.call(attributes: { parent: root }, translations: { "en" => { title: "New" } }) }, subject: nil,
          tables: TABLES_OF_A_PAGE.call + [ Post ] }
      }
    },
    "Posts::Save" => {
      "creating" => lambda {
        { call: -> { Posts::Save.call(attributes: { content_type: "blog" }, translations: { "en" => { title: "New" } }) }, subject: nil,
          tables: TABLES_OF_A_POST.call }
      }
    },
    "ContentBlocks::Save" => {
      "creating" => lambda {
        page = create_page(title: "Blocks", published: false)
        { call: -> { ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }) }, subject: nil,
          also: [ page ], tables: [ ContentBlock, Media::Usage, Translations::State ] }
      }
    },
    "Groups::Save" => {
      "creating" => lambda {
        { call: -> { Groups::Save.call(attributes: { name: "Brand new", grants: [ { permission: "posts.read", scope: {} } ] }) }, subject: nil,
          tables: [ AccessControl::Group, AccessControl::Grant, AccessControl::Membership ] }
      }
    },
    "Users::Save" => {
      "creating" => lambda {
        { call: -> { Users::Save.call(attributes: { email_address: "new@example.com", password: PASSWORD, password_confirmation: PASSWORD }) },
          subject: nil, tables: [ User, Session, AccessControl::Membership ] }
      }
    }
  }.freeze
end
