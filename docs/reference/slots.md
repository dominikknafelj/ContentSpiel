# Screen slots: the pattern, and how it works here

> Describes: `app/components/admin/slots.rb`, `app/components/admin/ui/slot_component.rb`, `app/components/admin/ui/rail_slot_component.rb`, `config/initializers/admin_slots.rb`.

This file explains the pattern for someone who has not met it. The exact contract (every slot's name and place, the arguments, the guards) is in `docs/reference/presence.md`, "`Admin::Slots`: named places on a screen"; where the two differ, that section and the code are right.

## The problem it answers

Notes was the first feature that attaches to content instead of being content. To show a Notes button in the editors' header, a pill in the page tree and a section in the media panel, each of those components was edited to render a notes component by name. Presence wanted the same places, and edit reservations and the publishing workflow will want them too. Every such feature would have cut into the same core templates, and each of those templates would have grown a list of the features it knows.

## The idea

A screen marks a place and gives it a name. A feature signs up for the name somewhere else. The screen draws "whatever signed up for this name" and never learns what that is.

Three things carry it:

1. **A registry**: a hash from a slot's name to an ordered list of entries.
2. **A registration**: one line per feature and place, in an initializer.
3. **A slot component**: what a screen renders at the place; it looks the name up and renders each entry.

Elsewhere the same idea is called an extension point, a plugin outlet (Discourse), a view hook (Redmine) or SlotFill (the WordPress block editor). **It is not ViewComponent's own "slots"** (`renders_one`, `renders_many`): there the caller of a component hands content into it, here a third party registers content for a place.

## The four parts in this app

### 1. The registry

`Admin::Slots` (`app/components/admin/slots.rb`) is a module that holds one hash. The keys are the names in `Admin::Slots::NAMES`, each value a list:

```ruby
Admin::Slots.register "editor.header.people", Admin::PresenceScreen::PeopleComponent, size: :header
```

`register` appends an entry (the component class, an optional loader, the options) to the name's list. A name that is not in `NAMES` raises, so a misspelt name fails at boot instead of drawing nothing.

### 2. The registrations

`config/initializers/admin_slots.rb` is the one file that says what stands where, in the order it is drawn. To learn what is in the editors' header, read this file, not the header's template: that is the price of the pattern.

It runs inside `Rails.application.config.to_prepare`, which Rails calls at boot and again after each code reload in development. A reload replaces the component classes, so the registry is emptied first (`Admin::Slots.reset!`) and filled again; nothing is registered twice and no old class is kept. The content and block types are registered the same way (`config/initializers/types.rb`).

### 3. The place on the screen

A host component renders the slot component where the feature's part should stand:

```erb
<%= render Admin::Ui::SlotComponent.new(name: "editor.header.people", record: record, viewer: viewer, **slot_context) %>
```

`Admin::Ui::SlotComponent` asks the registry for the name's entries and renders each in order. With nothing registered it renders nothing, not even a wrapper element.

### 4. The contract of a registered component

Every registered component is built the same way, and that sameness is the whole interface:

```ruby
entry.component.new(record:, viewer:, data:, **context, **entry.options)
```

- `record`: the page, post or image the screen is about; in a list, the row's record.
- `viewer`: the user looking. It is passed in; a slot component does not read `Current`.
- `data`: what the entry's loader answered for this record (see below), nil where there is no loader.
- `context`: what the host hands through (`locale:`, `url_options:`, and anything the screen has already read that a feature would otherwise read again).
- `options`: what the registration said (`size: :header`, `joined: true`), so one component can serve two places.

A component must end its parameters with `**`, because a host may hand through more than one feature needs:

```ruby
def initialize(record:, viewer:, data: nil, joined: false, **)
```

Its own `render?` decides whether it draws anything.

**An entry may draw a shared part.** A slot entry is the feature's: its name, its loader and its words stay in the feature's folder and locale file, so a core screen draws the slot and never names the feature. What two screens draw alike is not the feature's: when the drawing is used by more than one screen it lives in `app/components/admin/ui/` with the full `Admin::Ui::Contract` and knows no feature, and the entry renders it, handing over what its loader read and its own words. Notes' and presence's row markers are the two examples: `NotesScreen::RowPillComponent` and `PresenceScreen::RowMarkerComponent` load the counts and the roster and word them, and `Admin::Ui::NoteMarkerComponent` and `Admin::Ui::PresenceMarkerComponent` draw the bubble and the stack (`docs/reference/design-system.md`, "Component contract"). The shared part is told the count, the people's letters, the label and the room it has, and is never told a record, a viewer or a feature's key.

## What exists

The names are `Admin::Slots::NAMES`, and `presence.md` has the table of where each is drawn and what stands in it: `editor.header.people` and `editor.header.actions`, `media.panel.header` and `media.panel.sections`, `tree.row.markers`, `posts.row.markers` and `posts.row.title`, and `editor.block.markers`, drawn by a block's card and by a section's tile: the holder's avatar (on a tile only) and the notes marker, in that order. `editor.rail.tabs` (the editors' rail) and `media.rail.tabs` (the Media screen's rail) are the two PANEL slots (below).

## Lists: the loader

A tree of 200 pages that asked "who is on this page?" once per row would run 200 queries. So an entry for a list slot carries a **loader**, a lambda that is called once with all the rows:

```ruby
Admin::Slots.register "tree.row.markers", Admin::PresenceScreen::RowMarkerComponent,
  loader: Admin::PresenceScreen::RowMarkerComponent.loader("page")
```

The list's component calls `Admin::Slots.load("tree.row.markers", pages, viewer: viewer)` once per render. Each loader answers a hash from record id to that record's data, and each row's slot hands its record's piece to the component as `data:`. A list costs the same number of queries for 3 rows as for 30, and two tests say so (named in `presence.md`).

**`reads:`, one Hash per screen.** The editors hand every slot of the screen the same `reads: {}`, so two parts of one feature on one screen (the header's Notes button and the rail's Notes tab) read what both draw once: the first to ask reads and keeps it, the second finds it. A key is namespaced by its feature, `[feature, …]` (`[:notes_counts, "Page-3"]`, `Admin::NotesScreen::CountsComponent.read`), and a value is the read's result, never a component. A host that hands no `reads:` (a save's stream) gets nothing kept, and an entry then draws no figure it did not read.

