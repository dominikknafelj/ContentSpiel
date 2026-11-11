require "test_helper"
require_relative "../support/source_code"

# A component in a screen's folder (`app/components/admin/<screen>/`) is drawn
# by that screen alone (CLAUDE.md, "Where a component goes";
# docs/reference/design-system.md, "Component contract"). A component a second
# screen draws, or the layout, a shared component or a registry, is shared, and
# a shared component lives in `app/components/admin/ui/` with the full
# `Admin::Ui::Contract`: its states with previews, its keys, a Design System
# entry and a keyboard test. Left in a screen's folder it has none of them, and
# the second screen changes with every change the first one asks for.
#
# A user of a component is a file under `app/` whose code, comments stripped,
# names its constant: `Const.new`, `render Const`, `Const::SOMETHING`,
# `< Const`. The name is matched qualified from the screen's module on
# (`EditorScreen::BlockCardComponent`, with or without `Admin::` or `::Admin::`
# before it), the way every file under `module Admin` may write it. The bare
# name (`BlockCardComponent`) reaches the constant only lexically inside
# `module Admin::EditorScreen`, which is the screen's own folder and so its own
# user; elsewhere a bare name is another constant (`PanelComponent` inside
# `Admin::Ui` is `Admin::Ui::PanelComponent`), so it is not searched.
#
# What the guard cannot see: a constant reached through a string
# (`constantize`, `const_get`), and a component registered outside `app/`
# (`config/initializers/admin_slots.rb`: a slot entry stays in its feature's
# folder by design, `docs/reference/slots.md`).
#
# Which screens a file draws for is read from where it lives: its own
# screen's folder; the map (SCREENS for CS Studio's views, controllers and
# controller concerns, SEVERAL_SCREENS for one of those that draws more than one
# screen, SCREEN_FILES for any other file that is one screen's); or else
# shared, as SHARED and anything else under `app/` (the setup wizard, a job, a
# mailer) are.
class ComponentScreensTest < ActiveSupport::TestCase
  ROOT = Rails.root
  COMPONENTS = "app/components/admin"

  # The folders under COMPONENTS that are not a screen's.
  REGISTRIES = %w[ui columns fields shell].freeze

  # Files whose users are "shared": the shared components and registries, the
  # slot registry and the base class, the layouts, the admin's shared partials,
  # the helpers and the base controllers.
  SHARED = %w[
    app/components/admin/ui/
    app/components/admin/columns/
    app/components/admin/fields/
    app/components/admin/shell/
    app/components/admin/slots.rb
    app/components/admin/admin_component.rb
    app/views/layouts/
    app/views/admin/shared/
    app/helpers/
    app/controllers/admin/base_controller.rb
    app/controllers/application_controller.rb
  ].freeze

  # CS Studio's views, controllers and controller concerns: every file under
  # these is in SHARED or mapped by SCREENS or SEVERAL_SCREENS, and SCREENS
  # names nothing else.
  CALLERS = %w[app/views/admin app/controllers/admin app/controllers/concerns/admin].freeze

  # Each CS Studio view folder or file, controller and controller concern, by
  # the screen it draws. The most specific entry wins, so a view file may name
  # another screen than its folder. `:shared` is a file that more than one
  # screen uses, or a screen with no component folder of its own (System
  # status, sign-in, ⌘K, the error pages): either way it may draw shared
  # components only.
  SCREENS = {
    "account_screen" => %w[
      app/views/admin/accounts
      app/controllers/admin/accounts_controller.rb
      app/controllers/admin/account_sessions_controller.rb
    ],
    "audit_screen" => %w[
      app/views/admin/audit_events
      app/controllers/admin/audit_events_controller.rb
    ],
    "dashboard_screen" => %w[
      app/views/admin/dashboard
      app/views/admin/note_inbox/_card.html.erb
      app/controllers/admin/dashboard_controller.rb
      app/controllers/admin/note_inbox_controller.rb
    ], # note_inbox/_card is the Dashboard's Notes for you panel, which NoteInboxController redraws; the controller's index is the Notes inbox, whose view is notes_screen's
    "editor_screen" => %w[
      app/views/admin/pages
      app/views/admin/posts
      app/controllers/admin/posts_controller.rb
      app/controllers/admin/content_blocks_controller.rb
      app/controllers/admin/editing_controller.rb
      app/controllers/admin/publishing_controller.rb
      app/controllers/admin/link_targets_controller.rb
      app/controllers/admin/translation_confirmations_controller.rb
      app/controllers/admin/answers.rb
      app/controllers/admin/answers/answer.rb
      app/controllers/admin/answers/block_drawing.rb
      app/controllers/admin/answers/block_gone.rb
      app/controllers/admin/answers/block_refused.rb
      app/controllers/admin/answers/block_saved.rb
      app/controllers/admin/answers/context.rb
      app/controllers/admin/answers/held.rb
      app/controllers/admin/answers/publishing_streams.rb
      app/controllers/admin/answers/stale.rb
      app/controllers/concerns/admin/editing_claims.rb
      app/controllers/concerns/admin/media_fields.rb
      app/controllers/concerns/admin/publishing_state.rb
      app/controllers/concerns/admin/scheduling.rb
    ], # link_targets: the rich-text link dialog's search; translation_confirmations: the translation pair's reference card
    "forms_screen" => %w[
      app/views/admin/forms
      app/views/admin/form_submissions
      app/controllers/admin/forms_controller.rb
      app/controllers/admin/form_submissions_controller.rb
      app/controllers/admin/form_deliveries_controller.rb
    ],
    "groups_screen" => %w[
      app/views/admin/groups
      app/controllers/admin/groups_controller.rb
    ],
    "media_library" => %w[
      app/views/admin/media
      app/controllers/admin/media_controller.rb
      app/controllers/admin/media_originals_controller.rb
      app/controllers/concerns/admin/media_upload_responses.rb
    ], # media_upload_responses: an upload, the library's or the picker's, is answered with the library's tile
    "mind_graph_screen" => %w[
      app/views/admin/mind_graph
      app/controllers/admin/mind_graph_controller.rb
    ],
    "notes_screen" => %w[
      app/views/admin/notes
      app/views/admin/note_inbox/index.html.erb
      app/controllers/admin/notes_controller.rb
      app/controllers/admin/note_threads_controller.rb
      app/controllers/admin/note_messages_controller.rb
      app/controllers/admin/note_reactions_controller.rb
      app/controllers/admin/note_mentions_controller.rb
      app/controllers/admin/note_files_controller.rb
      app/controllers/concerns/admin/note_container.rb
    ],
    "pages_screen" => %w[
      app/views/admin/pages/_tree.html.erb
      app/views/admin/tree
      app/controllers/admin/tree_controller.rb
      app/controllers/admin/starter_contents_controller.rb
    ], # the page tree column; starter_contents: the tree's "⋯" menu
    "posts_screen" => %w[
      app/views/admin/posts/index.html.erb
    ],
    "presence_screen" => %w[
      app/controllers/admin/presence_controller.rb
    ],
    "settings_screen" => %w[
      app/views/admin/settings
      app/controllers/admin/settings_controller.rb
      app/controllers/admin/ai_keys_controller.rb
      app/controllers/admin/mail_logins_controller.rb
      app/controllers/admin/languages_controller.rb
      app/controllers/concerns/admin/carried_base.rb
      app/controllers/concerns/admin/glance_rows.rb
    ],
    "tags_screen" => %w[
      app/views/admin/tags
      app/controllers/admin/tags_controller.rb
    ],
    "tokens_screen" => %w[
      app/views/admin/api_tokens
      app/controllers/admin/api_tokens_controller.rb
    ],
    "translation_screen" => %w[
      app/views/admin/translations
      app/controllers/admin/translations_controller.rb
    ],
    "trash_screen" => %w[
      app/views/admin/trash
      app/controllers/admin/trash_controller.rb
    ],
    "users_screen" => %w[
      app/views/admin/users
      app/controllers/admin/users_controller.rb
      app/controllers/admin/invites_controller.rb
      app/controllers/concerns/admin/users_list.rb
    ],
    shared: %w[
      app/views/admin/errors
      app/views/admin/jump
      app/views/admin/passwords
      app/views/admin/sessions
      app/views/admin/system_status
      app/controllers/admin/jump_controller.rb
      app/controllers/admin/passwords_controller.rb
      app/controllers/admin/sessions_controller.rb
      app/controllers/admin/system_status_controller.rb
      app/controllers/admin/media_assets_controller.rb
      app/controllers/admin/tag_suggestions_controller.rb
      app/controllers/admin/user_suggestions_controller.rb
      app/controllers/admin/answers/rail_tab_streams.rb
      app/controllers/admin/answers/slot_streams.rb
      app/controllers/concerns/admin/autosave_responses.rb
      app/controllers/concerns/admin/bulk_responses.rb
      app/controllers/concerns/admin/field_params.rb
      app/controllers/concerns/admin/file_params.rb
      app/controllers/concerns/admin/mail_link_origin.rb
      app/controllers/concerns/admin/record_of_kind.rb
      app/controllers/concerns/admin/refusal_status.rb
      app/controllers/concerns/admin/sign_in_completion.rb
      app/controllers/concerns/admin/stale_form.rb
      app/controllers/concerns/admin/toast_stream.rb
      app/controllers/concerns/admin/translatable_record_loading.rb
    ] # media_assets: the picker's upload; rail_tab_streams and slot_streams: the slots' streams, whatever screen hosts them
  }.freeze

  # A file that draws more than one screen, each by name, with the reason. It is
  # one of CALLERS' files, here and never under two keys of SCREENS, where a
  # file listed twice is a mistake the map refuses.
  SEVERAL_SCREENS = {
    "app/controllers/admin/pages_controller.rb" => [
      %w[editor_screen pages_screen],
      "the Pages screen's controller: the editor in the content frame, and the tree row it redraws when a page's title or state changes"
    ]
  }.freeze

  # A file outside CALLERS that is one screen's, with the reason: one existing
  # file, never a folder, and never a file in a screen's folder, which is that
  # screen's already. A shared folder's file belongs here only when what it
  # draws is that screen's own.
  SCREEN_FILES = {
    "app/components/admin/ui/media_picker_component.html.erb" => [
      "media_library",
      "the picker draws the Media screen's own listing (/media?picker=1), so it names the library tile's class and words"
    ]
  }.freeze

  # The (class, file) pairs that name a screen class, its own screen's included:
  # The guard's floor ("the guard is looking at the code").
  USERS_FLOOR = 150

  MAP = { screens: SCREENS, several: SEVERAL_SCREENS, files: SCREEN_FILES }.freeze

  FIX = "Move it to app/components/admin/ui/ and give it Admin::Ui::Contract (docs/reference/design-system.md, 'Component contract'). " \
        "Or, if the file belongs to that screen, map it in SCREENS (SEVERAL_SCREENS for a file that draws more than one screen)."

  def self.code_of(path, source = File.read(path)) = SourceCode.code_of(path, source)

  def self.relative(path) = Pathname(path).relative_path_from(ROOT).to_s

  # Every file under `app/` that may name a component, with its code.
  def self.sources
    @sources ||= Dir[ROOT.join("app/**/*.{rb,erb}")].sort.to_h { |path| [ relative(path), code_of(path) ] }.freeze
  end

  def self.screen_folders
    Dir[ROOT.join(COMPONENTS, "*/")].map { |path| File.basename(path) } - REGISTRIES
  end

  # Every class a screen folder defines, by its constant path, with its screen.
  def self.screen_classes
    screen_folders.flat_map do |screen|
      Dir[ROOT.join(COMPONENTS, screen, "**/*.rb")].map { |path| [ Rails.autoloaders.main.cpath_expected_at(path), screen ] }
    end.sort
  end

  # `Admin::EditorScreen::BlockCardComponent` as it may be written from inside
  # `module Admin`, or from anywhere in full.
  def self.pattern_for(cpath)
    /(?<![\w:])(?:::)?(?:Admin::)?#{Regexp.escape(cpath.delete_prefix("Admin::"))}(?!\w)/
  end

  def self.under?(path, entry) = path == entry || path.start_with?("#{entry}/")

  def self.in_callers?(path) = CALLERS.any? { |root| under?(path, root) }

  # The most specific SCREENS entry for a path, as [entry, screen], or nil.
  def self.winning_entry(path, screens)
    screens.flat_map { |screen, entries| entries.map { |entry| [ entry, screen ] } }
           .select { |entry, _| under?(path, entry) }.max_by { |entry, _| entry.length }
  end

  # The screens a file is mapped to, or nil: SEVERAL_SCREENS' list, SCREEN_FILES'
  # screen, or its most specific SCREENS entry's screen.
  def self.mapped_screens(path, map = MAP)
    return map[:several][path].first if map[:several].key?(path)
    return [ map[:files][path].first ] if map[:files].key?(path)

    entry = winning_entry(path, map[:screens])
    entry && [ entry.last ]
  end

  # The screens a file draws for: its screen folder, its map entry, or "shared".
  # A SHARED path is shared unless SEVERAL_SCREENS or SCREEN_FILES names the
  # file itself, so a broad SCREENS entry (`app/views/admin`) can never make a
  # shared partial one screen's.
  def self.screens_of(path, map = MAP)
    folder = path[%r{\A#{COMPONENTS}/([^/]+)/}, 1]
    return [ folder ] if folder && !REGISTRIES.include?(folder)

    return map[:several][path].first if map[:several].key?(path)
    return [ map[:files][path].first ] if map[:files].key?(path)
    return [ :shared ] if SHARED.any? { |prefix| path.start_with?(prefix) }

    mapped_screens(path, map) || [ :shared ]
  end

  # [Const, path] for every file that names a screen class, its own screen's included.
  def self.users(classes = screen_classes, sources = self.sources)
    classes.flat_map do |cpath, _|
      pattern = pattern_for(cpath)
      sources.filter_map { |path, code| [ cpath, path ] if code.match?(pattern) }
    end
  end

  # [Const, path, its screens] for every user of a screen class outside its screen.
  def self.strangers(classes = screen_classes, sources = self.sources, map = MAP)
    screen_of_class = classes.to_h
    users(classes, sources).filter_map do |cpath, path|
      user_screens = screens_of(path, map)
      [ cpath, path, user_screens ] unless user_screens.include?(screen_of_class.fetch(cpath))
    end
  end

  def self.message(strangers)
    strangers.group_by(&:first).map do |cpath, users|
      "#{cpath} is drawn outside its screen:\n" + users.map { |_, path, screens| "  #{path} (#{screens.join(", ")})" }.join("\n") + "\n  #{FIX}"
    end.join("\n")
  end

  def self.callers
    CALLERS.flat_map { |root| Dir[ROOT.join(root, "**/*.{rb,erb}")] }.map { |path| relative(path) }
           .reject { |path| SHARED.any? { |prefix| path.start_with?(prefix) } }.sort
  end

  # The map's problems, by kind:
  # - unmapped: a CALLERS file the map does not place;
  # - twice: an entry under two keys of SCREENS, or in two of the three hashes;
  # - stale: a SCREENS or SEVERAL_SCREENS entry that is no CALLERS file's entry
  #   (it names nothing, or a more specific entry takes all its files);
  # - outside: a SCREENS or SEVERAL_SCREENS entry not under CALLERS, where a
  #   folder (`app/components/admin/ui`, `app/views/layouts`) would make every
  #   shared file in it one screen's;
  # - files: a SCREEN_FILES entry that is not one existing file outside CALLERS
  #   and outside a screen's folder, names no screen folder, or gives no reason.
  def self.map_problems(map = MAP, callers = self.callers, file: ->(path) { ROOT.join(path).file? }, screen_folders: self.screen_folders)
    entries = map[:screens].flat_map { |screen, list| list.map { |entry| [ entry, screen.to_s ] } } +
              map[:several].map { |entry, (screens, _)| [ entry, screens.join(" and ") ] } +
              map[:files].map { |entry, (screen, _)| [ entry, "#{screen} (SCREEN_FILES)" ] }
    twice = entries.group_by(&:first).select { |_, found| found.size > 1 }
                   .map { |entry, found| "#{entry}: #{found.map(&:last).join(", ")}" }
    unmapped = callers.reject { |path| mapped_screens(path, map) }
    winners = callers.map { |path| map[:several].key?(path) ? path : winning_entry(path, map[:screens])&.first }
    mapped = (map[:screens].values.flatten + map[:several].keys).uniq
    stale = mapped.reject { |entry| winners.include?(entry) }
    outside = mapped.reject { |entry| in_callers?(entry) }
    in_a_screen = %r{\A#{COMPONENTS}/(?!(?:#{REGISTRIES.join("|")})/)[^/]+/}
    files = map[:files].filter_map do |path, (screen, reason)|
      wrong = [ ("not one existing file" unless file.call(path)),
                ("under CALLERS: map it in SCREENS" if in_callers?(path)),
                ("in a screen's folder, which is that screen's already" if path.match?(in_a_screen)),
                ("#{screen.inspect} is no screen folder" unless screen_folders.include?(screen)),
                ("no reason written out" unless reason.to_s.length > 40) ].compact
      "#{path}: #{wrong.join("; ")}" if wrong.any?
    end
    { unmapped:, twice:, stale:, outside:, files: }
  end

  # Floors well under what the tree holds: a broken glob, path, matcher or comment stripper
  # finds a handful or none and fails here, and moving more components to ui/
  # does not.
  test "the guard is looking at the code" do
    assert_operator self.class.screen_classes.size, :>, 100, "too few screen classes found"
    assert_operator self.class.callers.size, :>, 100, "too few CS Studio views, controllers and concerns found"
    assert_operator self.class.sources.size, :>, 700, "too few files under app/ read"
    assert_operator self.class.users.size, :>, USERS_FLOOR, "too few users of screen classes found: the matcher or the comment stripper reads nothing"
  end

  test "every screen component is drawn by its own screen only" do
    strangers = self.class.strangers
    assert_empty strangers, -> { self.class.message(strangers) }
  end

  test "every admin view folder, controller and concern is mapped to one screen or shared" do
    problems = self.class.map_problems
    assert_empty problems[:unmapped], "not in ComponentScreensTest::SCREENS: map each to the screen it draws, or :shared (SEVERAL_SCREENS for a file that draws more than one):\n#{problems[:unmapped].join("\n")}"
    assert_empty problems[:twice], "listed twice in the map (a file that draws several screens goes in SEVERAL_SCREENS only):\n#{problems[:twice].join("\n")}"
  end

  test "the map names only folders and files that exist" do
    stale = self.class.map_problems[:stale]
    assert_empty stale, "a SCREENS or SEVERAL_SCREENS entry names no file on disk (or only files a more specific entry takes): delete it\n#{stale.join("\n")}"
  end

  test "SCREENS and SEVERAL_SCREENS name only CS Studio's views, controllers and concerns, and SCREEN_FILES one file each with its reason" do
    problems = self.class.map_problems
    assert_empty problems[:outside], "not under #{CALLERS.join(", ")}: a file elsewhere that is one screen's goes in SCREEN_FILES with its reason\n#{problems[:outside].join("\n")}"
    assert_empty problems[:files], "SCREEN_FILES:\n#{problems[:files].join("\n")}"
  end

  test "every key of the map is a screen folder or :shared" do
    assert_equal (self.class.screen_folders + [ :shared ]).map(&:to_s).sort, SCREENS.keys.map(&:to_s).sort
  end

  test "a file of SEVERAL_SCREENS names two screen folders or more, and says why" do
    SEVERAL_SCREENS.each do |path, (screens, reason)|
      assert_operator screens.uniq.size, :>=, 2, "#{path} draws one screen: put it in SCREENS"
      assert_empty screens - self.class.screen_folders, "#{path} names a folder that is no screen's"
      assert_operator reason.length, :>, 40, "#{path} needs its reason written out"
    end
  end

  test "the guard can fail: a screen component named in a shared file's code, and not in its comments" do
    classes = [ [ "Admin::DashboardScreen::PanelComponent", "dashboard_screen" ] ]
    planted = ->(path, source) { self.class.strangers(classes, { path => self.class.code_of(path, source) }) }

    assert_equal [ [ "Admin::DashboardScreen::PanelComponent", "app/components/admin/ui/sample_component.rb", [ :shared ] ] ],
      planted.("app/components/admin/ui/sample_component.rb", "module Admin\n  module Ui\n    X = DashboardScreen::PanelComponent.new\n  end\nend\n")
    assert_equal 1, planted.("app/components/admin/ui/sample_component.html.erb", "<%= render ::Admin::DashboardScreen::PanelComponent.new %>").size
    assert_equal 1, planted.("app/components/admin/ui/sample_component.rb", "class S < Admin::DashboardScreen::PanelComponent; end").size
    assert_equal 1, planted.("app/components/admin/ui/sample_component.rb", "Admin::DashboardScreen::PanelComponent::KINDS").size
    assert_equal 1, planted.("app/components/admin/notes_screen/sample_component.rb", "Admin::DashboardScreen::PanelComponent.new").size

    assert_empty planted.("app/components/admin/ui/sample_component.rb", "# Admin::DashboardScreen::PanelComponent\nx = 1 # DashboardScreen::PanelComponent.new\n")
    assert_empty planted.("app/components/admin/ui/sample_component.html.erb", "<%# render Admin::DashboardScreen::PanelComponent\n    over two lines %>\n<p></p>")
    assert_empty planted.("app/components/admin/ui/sample_component.rb", "Admin::Ui::PanelComponent.new; PanelComponent.new; MyDashboardScreen::PanelComponent; DashboardScreen::PanelComponentFoo")
    assert_empty planted.("app/components/admin/dashboard_screen/sample_component.rb", "PanelComponent.new")
    assert_empty planted.("app/views/admin/dashboard/sample.html.erb", "<%= render Admin::DashboardScreen::PanelComponent.new %>")
  end

  REASON = "a reason long enough to say why the file is the screen's".freeze

  test "the map's own checks: an unmapped file, an entry listed twice, an override, a stale entry and a file of several screens" do
    map = { screens: { "a_screen" => %w[app/views/admin/x app/views/admin/gone app/controllers/admin/z_controller.rb],
                       "b_screen" => %w[app/views/admin/x/one.html.erb app/views/admin/x] },
            several: { "app/controllers/admin/z_controller.rb" => [ %w[a_screen b_screen], REASON ],
                       "app/controllers/admin/w_controller.rb" => [ %w[a_screen b_screen], REASON ] },
            files: { "app/components/admin/ui/p.html.erb" => [ "a_screen", REASON ] } }
    callers = %w[app/views/admin/x/one.html.erb app/views/admin/x/two.html.erb app/views/admin/y/three.html.erb
                 app/controllers/admin/z_controller.rb app/controllers/admin/w_controller.rb]
    problems = self.class.map_problems(map, callers, file: ->(_) { true }, screen_folders: %w[a_screen b_screen])

    assert_equal %w[app/views/admin/y/three.html.erb], problems[:unmapped]
    assert_equal [ "app/views/admin/x: a_screen, b_screen", "app/controllers/admin/z_controller.rb: a_screen, a_screen and b_screen" ], problems[:twice]
    assert_equal %w[app/views/admin/gone], problems[:stale]
    assert_empty problems[:outside]
    assert_empty problems[:files]
    assert_equal [ "b_screen" ], self.class.mapped_screens("app/views/admin/x/one.html.erb", map)
    assert_equal %w[a_screen b_screen], self.class.screens_of("app/controllers/admin/w_controller.rb", map)
    assert_equal [ "a_screen" ], self.class.screens_of("app/components/admin/ui/p.html.erb", map)
    assert_equal [ :shared ], self.class.screens_of("app/components/admin/ui/q.html.erb", map)
    assert_equal [ :shared ], self.class.screens_of("app/views/setup/mail.html.erb", map)
    assert_equal [ :shared ], self.class.screens_of("app/views/layouts/admin.html.erb", map)

    broad = { screens: { "a_screen" => %w[app/views/admin app/controllers/admin] }, several: {}, files: {} }
    assert_equal [ "a_screen" ], self.class.screens_of("app/views/admin/x/one.html.erb", broad)
    assert_equal [ :shared ], self.class.screens_of("app/views/admin/shared/_row.html.erb", broad)
    assert_equal [ :shared ], self.class.screens_of("app/controllers/admin/base_controller.rb", broad)

    classes = [ [ "Admin::BScreen::RowComponent", "b_screen" ], [ "Admin::CScreen::RowComponent", "c_screen" ] ]
    drawn = self.class.strangers(classes, { "app/controllers/admin/w_controller.rb" => "Admin::BScreen::RowComponent; CScreen::RowComponent" }, map)
    assert_equal [ [ "Admin::CScreen::RowComponent", "app/controllers/admin/w_controller.rb", %w[a_screen b_screen] ] ], drawn
  end

  test "the map refuses a shared folder made one screen's, and a SCREEN_FILES entry that is a folder, has no reason or belongs elsewhere" do
    escape = { screens: { "a_screen" => %w[app/components/admin/ui app/views/layouts app/helpers app] },
               several: { "app/jobs" => [ %w[a_screen b_screen], REASON ] }, files: {} }
    assert_equal %w[app/components/admin/ui app/views/layouts app/helpers app app/jobs],
      self.class.map_problems(escape, [], screen_folders: %w[a_screen b_screen])[:outside]

    files = { "app/components/admin/ui" => [ "a_screen", REASON ],
              "app/views/layouts" => [ "a_screen", REASON ],
              "app/views/layouts/admin.html.erb" => [ "a_screen", "" ],
              "app/views/admin/x.html.erb" => [ "a_screen", REASON ],
              "app/components/admin/b_screen/x_component.rb" => [ "a_screen", REASON ],
              "app/helpers/x_helper.rb" => [ "z_screen", REASON ] }
    problems = self.class.map_problems({ screens: {}, several: {}, files: files }, [], file: ->(path) { path.end_with?(".rb", ".erb") },
                                       screen_folders: %w[a_screen b_screen])[:files]

    assert_equal [ "app/components/admin/ui: not one existing file",
                   "app/views/layouts: not one existing file",
                   "app/views/layouts/admin.html.erb: no reason written out",
                   "app/views/admin/x.html.erb: under CALLERS: map it in SCREENS",
                   "app/components/admin/b_screen/x_component.rb: in a screen's folder, which is that screen's already",
                   "app/helpers/x_helper.rb: \"z_screen\" is no screen folder" ], problems
  end
end
