# Post types: declared by what they bring, switched on in Settings

Status: decided direction, for issue #114 ("Content types are code-only, have
no declarations, and ship the owner's site"). The owner decided five things
before this spec was written; they are marked "(owner's decision)". Every
other decision is marked "(my call)", with its reason, and §15 lists them
together with what only the owner can answer. Every new screen element is the
design agent's (§12): this spec says what each one must do and say, never how
it looks.

## 1. Why

Three post types are registered unconditionally (`config/initializers/types.rb`:
`ContentTypes::Blog`, `ContentTypes::ResumeEntry`, `ContentTypes::NowUpdate`),
so every site ships the owner's personal site. An editor on a business site
sees "Resume entry" and "Now update" in the New post dialog, the posts list's
type filter, the Post list block's select, the permission matrix and the
Mind graph, and a new site's starter content makes a Resume and a Now page
nobody asked for.

The types also lack what block types got in "Block types declare what they
bring" (2026-10-13): a content type declares its two components but not the
methods their templates may call, so `Theme::Contract::POST_COMPONENTS` is
written by hand, and the shared samples and the public canary build posts by
hand rather than from what each type declares. A fourth built-in type today
means editing the theme contract, the canary and the seeds by hand.

The README says "Posts of types you define", which is not true: a site
cannot define one.

## 2. Goals, non-goals, anti-goals