**A slot for one record has no loader, and takes what the host has already read as context.** The one such slot that would otherwise cost a statement is the slot on a block, `editor.block.markers`: the editors have read the page's edit reservations once for the whole screen (`Editing::Holds`), and the card and the tile hand them to the slot as `holds:`, like any other context. The holder's avatar asks those holds and nothing else: it has no loader, reads no `Current`, and draws nothing for a host that hands none; the notes marker ignores them. `Admin::Slots.load` takes `name, records, viewer:` and nothing more. (`test/components/admin/editor_screen/holder_avatar_component_test.rb`: "a host that hands no holds draws no avatar, reads nothing and asks no Current", "drawing from the page's holds costs no statement, for one block as for thirty"; `test/integration/admin/editing_test.rb`: "the page editor costs the same statements for 3 blocks as for 30 with both features on every block, and the avatar's slot costs none".)

## One render, followed through

1. Someone opens a page's editor. The header's template reaches the slot `editor.header.people`.
2. The slot component asks the registry and gets one entry: the people component, with `size: :header`.
3. It renders `PeopleComponent.new(record: page, viewer: user, data: nil, locale: …, size: :header)`.
4. The people component draws its frame; from there on it is presence's own (`presence.md`).

The header's template holds no line that says "presence".

## A panel slot: the rail's tabs

A panel slot is not drawn by `SlotComponent`: each entry is a tab and its panel, and the two stand in different places of a rail, so its host draws it through `Admin::Ui::RailSlotComponent`, telling it which slot (`slot:`). There are two hosts, each with its own slot, so what is registered for one rail never stands in the other: the editors draw `editor.rail.tabs` in their rail (`#editor-grid`), where notes register the Notes tab (`Admin::NotesScreen::RailPanelComponent`), and the Media screen draws `media.rail.tabs` in the chosen image's rail (`#media-rail`, after its own Image tab), where notes register the image's Notes tab (`Admin::NotesScreen::MediaSectionComponent`). Both hosts follow the steps below; where they differ it is said.

1. **The entry answers four more things.** Built like every slot component (`record:, viewer:, data: nil, **context`), it answers `tab_key` (a String, lowercase letters only; anything else raises, as does a key another entry or the host's own tabs already have: `reserved:`), `tab_label`, `tab_count` (an Integer, or nil for no figure) and `render?`, and may answer two more: `tab_count_data` (data attributes for the tab's number, so a script of the feature's can fill it: the Notes tab's is an `admin--notes--drawer` `total`) and `tab_current?` (true when the request's own address opens it: the Notes tab's for `?notes=open`). Drawn, it is the panel's content.
2. **The host makes one `RailSlotComponent` and uses it twice.** `#tabs` goes to `RailTabsComponent` as `slot_tabs:`, which puts them after the rail's own tabs; `render rail_slot` draws each panel in a `RailPanelComponent` after the host's own panels. The entries are built once, so a tab and its panel come from one object. The page editor's rail is Page, Section, then the slot's; the post editor's is Post, then the slot's; the Media rail's is Image, then the slot's, under a tablist the host names "Image details" (`RailTabsComponent`'s `label:`; the editors' is "Settings"), with the rail's Close after every panel. The first entry that answers `tab_current?` true (`RailSlotComponent#current_key`) is drawn current, tab and panel, and the host draws its own tab current only when none does, so the first paint shows what the address asked for.
3. **One tab is a heading, two are a tablist.** A rail with only its own tab is an `h2`. When an entry renders, the rail is a real tablist with the entry's tab in it; the host does not decide. With notes registered, the post editor's rail is a tablist of two (Post, Notes) wherever the viewer may read the post's notes. On a post the tablist and the slot's panels follow the form in the document, because inside it they would be frozen by `editing/freeze.js` and drawn again by every record merge; the grid puts the tabs in the rail's first row.
4. **Both hosts hand the slot `query:`**, the request's query parameters, with `locale:`, `url_options:` and the screen's `reads:` (above), so a panel reads its own parameters (`?notes=open`, and on the Media screen a `thread`) and shares what the screen's other slots have read without the host naming either; the Media screen hands no `reads:`.
5. **A save's answer draws the tab's contents again and never the panel.** The stream's context is smaller than the page's: no `query:` and no `reads:`, so a tab's label must be answerable from `record` and `viewer` alone, and a count it would have to read is drawn hidden for the feature's script to fill (the Notes tab answers 0 with its number hidden, and `admin--notes--drawer` fills it from the counts the page holds); and a tab not drawn at page load is not added by a stream, it appears at the next load. `Admin::Answers::RailTabStreams.for(record, view:, viewer:, slot:, rail_id: "editor-grid", **context)` (the editors pass `slot: "editor.rail.tabs"`) returns one `turbo_stream.update("<rail_id>-tab-<key>", …)` per entry that renders, the tab's label and number (`RailTabComponent` with `contents: true`): the `<button>` stays, so a tab with the keyboard's focus keeps it as the answer lands (`test/system/admin/notes_rail_test.rb`, "a save draws the Notes tab's contents again, its number stays, and a focused tab keeps the focus"), appended by `PagesController#update` and `PostsController#update` on a successful save. A panel may hold typed text, and which tab is current is not touched.

The rail's components, the answer, the post form, the two editor views (`admin/pages/show`, `admin/posts/show`) and the Media view (`admin/media/index`) do not name the feature: `test/lib/notes_boundary_test.rb`. Tests: `test/components/admin/ui/rail_slot_component_test.rb` ("it draws the tabs registered at the slot it is told, and none of another slot's"), `test/controllers/admin/answers/rail_tab_streams_test.rb`, in `test/components/admin/editor_screen/post_form_component_test.rb` "a registered rail tab makes the post rail a tablist of two, with its panel after the form" and "with nothing registered the post rail is a heading", and the Notes tab's own in `docs/reference/notes.md`, "The Notes tab and the markers".

## Doing it yourself

**A new feature in an existing place.** Write a component that takes `record:`, `viewer:`, `data:` and `**`. Add one `register` line to the initializer, in the position it should be drawn in. For a list slot, give it a loader. No host component changes.

**A new place.** Add the name to `Admin::Slots::NAMES`, render `Admin::Ui::SlotComponent` with that name in the host, and for a list call `Admin::Slots.load` once in the list's component. If the host should stay free of the features' names, add it to `SLOT_HOSTS` in `test/lib/notes_boundary_test.rb`.

**In a test.** `Admin::Slots.with("name" => [ … ]) { … }` replaces the registry for the block and puts it back afterwards (`test/components/admin/slots_test.rb`).

## Benefits

- **A new feature costs one line, not an edit per screen.** Notes edited about ten core components to make room for itself; the next feature that wants one of the eight places edits none of them.
- **Core templates stay about the core.** The editors' header knows pages and posts. It does not grow a list of the features that exist, and a feature can be changed or removed without opening it.
- **The boundary can be tested.** Because a host has no reason to name a feature, a test can refuse it when it does (`test/lib/notes_boundary_test.rb`). Without slots that rule could only be a wish.
- **One place answers "what is on this screen from features?"**: the initializer, in drawing order.
- **Lists stay cheap by construction.** The loader makes "one query for all rows" the only way to give a row its data, where a hand-written row component makes the query-per-row mistake easy.
- **One component, several places.** The options let the people component serve the header and the media panel at two sizes.
- **It is the seam a plugin interface would stand on**, already used by two features from inside the app, so it is not a guess about what outside code would need.