Goals
- A site switches each post type on or off in Settings, saved with the save
  bar, and the switch is audited (owner's decision).
- A new site starts with Blog alone (owner's decision). Resume entry and Now
  update are the optional "personal site" pair (owner's decision), each with
  its own switch (§8).
- An existing site keeps every type on after the upgrade (owner's decision).
- A type switched off is dormant, not deleted (owner's decision): its posts
  stay stored, untouched, and come back exactly as they were when the type is
  switched on again. §6 says what a dormant post is at every place a post is
  read.
- A content type declares the theme methods of its components and a sample,
  as a block type does; the theme contract's post lines are derived from the
  registry and held by the ledger; the shared samples and the canary build a
  post of every declared type from its sample.
- The README says what is true.

Non-goals (each a later step, my call)
- A `content_types` plugin hook for a gem (the issue's third step). The switch
  is built so that a gem's type is one more row of the same card (§4.4), and
  the declarations are the ones a hook would take, but the hook waits for the
  roadmap's "Block types from outside, step 2" (getting a gem into a site's
  image), which nothing in this spec needs. §15 asks the owner.
- Post types defined in CS Studio (roadmap "Next", item 3). The stored switch
  holds names, so an admin-defined type's `owner/name` fits it unchanged.
- `tokens` and `stylesheet` declarations for a content type. No built-in post
  component brings a stylesheet or a token (their looks are `theme.css`'s), so
  the declarations would have no user; they come with the hook, when a gem's
  type can bring one ("No compatibility code before it is needed").
- Translating a type's label (`t.label "Blog"` stays an English literal, as
  every content type's and block type's label is today).

Anti-goals
- Deleting, moving or rewriting a dormant post's rows, copies, tags, notes,
  relations or translation states. Switching off writes the settings row and
  the derived addresses and search entries, nothing else.
- A second way to remove a type: a type is in the registry or it is not; the
  switch is the site's only control over a declared type.
- Asking for confirmation in a dialog. The save bar's Save is the
  confirmation, and switching back on restores everything (§7.4) (my call).

## 3. Words

CS Studio says **post type** (the Mind graph already does: "Post types",
"post type"); the code keeps `content_type`, `ContentTypes` and
`ContentTypeDefinition`, which name a column, a registry and a jsonb key that
nothing gains from renaming (my call). The three admin strings that say
"content type" today (`admin.posts…description` "Choose a content type to
create your first post.", the groups screen's `dormant`, `all_types` and
`types`) change to "post type" in the same change, so a person meets one word
(my call; key values only, no key renamed).

**Declared**: registered in code (`ContentTypes.all`). **Switched on**: declared
and named in the site's switch. **Dormant**: a post whose type is declared and
switched off, or no longer declared (a removed gem's type, the case the code
already calls "unregistered"). Everything §6 says of a dormant post holds for
both, except where it names the label: an undeclared type has none and shows
its stored name, as today.

## 4. The switch

### 4.1 Where it is stored (my call)

`site_settings.content_types`, `jsonb`, `NOT NULL`, default `["blog"]`: the
names of the types switched on. The settings row is where the site's other
switches live (`locales`), it is locked by every writer of it (CLAUDE.md:
`Settings::Save` locks the row first), and its commit already moves the public
content version (`SiteSetting#reset_cached_state`), so every public page
answers anew after a switch with no code of its own.

A list of what is ON, not of what is off (my call): a type that arrives later
(a new built-in, a gem's, an admin-defined one) is off until someone switches
it on, which is what a business site wants of a future "Resume"-like type.
The cost: a gem's integrator must switch its type on once in Settings.

### 4.2 A new site, an existing site, development, tests

- **A new site** gets the column's default, `["blog"]` (owner's decision): a new
  database is built from `db/schema.rb`, and `SiteSetting.instance` creates the
  row with column defaults. The setup wizard gets no step for it (my call):
  the starter content then makes the Blog section alone
  (`StarterContent.sections` reads the switched-on types).
- **An existing site** (owner's decision): the migration
  `20261116090000_add_content_types_to_site_settings` adds the column and, in
  the same migration, writes `["blog", "resume_entry", "now_update"]` into
  every existing row, so `contentspiel upgrade` changes nothing a visitor or
  an editor sees. The migration updates a row and inserts none, so the
  "a row a migration inserts reaches no new site" rule
  (`docs/reference/users-groups-tokens.md`) does not apply; its `down` drops
  the column.
- **Development**: `db/seeds.rb` switches all three on, beside German and
  Spanish and under the same condition (a database with no pages and no
  posts), through `Settings::Save`, so the showcase and the demo posts have
  their types (my call; as the languages are).
- **Tests**: the fixture site (`test/fixtures/site_settings.yml`) has all three
  on, as it has three languages, and says so in its comment;
  `TestTypes#with_test_types` switches `test/event` on for its block and back.
  `test/models/site_setting_test.rb` holds the column's default.

### 4.3 What a stored list may hold

- An Array of distinct Strings of `ContentModel::Registry::NAME_FORMAT`
  (`SiteSetting#content_types_are_well_formed`, always validated).
- **At least one declared type switched on**, validated only when the column
  changes (`SiteSetting#a_content_type_is_switched_on`), with the field error
  "Keep at least one post type switched on." (`activerecord.errors.models.
  site_setting.attributes.content_types.none_switched_on`) (my call). A site
  with no post type would leave the Post list block, the posts list, the New
  post dialog and `ContentTypes.default` with nothing to stand on; a site with
  pages only is a later question (§15). A stored list whose declared names all
  went away (every gem removed) is not refused until it is changed; then
  `ContentTypes.default` falls back to the first declared type (§5).
- A name that is not declared (a removed gem's type) is **carried**: not drawn,
  never removed by a save, and the gem's return finds its type switched on
  again (CLAUDE.md: a type removed from its registry is dormant, carried
  through saves). There is no Remove for it (my call): the entry matches
  nothing and costs nothing, and removing it would make a reinstalled gem's
  posts dormant for no reason anyone chose.

### 4.4 A gem's type, later

When the hook comes, a gem's type is declared and off; the Settings card
draws it as one more row, under its group if it declares one (§9.4). Nothing
in this spec has to change for that.

## 5. The registry's two sets

`ContentTypes` keeps the shared `ContentModel::Registry` (`all`, `names`,
`find`, `fetch`: the DECLARED types; `BlockTypes` and `FieldGroups` share the
module and keep its meaning) and gains the site's set (my call), read from
`Current.site` as `Locales.enabled` is:

- `ContentTypes.switched_on(site: Current.site) -> Array<ContentTypeDefinition>`,
  declared types the site names, in registration order (never stored order).
- `ContentTypes.switched_on_names(site: Current.site) -> Array<String>`.
- `ContentTypes.switched_on?(name, site: Current.site) -> Boolean`.
- `ContentTypes.default` becomes the first switched-on type, else the first
  declared one (what a Post list block with no filter draws its list through).
- `Post#type_switched_on? -> Boolean` and the scope
  `Post.of_switched_on_types` (`where(content_type: ContentTypes.switched_on_names)`),
  the one way a list narrows to them, with its line saying what it answers.

**Which set a reader takes is a decision, written down** (my call). A new
caller of `ContentTypes.all` or `.names` that meant "what a visitor may see"
would leak a dormant type, so `test/lib/content_type_sets_test.rb` scans
`app/`, `lib/`, `config/` and `db/seeds` (comments stripped) for
`ContentTypes.all` and `ContentTypes.names` and fails for a file not in its
`DECLARED_READERS` map, each entry with its reason, and for an entry that
matches nothing. `.find` and `.fetch` are not scanned: looking up a
definition for its label, hue or fields is right for a dormant post too.

Nothing in `to_prepare`, the theme check or the theme contract reads the
switch: they run at boot, where there may be no database, and a theme's
contract is the code's whatever a site switches on.

## 6. What a dormant post is, everywhere

The rows, the copies, the tags, the related posts, the notes, the translation
states and the media usages of a dormant post are left exactly as they are.
What changes is what reads them.

**The public site.** A dormant post has no address: `PublicSite::Paths` derives
none for it (`compute_path` asks `type_switched_on?` where it asks for a
definition today, and `dependent_posts`' unhoused posts narrow to
`switched_on_names`), so its old address is a 404, it is in no sitemap, the
preview of it is a 404 (the preview resolves by address), and a link to it
in rich text renders as plain text, as a link to a trashed post does. A Post
list block lists no dormant post: `BlockTypes::PostList` (`listed_posts`,
`matches?`) and `Publishing::Listing` narrow to the switched-on names, so a
list filtered to a switched-off type lists nothing and one with no filter
lists the switched-on types' posts. Its addresses are derived rows, deleted as
the trash frees a post's (`docs/reference/trash.md`); an old slug's redirect
rows go with them and do not come back (§7.4).

**Search.** `SiteSearch::Documents.for` builds no document for a dormant post,
the switch rebuilds the index (§7.2), and until the rebuild has run
`SiteSearch::Shown` drops any hit with no address, so a dormant post is never
drawn as a result.

**The posts list.** A dormant post is listed, so it can be found, opened,
trashed or taken back by switching its type on (my call: the work surfaces
below leave it out; the list is where content is found). Its row is marked as
switched off (§12, D3). The type filter offers the switched-on types, then each
switched-off type the viewer has at least one kept readable post of, marked as
off (one statement, `Posts::List#types_present`). The status counts count it.

**The editor.** A dormant post opens view only (my call): `AccessControlHelper
#can_edit?` answers false for a post whose type is not switched on, which
draws the "View only" editor that exists for a reader without `edit`, and the
header offers no publishing action (`HeaderComponent#may_publish?` false).
Above the form a notice says the type is switched off, that its posts are kept
and not on the site, and, for a holder of `settings.manage`, links to Settings
› Post types (§12, D4). Trash stays offered. Notes stay open: a conversation
about kept content harms nothing (my call).

**Writes.** Every service that writes a post's content or its publication
refuses a dormant post with the sentence "<Label> is switched off. Switch it on
in Settings to change this post." (`admin.posts.switched_off`, with `%{type}`;
an undeclared type's stored name in its place), as a failure (422), before its
rights are checked and with nothing written or audited (a state, not a right):
`Posts::Save` (an autosave, a publish-only save, a new post of that type, an
MCP `create_post` or `update_post`), `Publishing::PublishChanges`,
`Publishing::DiscardChanges` and `Publishing::CancelScheduledChange` on a
post. The check is one method, `ApplicationService#switched_off_refusal(post)`.
`Posts::Bulk` needs nothing: it publishes through `Posts::Save`, so a dormant
post in a selection comes back in `failed` with the sentence. A stale tab whose
type was switched off meanwhile meets the same 422 at its next autosave.

**What still works.** `Trash::Move`, `Trash::Restore` (the post comes back
dormant; `content_type_is_registered` keeps meaning declared, so its full
validation passes) and `Trash::Purge`, including the retention job; the
Trash list shows it with its type. A scheduled dormant post's time still comes
(`Publishing::Version.settle!`), and it is simply in no list and at no
address until its type is on again.

**The New post dialog** offers the switched-on types the viewer may create
(`NewPostFormComponent`); with one, it draws its one-type form, as a
Blog-only site will. A `?type=` naming a switched-off type is refused by
`Posts::Save` with the sentence.

**The Post list block's card.** Its type select (`Admin::Fields::ContentTypeField`)
offers the switched-on types and, when the stored value names a switched-off or
undeclared type, that value too, labelled as switched off (`admin.components.
fields.content_type.switched_off`, "%{label} (switched off)"), so a save of the
block keeps its filter (my call; the dormant rule). The card says under the
select that such a list shows nothing on the site (§12, D6).

**Dashboard and Translations.** Your drafts, Going live, Waiting for you,
Languages behind and the Translations matrix leave dormant posts out
(`Dashboard::Feed`, `Dashboard::WaitingForYou`, `Dashboard::TranslationNeeds`,
`Admin::TranslationsController#index`, through `Post.of_switched_on_types`)
(my call: a dormant post is nobody's next task). Recent activity keeps their
events: it is history.

**⌘K** finds a dormant post by its title, as it finds a trashed one in the
trash: finding is how it is reached (my call; no change).

**The Mind graph.** A dormant post stays a node under its type's hub, in its
type's hue (the type is declared). The dotted line from a page's Post list
block to the type's hub and to its posts follows the public truth
(`BlockTypes::PostList.matches?`), so it is not drawn for a switched-off type.
The hub's card and its row in the list say the type is switched off (§12, D7).
An undeclared type stays "retired", as today.

**Grants and the Groups screen.** Unchanged in behaviour (my call):
`AccessControl::Permissions.content_type_choices` stays the declared names, so
a grant scoped to a switched-off type is live, not dormant, and still decides
who may read, trash or purge its posts. The scope editor and the permission
row draw a switched-off type with a mark (§12, D8), so nobody reads it as
gone; the "no longer exists" wording stays for an undeclared type alone.

**MCP.** `create_post`'s `content_type` enum is the switched-on names (read at
call time, as now); `list_posts`' enum is the switched-on names and it lists
only their posts (my call: an assistant should not be handed posts it cannot
change); `get_post` reads any readable post and its answer gains
`"type_switched_on"`; `update_post` meets `Posts::Save`'s refusal.

**Media.** An image a dormant post uses stays in use: its usages list the post
and the database's foreign key keeps the image from being deleted, as today.

**Notes, the inbox, presence, live editing**: unchanged.

**The audit log** keeps every event of a dormant post.

## 7. Switching

### 7.1 Who and where

Settings › Post types (§11), a part of the one Settings form, saved by
`Settings::Save` with the save bar (owner's decision), behind `settings.manage`
(my call: it is the site's configuration, as Publishing and Forms are, and
`languages.manage` is the only right Settings splits off). The posted list is
`attributes: { content_types: [...] }`, a site part of the call.

### 7.2 One save, in order

Inside `Settings::Save`'s transaction, after the row is locked and saved:

1. The stored list is `posted ∩ declared` in registration order, then every
   stored name that is not declared (carried, §4.3). A posted name that is
   not declared is ignored (a forged one switches nothing on).
2. `changed = (before ∪ after) − (before ∩ after)`, over declared names.
3. When `changed` is not empty: `PublicSite::Paths.refresh(posts:
   Post.where(content_type: changed))` (the addresses go or come back),
   `SiteSearch::Indexing.content_types_changed` (a `ReindexJob` after the
   outermost commit, as `languages_changed` does), and one audit event per
   type (§7.3).
4. The row's commit moves the public content version and resets
   `Current.site` (existing `after_commit`).

`Paths.refresh` reads the switch through `Current.site`, so `Settings::Save`
derives from the row it locked and saved (`@site`, which the controller passes
as `Current.site`); when another object is passed, the service assigns
`Current.site = @site` for the refresh, and a test holds that the addresses
follow the saved list, not a copy loaded earlier in the request.

**A write beside a switch.** Every write that decides from a switch holds the
settings row `FOR SHARE` before the rows it writes (`ContentTypes.hold!`):
`Posts::Save` and `Publishing::PublishChanges` at the top of their transaction,
asking the switched-off refusal again under it; `Publishing::Version.take!`
before the record's row; `PublicSite::Paths.refresh` before any address or
due copy it marks (a refresh of nothing only when one is due); and
`SiteSearch::Indexing` before the built-in's entries. `Settings::Save` takes the
row `FOR UPDATE` first, so a publish in flight finishes before a switch-off's
refresh reads its post, and a publish that arrives during a switch-off waits for
its commit and is refused. The order is the settings row, then the record's row,
the addresses and the entries; a switch writes no page or post row, so a writer
that holds its record's row first waits with no cycle.
(`test/services/posts/switch_hold_test.rb`, statement order;
`test/services/settings/switch_race_test.rb`, both orders on two connections.)

### 7.3 The audit

One event per type switched (owner's decision that it is audited; my call on
its shape): `content_type.switched_on` and `content_type.switched_off`, subject
the site, `metadata: { "name" => "resume_entry", "label" => "Resume entry" }`
(the label kept so the sentence reads after a gem is gone), recorded in the
save's transaction. `Audit::Sentence` says "switched on the post type
**Resume entry**" and "switched off the post type **Resume entry**", in the
settings group beside `language.enabled`. The column is kept out of
`settings.updated`'s `field_changes` (`Settings::Save` drops `"content_types"`
from the changes it builds), so a switch is said once.

### 7.4 What comes back

Switching a type on again derives its posts' current addresses from their
slugs, which never changed (slugs are unique per type, `localized_slug scope:
:content_type`, so a dormant post's slug stays reserved within its type); old
slugs' redirects do not come back (§6). Its posts are listed and searchable
again, its published copies are what the public sees, and a post whose time
came while it was dormant is live. A switched-on post whose address another
post took meanwhile is the clash `PublicSite::Paths` already reports for a
post moved into a list; the save succeeds (`docs/reference/page-tree-and-routing.md`).

## 8. The personal-site pair (my call, the owner asked for a recommendation)

**Each type has its own switch, and the two are drawn together under one
heading, "For a personal site"**, with no "switch both on" control.

- "Switched on together or each on its own" is then two ticks or one, with
  no second control writing the same checkboxes (one writer per field, as
  the save bar's changed mark assumes).
- A site may want a Now page without a résumé, or the reverse; a single
  "personal site" switch would forbid that.
- The pair is a declaration, not a list in Settings: each type declares
  `t.group :personal_site` (§9.4), so a gem's types (an "Events" pair, say)
  group the same way, and the card knows no type by name.

The design agent may propose a convenience for the pair; it would be a design
decision, and this spec's rule (one writer per checkbox) still holds.

## 9. What a content type declares

### 9.1 The components and their theme methods

```ruby
ContentTypes.register :blog do |t|
  t.label "Blog"
  t.description :blog
  t.list_component Posts::BlogListComponent, theme_methods: %w[posts page]
  t.detail_component Posts::DetailComponent, theme_methods: %w[post]
  t.sample title: "Hello, world", excerpt: "The first post on this site.",
           body: "This is a sample blog post. Edit or delete it in the admin.",
           shows: [ "Hello, world" ]
  t.starter section: { title: "Blog", slug: "blog" }
end
```

`list_component` and `detail_component` take the component and its line of
the theme contract (`theme_methods:`, required: a component a theme may
replace says what its template may call). Read back with no argument as
today; `list_theme_methods` and `detail_theme_methods` answer the lines.
`ContentTypes.admit!` refuses a type that declares a component another type
already declared with other methods (the three built-ins share
`Posts::DetailComponent`), naming both types.

`Theme::Contract.post_components` replaces `POST_COMPONENTS`: every declared
type's two components with their methods, in registration order, merged into
`components` as the block types' are. The ledger (`test/support/contract_ledger.rb`)
keeps its four `posts/…` lines unchanged, and `contract_ledger_test.rb` now
holds the derived lines to them, so dropping a method or a component fails as
it does for a block. The contract does not depend on the switch.

### 9.2 The sample

`t.sample(title:, excerpt: nil, body: nil, fields: {}, shows:)`: a post's
values as `Posts::Save` takes them (`body` Markdown, `fields` the type's typed
fields), and `shows:`, texts its public detail page and its list hold. Refused
at registration, starting with the type's name: a missing or blank title, a
body that is not a String, a `fields` key the type does not declare, an empty
`shows:`, and (stricter than a block's, because a post's values are few and
plain) a `shows:` text that is not the title, the excerpt or one of the
`fields`' String values. `ContentTypeDefinition::Sample` is a `Data`.

### 9.3 The starter

`t.starter section:` keeps the section page the starter content makes and
takes its post from `t.sample` (minus `shows:`), so the seeded post and the
tests' post are one declaration (my call; the `sample:` keyword of
`starter` goes). No outside caller can hold the old form (there is no hook),
so this is no breaking change.

### 9.4 The description and the group

- `t.description :blog`: a Symbol naming a key under `admin.content_types.
  descriptions` (`config/locales/admin/content_types.en.yml`), read when the
  Settings card is drawn, never at registration (the locale files may not be
  loaded then; as `editor_note`). One sentence saying what the type is for:
  Blog "Articles and news, newest first."; Resume entry "One role on a
  résumé: company, role and dates."; Now update "A short note on what you are
  doing now; the site shows the latest." (copy for the design agent to
  confirm). Optional; a type with none draws no sentence.
- `t.group :personal_site`: a Symbol naming a key under
  `admin.content_types.groups` ("For a personal site"), so the card draws the
  type under that heading. Optional; ungrouped types come first.

### 9.5 What stays

`t.label`, `t.field`, `colour_index` and the `FieldTypes::BLOCK_ONLY`
refusals are unchanged. `t.description` and `t.group` keys of a built-in are
held by a test that draws the card (the test environment raises on a
missing key).

## 10. The shared samples and the canary

- `test/support/post_samples.rb` (`PostSamples`): `sample_post(type,
  published: true) -> Post`, built and published through `Posts::Save` from
  the type's sample, as an editor's save is; `sample_every_post_type ->
  Array<Post>` for every declared type (switched on for the test).
- `test/integration/post_samples_test.rb`: "every declared post type's sample
  is drawn on its detail page and in its list: each shows text on one of the two, and each page draws one of the sample's own values".
- `test/integration/public_canary_test.rb` builds its posts with
  `sample_every_post_type` in place of its hand-written ones, so a fourth type
  is in the canary the day it is declared.
- `db/seeds/showcase.rb` draws one Post list block per switched-on type, as
  now, reading `switched_on_names`.

## 11. Settings › Post types (behaviour; the look is §12)

- A ninth section of `SettingsSections`, `post_types`, `settings.manage`,
  after Languages and before Publishing (my call: what the site holds before
  how it publishes; D1 may move it); its name `admin.components.settings_screen.
  sections.post_types`, "Post types"; ⌘K's row "Settings › Post types"
  (`Jump::Search::SETTINGS_TITLES`).
- `Admin::SettingsScreen::PostTypesCardComponent`, in the card frame, one row
  per declared type (registration order; ungrouped, then each group under its
  heading): the type's dot (`Admin::Ui::ContentTypeDotComponent`), its label,
  its description, a checkbox `site_setting[content_types][]` with the type's
  name, and how many kept posts of the type the viewer may read ("12 posts",
  "1 post", none when 0), all counts in one grouped statement through the read
  scope (`AccessControl.scope(actor, "posts.read", Post.kept)`; not found, not
  forbidden: a count of posts the viewer cannot read would say they exist).
  A hidden `site_setting[content_types][]=""` precedes the checkboxes, so
  unticking every box posts an empty list and meets the "at least one" error
  rather than leaving the column alone.
- While a ticked type with posts is unticked and unsaved, its row says what the
  save will do: "Its 12 posts leave the site when you save. They are kept, and
  come back when you switch it on again." (§12, D2). It is server-drawn and
  shown by the checkbox's state; whether CSS or a controller shows it is the
  design's (a controller would be `admin--settings--post-types`,
  `app/javascript/controllers/admin/settings/post_types_controller.js`).
- The save bar names the field and marks it changed like any other
  (`Admin::SettingsScreen::Values#changed_fields`); a refused save is the 422
  re-render with the error on the card.
- The toast: "Settings saved", as for any save (my call: no toast of its own).
- "At a glance" draws no row for it (my call, as Forms and Sign-in draw none;
  D1 may ask for one, which would be the rail's fifth row and its own words).

## 12. Design requests

Every element below needs the design agent before it is built; the plan's
second part waits for its cards.

- **D1, the Settings section and card**: the section's chip (family and icon),
  its place in the nav, the card's intro, a type's row (dot, label,
  description, the switch's control, the post count), the "For a personal
  site" group heading, and whether "At a glance" has a row.
- **D2, the unsaved turn-off line** on a row: its words and tone (warn?), and
  whether it is a line, a note or a notice.
- **D3, the posts list**: the mark on a dormant post's row, and the type
  filter's switched-off entries.
- **D4, the editor's notice** for a dormant post: its words, tone and place
  beside "View only", and the link to Settings.
- **D5, a type's "switched off" word** wherever a type's name is drawn with it
  (the filter, the scope editor, the select, the hub): one word or chip for
  all of them.
- **D6, the Post list block's card**: the "(switched off)" option and the line
  under the select ("This list shows nothing on the site while Resume entry is
  switched off.").
- **D7, the Mind graph**: the switched-off mark on a type hub's card and on its
  row in the list.
- **D8, the Groups screen**: the mark on a switched-off type in the scope
  editor's box and on the permission row's chips.

## 13. Guards and tests

New guards:
- `test/lib/content_type_sets_test.rb`: every reader of the declared set is
  named, with its reason; a stale entry fails (§5).
- `test/integration/switched_off_types_test.rb`, the behavioural guard of §6,
  as `trash_visibility_test.rb` is of the trash: with Resume entry switched off
  and a published resume post with a tag, an image and a note, the post's
  address is a 404 in every language, it is in no sitemap, no Post list block
  (filtered or not) lists it, the search finds none of its words, the preview
  of its old address is a 404, MCP `list_posts` lists it not, the dashboard's
  lists and the Translations matrix leave it out; the posts list, the Trash
  (after a trash), the Mind graph and ⌘K find it; and after switching back on
  every one of those answers as before, the address the same.
- `test/models/public_site/paths_test.rb` and
  `test/models/site_search/postgres_parity_test.rb` gain `Settings::Save`'s
  switch as a write path (CLAUDE.md: a new write path that changes what
  addresses or documents are built from joins them).
- `test/services/posts/switched_off_refusal_test.rb`: each service in §6's
  list refuses a dormant post with the sentence, writing and auditing nothing,
  and the Trash services do not.
- `test/values/theme/contract_ledger_test.rb` holds the derived post lines;
  `test/values/theme/contract_test.rb`: "the theme contract is the same with
  every post type switched off".

Rules a change can break silently (for `docs/reference/content-blocks-and-types.md`
and, where there is no guard, `CLAUDE.md`):
- A new public or work list over posts narrows to the switched-on types
  (`Post.of_switched_on_types`) and joins `switched_off_types_test.rb`; no test
  fails for one that doesn't (a hand-listed case, beside the trash's).
- A new service that writes a post's content or publication calls
  `switched_off_refusal` and joins `switched_off_refusal_test.rb`; **no guard**
  for one that doesn't.
- Nothing at boot, in the theme check or in the contract reads the switch;
  the static guard holds `.all`/`.names` only, **no guard** for a
  `switched_on` call added to `to_prepare`.

## 14. Build order, release, changelog, the guide

**Order** (my call): the model, the switch and every reader first (§4 to §7,
§9, §10, with no screen: the fixture site has all three on, so nothing visible
changes), then the screens after the design cards (§11, §6's marks), then the
documents.

**CHANGELOG** (`## Unreleased`):
- *Added*: Settings › Post types; the audit events; MCP `get_post`'s
  `type_switched_on`.
- *Changed*: a new site starts with Blog alone; a post of a switched-off type
  is dormant (§6); MCP's `create_post` and `list_posts` offer the switched-on
  types; "content type" reads "post type" in CS Studio.
- *Migrations*: `20261116090000_add_content_types_to_site_settings`, "the
  column `site_settings.content_types`, the post types switched on; an existing
  site keeps all three on".
- *Removed*: `Theme::Contract::POST_COMPONENTS`, now
  `Theme::Contract.post_components`, derived; `ContentTypeDefinition#starter`'s
  `sample:` keyword, now `t.sample`.
- *For a gem or an outside caller*: `t.list_component`/`t.detail_component`
  take `theme_methods:`; `t.sample`, `t.description`, `t.group`;
  `ContentTypes.switched_on`, `.switched_on_names`, `.switched_on?`.
- No *Breaking*: no top-level name is added (`ContentTypes` exists), no hook
  changes, and no theme contract line changes.

**The guide** (`contentspiel-docs`, before the release): the Settings page
(Post types), the posts page (switched-off types, view only), the starter
content page (a new site starts with Blog), and for integrators the content
types page (the declarations, the switch, a gem's type is off until switched
on). **README**: "Posts of three built-in types, Blog and the optional Resume
entry and Now update, each switched on in Settings, with tags, …".
**Roadmap**: "Next", item 2's "decide whether resume entry and now update stay
defaults" is decided (this spec); the `content_types` hook stays under
"Block types from outside, step 2".

## 15. My calls, and what only the owner can answer

My calls, in one place: the words (§3); the column and an on-list (§4.1); no
wizard step (§4.2); development switches all on (§4.2); at least one on (§4.3);
carried undeclared names, no Remove (§4.3); the two sets and the static guard
(§5); dormant posts listed, view only, left out of the work surfaces, found by
⌘K and the Mind graph, grants unchanged, MCP's narrowing (§6); refusal before
rights, as a 422 (§6); `settings.manage` (§7.1); the audit's shape (§7.3); one
switch each, grouped, no "both" control (§8); theme methods per component, the
sample's strict `shows:`, the starter from the sample, description and group as
keys (§9); the hook, tokens and stylesheets later (§2); the card's place, the
count through the read scope, no toast and no glance row of its own (§11).

Only the owner can answer:
1. Is the `content_types` hook part of #114, or a later issue? This spec builds
   the declarations it would take and stops before it.
2. Should a site with pages only (no post type at all) be possible? This spec
   refuses it for now.
3. On upgrade, should an existing site whose Resume entry and Now update hold
   no posts get them switched off instead of on? The decision as given keeps
   every type on; this spec follows it.

## 16. The design's answers (Design System v241, `1794784635-1aa4`)

The design agent answered D1 to D8 in the card **StudioPostTypes** of the CMS
Design System (https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT, version
`1794784635-1aa4`), with pointers in StudioSettings, StateChip, RecordState,
StudioListTable, StudioFilterBar, StudioEditorHeader, StudioBlockCard,
StudioMindGraph and StudioGroups, all "Decided, not built (#114)". Where this
section and §11 or §12 differ on a word or a look, this section wins; on
behaviour, §1 to §11 do. The owner's answers to §15: the `content_types` hook
is **not** part of #114 (its own issue, named in the pull request as a
follow-up); a site keeps at least one type on; an existing site keeps every
type on at upgrade, even with no posts of a type.

### 16.1 D5, the one word: "Switched off"

- Where markup fits, the type's name (`Admin::Ui::ContentTypeDotComponent`, dot
  and label) and after it the off state chip,
  `Admin::Ui::StateChipComponent.new(tone: :off, label:)` reading **"Switched
  off"**: the posts list's Status cell, the editor header, the Mind graph's hub
  card and its list row. A type's state is the site's configuration, so it is
  the system's state chip, never a status chip and never warn. The word is one
  key for every caller, `admin.components.ui.type_state.switched_off`, read by
  one shared component, `Admin::Ui::TypeStateComponent` (renders the chip for a
  switched-off type, nothing otherwise; its card is StudioPostTypes).
- Where only text fits (a native `<option>`, a Badge's words): the suffix
  **"%{label} (switched off)"**: the posts filter's Type, the Post list block's
  select, the Groups scope chips and scope box.
- The dot keeps its hue. Words: "switched on" / "switched off" everywhere,
  never "disabled", "inactive", "hidden" or "dormant" (the code's word).
  "Retired type" and "this type no longer exists" stay for an undeclared type.

### 16.2 D1, Settings › Post types

- Section `post_types`, family `lists`, icon `posts`, after Languages and
  before Publishing, `settings.manage`; ⌘K "Settings › Post types"; no At a
  glance row; toast "Settings saved".
- `Admin::Ui::SettingsCardComponent`, heading "Post types", intro "The kinds of
  post this site has. Switching a type off takes its posts off the site and
  keeps them." No `head_end`.
- A row (`Admin::SettingsScreen::PostTypesCardComponent`): a grid
  `36px 1fr auto`, `gap-x-3`, `py-3`, divided by `cs-line`:
  1. the switch: the `.cs-toggle` look (ChoiceFields) on the checkbox
     `site_setting[content_types][]`, `role="switch"`;
  2. the type's dot and label (14px, weight 500; the `<label for>` of the
     switch), under it the description (`text-small cs-dim`, the switch's
     `aria-describedby`); no description, no line;
  3. the count, "12 posts" / "1 post", `text-small cs-meta`, right-aligned,
     nothing at 0.
- Group heading "For a personal site": a band on `cs-paper` across the card
  (`-mx-4 px-4 py-1.5`), `text-label cs-meta`, as the permission matrix's area
  bands. Ungrouped types first. No "switch both on" control.
- The refused save: "Keep at least one post type switched on." in
  `text-small cs-danger-ink` under the last row, and in the error summary.

### 16.3 D2, what an unsaved switch will do

- Turning off a type with posts: under its description,
  `NoticeComponent.new(tone: :warn, size: :compact, role: nil)`: "Its 6 posts
  leave the site when you save. They are kept, and come back when you switch it
  on again." (one: "Its 1 post leaves the site when you save. It is kept, and
  comes back when you switch it on again.").
- Turning on a type with posts: the neutral compact notice "Its 6 posts come
  back to the site when you save." (one: "Its 1 post comes back to the site when
  you save.").
- Both server-drawn, `hidden` at rest, shown by CSS with no script: the row
  carries `data-stored="on|off"`, and the rules are
  `[data-stored="on"]:has(.cs-toggle:not(:checked)) .…__leaving` and
  `[data-stored="off"]:has(.cs-toggle:checked) .…__returning`, `!important`
  inside `@layer base` (Tailwind's preflight hides `[hidden]` with an
  `!important` there, which beats one outside the layer). A type with 0 posts
  draws neither. The server does NOT name the lines in the switch's
  `aria-describedby`: an element named there is announced even while it is
  hidden.
- **The design's "no controller" gave way for the accessible description.** A
  screen reader must hear the line the eye sees, and only while it shows, which
  CSS cannot say. One small controller, `admin--settings--post-types`
  (`app/javascript/controllers/admin/settings/post_types_controller.js`), keeps
  each switch's `aria-describedby` at its description plus the row's line while
  the stylesheet draws it, reading the line's state from the stylesheet rather
  than deciding it again, and puts the server's value back at disconnect and at
  `turbo:before-cache`. The look stays the CSS's and works without the script
  (`test/system/admin/settings_post_types_test.rb` reads the description from
  the browser's accessibility tree before and after a switch is moved).

### 16.4 D3, the posts list

- Status cell: `Admin::Ui::ListStateComponent` draws the type's off chip first,
  then the record's own chips (Draft, Scheduled, Unpublished changes); a live
  dormant post shows "Switched off" alone. The mark joins `ListStateComponent`,
  never the list's template.
- The path line under the title reads "Not on the site" (`cs-meta`).
- The Type cell is unchanged.
- The filter's Type: "All", the switched-on types, then each switched-off type
  with posts the viewer may read, as "Resume entry (switched off)"
  (`admin.components.posts_screen.toolbar.switched_off`). No optgroup.

### 16.5 D4, the editor

- Header row 2: "View only" (the dashed badge), the type's dot and name, then
  the off chip.
- Above the form, in the place of the view-only hint and replacing it for this
  cause, `NoticeComponent.new(tone: :neutral)` (role `note`):
  - holder of `settings.manage`: "Resume entry is switched off. Its posts are
    kept, and are not on the site. Switch it on to change this post. **Open
    Post types settings →**", linking to Settings' `#post_types`;
  - anyone else: the first two sentences, then "Someone who manages Settings
    can switch it on."
  - keys `admin.components.editor_screen.switched_off.{body,change,ask,open_settings}`
    ("%{type} is switched off. Its posts are kept, and are not on the site.",
    "Switch it on to change this post.", "Someone who manages Settings can
    switch it on.", "Open Post types settings →").
- Trash stays in the ⋯ menu; Notes stay open; no publishing action.

### 16.6 D6, the Post list block's card

- The select offers the switched-on types; a stored switched-off or undeclared
  value is the selected option "Resume entry (switched off)".
- Under it (8px), `NoticeComponent.new(tone: :warn, size: :compact, role:
  nil)`: "This list shows nothing on the site while %{type} is switched off."
  (`admin.components.fields.content_type.list_empty`), plus " **Open Post types
  settings →**" for a holder of `settings.manage`; in the select's
  `aria-describedby`. No line for a switched-on value.

### 16.7 D7, the Mind graph

- Hub card: under the title, the off chip, then a `text-small cs-dim` line:
  one "Its 1 post is kept and is not on the site, so no list links to it." /
  other "Its %{count} posts are kept and are not on the site, so no list links
  to them." / zero "It has no posts."
- List row (Post types group): the off chip at the row's end, replacing the
  count.
- The chip is a clone from `PartsComponent`'s template (`mind_graph/parts.js`),
  as the status chips are, added to the parts and to the parts' markup test.
- The canvas is unchanged: no legend entry; the missing dotted lines say it.

### 16.8 D8, the Groups screen

- Permission row chips and the scope editor's box: the neutral
  `BadgeComponent`, the type's dot as its mark, "Resume entry (switched off)"
  (`admin.components.groups_screen.matrix.switched_off_type`, "%{name}
  (switched off)"). Neutral: the grant is live. Warn and "%{name} · this type no
  longer exists" stay for an undeclared type.

### 16.9 Words and keys

The card's keys are written where this codebase's scoping puts them (a
component's key is `admin.components.<its folder>.<its name>.<leaf>`), with the
card's leaf names and English verbatim: the Settings card's `intro`, `count`
(one/other), `leaving` and `returning` (one/other) under
`admin.components.settings_screen.post_types_card`; the section name
`admin.components.settings_screen.sections.post_types`;
`admin.content_types.groups.personal_site` "For a personal site"; the three
descriptions of §9.4, confirmed as written.

### 16.10 The Design System's copy

`test/support/design_system_entries.rb` gains `StudioPostTypes` in `ENTRIES`,
`Admin::Ui::TypeStateComponent => "StudioPostTypes"` in `COVERED_BY`, and
`VERSION` `1794784635-1aa4`. Cards other branches add (Gif, ImageViewer) are
theirs; a merge with main brings them.