## Tradeoffs

- **A template does not show everything it renders.** To see what is in the header you read the initializer as well. This is the main cost, and it is paid by every reader, every time.
- **One more concept to learn.** Someone who knows Rails does not know this registry; plain `render` needs no explanation.
- **The contract is loose.** Arguments travel as keywords and a component swallows the ones it does not know (`**`), so a misspelt context key is not an error: the component just does not get it. A direct `render` with a wrong keyword raises.
- **Order is by position in a file.** What is drawn first is whichever line comes first in the initializer; nothing else states or checks the order.
- **A slot fits one shape of place.** It hands over a record and a viewer. A place that needs more (a column with its header, a menu item with its own action) needs a second mechanism or stays a direct render; the posts table's Notes column header is such a case and is still named in the table.
- **Finding a usage takes a different search.** "Where is this component rendered?" is answered by the initializer, not by a `render` call in a template, which is where an editor's search would look first.
- **It is code to maintain**: the registry, the slot component, the reload handling and their tests, for what direct renders do with none.
- **It pays only if features keep coming.** With two features it is roughly even; the third and fourth are what make it worth having. If no more arrive, direct renders would have been simpler.

## When not to use it

A slot costs a reader one step of looking up, so a place becomes a slot when a **second** feature wants it, not before. A component that one screen renders for itself is rendered by name, as everywhere else in Rails. The places where notes is still named directly are listed with the event that would turn each into a slot, in `test/lib/notes_boundary_test.rb`.

## What a slot does not do

- It checks no permission. A registered component, and the endpoint it fetches from, ask the read scope themselves.
- It carries no script and no style. A component brings its own Stimulus controller and uses CS Studio's tokens like any other.
- It is not a plugin system. The same registry is what one would later be built on (`docs/roadmap.md`, "Plugin API v1"), but nothing here loads code from outside the app, and the contract is not versioned.

## Does it go against Rails?

No. The registry is filled in `to_prepare`, the documented place for anything that must survive a reload; the components are ordinary ViewComponents in the folders Zeitwerk expects; nothing of Rails is patched. What it leaves behind is a habit, not a rule: that a template shows everything it renders. Rails has no built-in for named places and none against them; applications that features plug into (Discourse, Redmine, Solidus) each add one.

## Rules a change can break silently

Moved word for word from `CLAUDE.md`, where "above" and "below" meant the list these rules stood in: a rule named that way may now be in another reference file. Each names the test that guards it; a rule or a part of one with no guard is also said in `CLAUDE.md`.

- A slot-hosting component does not name the features in its slots: the editors' header, the media panel, the page tree's rows, the posts table and (for a block's markers, `editor.block.markers`) the block card and a section's tile draw `Admin::Ui::SlotComponent` at a name from `Admin::Slots::NAMES`, a feature registers in `config/initializers/admin_slots.rb` (the one file that names them all, inside `to_prepare` after `reset!`), a list slot's loader runs once for all the rows of the list and a row only reads its entry, a slot for one record has no loader and takes what its host has already read as context (`holds:` on a block: a host that hands none draws no avatar), and every slot component accepts `**` for the context of the host it does not use (`test/lib/notes_boundary_test.rb`: "the editors' header, the media panel, the rail and the two editor views do not name notes: they draw their slots", "every place that still names notes directly is a named exception with its trigger, and still names them", "the block card and the tile draw no marker themselves: they draw the slot" (both still name notes for the "Add note" item of their menus, a named exception); `test/components/admin/slots_test.rb`: "load calls each loader once with every record and the viewer, and skips entries without one", "the real registry holds notes' components, and presence's people in the header at its size and in the panel at its"; the 3-against-30 statement tests in `test/components/admin/pages_screen/tree_component_test.rb` and `test/components/admin/posts_screen/table_component_test.rb`; `test/components/admin/presence_screen/people_component_test.rb`: "it takes what the hosts hand every slot component and ignores it, and an actor that is no user is shown nothing"; `test/components/admin/editor_screen/holder_avatar_component_test.rb`: "a host that hands no holds draws no avatar, reads nothing and asks no Current"). A place that is not a slot yet stays a direct call and is a named exception in the boundary test with the trigger that would make it one.
