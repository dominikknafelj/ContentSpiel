require "test_helper"
require_relative "source_layout_test"
require_relative "dependency_direction_test"

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
# screen's folder; SCREENS or SEVERAL_SCREENS, the map of CS Studio's views,
# controllers and controller concerns; or SHARED. Anything else under `app/`
# (the setup wizard, a job, a mailer) counts as shared.
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

  # Every file under these is in SHARED or mapped by SCREENS or SEVERAL_SCREENS.
  CALLERS = %w[app/views/admin app/controllers/admin app/controllers/concerns/admin].freeze

  # Each CS Studio view folder or file, controller and controller concern, by
  # the screen it draws. The most specific entry wins, so a view file may name
  # another screen than its folder, and an entry wins over SHARED, so a shared
  # folder's file that draws one screen's listing is that screen's. `:shared` is a file that more than one
  # screen uses, or a screen with no component folder of its own (Your
  # account, System status, sign-in, ⌘K, the error pages): either way it may
  # draw shared components only.
  SCREENS = {
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
      app/components/admin/ui/media_picker_component.html.erb
    ], # the picker draws the Media screen's own listing (/media?picker=1), and the upload answers with its tile
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
      app/views/admin/accounts
      app/views/admin/errors
      app/views/admin/jump
      app/views/admin/passwords
      app/views/admin/sessions
      app/views/admin/system_status
      app/controllers/admin/accounts_controller.rb
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
      app/controllers/concerns/admin/stale_form.rb
      app/controllers/concerns/admin/toast_stream.rb
      app/controllers/concerns/admin/translatable_record_loading.rb
    ] # media_assets: the picker's upload; rail_tab_streams and slot_streams: the slots' streams, whatever screen hosts them
  }.freeze

  # A file that draws more than one screen, each by name, with the reason. It is
  # here and never under two keys of SCREENS, where a file listed twice is a
  # mistake the map refuses.
  SEVERAL_SCREENS = {
    "app/controllers/admin/pages_controller.rb" => [
      %w[editor_screen pages_screen],
      "the Pages screen's controller: the editor in the content frame, and the tree row it redraws when a page's title or state changes"
    ]
  }.freeze

  FIX = "Move it to app/components/admin/ui/ and give it Admin::Ui::Contract (docs/reference/design-system.md, 'Component contract')."

  # The code of a file, its comments blanked: Ruby's by Ripper
  # (`DependencyDirectionTest.without_comments`, so a `#` in a string stays);
  # ERB's `<%# … %>` blocks, then the `#` lines of its Ruby
  # (`SourceLayoutTest::COMMENT_LINES`).
  def self.code_of(path, source = File.read(path))
    case File.extname(path)
    when ".rb" then DependencyDirectionTest.without_comments(source)
    when ".erb" then source.gsub(/<%#.*?%>/m) { |comment| comment.gsub(/[^\n]/, "") }.gsub(SourceLayoutTest::COMMENT_LINES.fetch(".erb"), "")
    else source
    end
  end

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

  # The screens a caller file is mapped to: SEVERAL_SCREENS' list, or its most
  # specific SCREENS entry's one screen, or nil.
  def self.mapped_screens(path, map = SCREENS, several = SEVERAL_SCREENS)
    return several[path].first if several.key?(path)

    screen = map.flat_map { |key, entries| entries.map { |entry| [ entry, key ] } }
                .select { |entry, _| path == entry || path.start_with?("#{entry}/") }
                .max_by { |entry, _| entry.length }&.last
    screen && [ screen ]
  end

  # The screens a file draws for: its screen folder, its map entry, or "shared".
  def self.screens_of(path, map = SCREENS, several = SEVERAL_SCREENS)
    folder = path[%r{\A#{COMPONENTS}/([^/]+)/}, 1]
    return [ folder ] if folder && !REGISTRIES.include?(folder)

    mapped_screens(path, map, several) || [ :shared ]
  end

  # [Const, path, its screens] for every user of a screen class outside its screen.
  def self.strangers(classes = screen_classes, sources = self.sources, map = SCREENS, several = SEVERAL_SCREENS)
    classes.flat_map do |cpath, screen|
      pattern = pattern_for(cpath)
      sources.filter_map do |path, code|
        user_screens = screens_of(path, map, several)
        [ cpath, path, user_screens ] if !user_screens.include?(screen) && code.match?(pattern)
      end
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

  # [unmapped callers, entries mapped twice, entries that name nothing]. An
  # entry is mapped twice when it is under two keys of SCREENS, or in SCREENS
  # and SEVERAL_SCREENS both. An entry outside CALLERS (a shared folder's file)
  # needs only to exist; one inside must be the entry that wins for a file.
  def self.map_problems(map = SCREENS, callers = self.callers, several = SEVERAL_SCREENS, exists: ->(entry) { ROOT.join(entry).exist? })
    entries = map.flat_map { |screen, list| list.map { |entry| [ entry, screen ] } } +
              several.map { |entry, (screens, _)| [ entry, screens.join(" and ") ] }
    twice = entries.group_by(&:first).select { |_, found| found.size > 1 }
                   .map { |entry, found| "#{entry}: #{found.map(&:last).join(", ")}" }
    unmapped = callers.reject { |path| mapped_screens(path, map, several) }
    winners = callers.map { |path| several.key?(path) ? path : map.values.flatten.select { |entry| path == entry || path.start_with?("#{entry}/") }.max_by(&:length) }
    in_callers = ->(entry) { CALLERS.any? { |root| entry == root || entry.start_with?("#{root}/") } }
    stale = entries.map(&:first).uniq.reject { |entry| exists.call(entry) && (winners.include?(entry) || !in_callers.call(entry)) }
    [ unmapped, twice, stale ]
  end

  # Floors well under today's counts (147 screen classes, 132 callers): a broken
  # glob or path finds a handful or none and fails here, and moving more
  # components to ui/ does not.
  test "the guard is looking at the code" do
    assert_operator self.class.screen_classes.size, :>, 100, "too few screen classes found"
    assert_operator self.class.callers.size, :>, 100, "too few CS Studio views, controllers and concerns found"
  end

  test "every screen component is drawn by its own screen only" do
    strangers = self.class.strangers
    assert_empty strangers, -> { self.class.message(strangers) }
  end

  test "every admin view folder, controller and concern is mapped to one screen or shared" do
    unmapped, twice, = self.class.map_problems
    assert_empty unmapped, "not in ComponentScreensTest::SCREENS: map each to the screen it draws, or :shared (SEVERAL_SCREENS for a file that draws more than one):\n#{unmapped.join("\n")}"
    assert_empty twice, "listed twice in the map (a file that draws several screens goes in SEVERAL_SCREENS only):\n#{twice.join("\n")}"
  end

  test "the map names only folders and files that exist" do
    _, _, stale = self.class.map_problems
    assert_empty stale, "a SCREENS entry names no file on disk (or only files a more specific entry takes): delete it\n#{stale.join("\n")}"
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

  test "the map's own checks: an unmapped file, an entry listed twice, an override, a stale entry and a file of several screens" do
    map = { "a_screen" => %w[app/views/admin/x app/views/admin/gone app/controllers/admin/z_controller.rb app/components/admin/ui/p.html.erb],
            "b_screen" => %w[app/views/admin/x/one.html.erb app/views/admin/x] }
    several = { "app/controllers/admin/z_controller.rb" => [ %w[a_screen b_screen], "reason" ], "app/controllers/admin/w_controller.rb" => [ %w[a_screen b_screen], "reason" ] }
    callers = %w[app/views/admin/x/one.html.erb app/views/admin/x/two.html.erb app/views/admin/y/three.html.erb
                 app/controllers/admin/z_controller.rb app/controllers/admin/w_controller.rb]
    unmapped, twice, stale = self.class.map_problems(map, callers, several, exists: ->(entry) { !entry.end_with?("gone") })

    assert_equal %w[app/views/admin/y/three.html.erb], unmapped
    assert_equal [ "app/views/admin/x: a_screen, b_screen", "app/controllers/admin/z_controller.rb: a_screen, a_screen and b_screen" ], twice
    assert_equal %w[app/views/admin/gone], stale, "a shared folder's file in the map needs only to exist"
    assert_equal [ "b_screen" ], self.class.mapped_screens("app/views/admin/x/one.html.erb", map, several)
    assert_equal %w[a_screen b_screen], self.class.screens_of("app/controllers/admin/w_controller.rb", map, several)
    assert_equal [ "a_screen" ], self.class.screens_of("app/components/admin/ui/p.html.erb", map, several)
    assert_equal [ :shared ], self.class.screens_of("app/components/admin/ui/q.html.erb", map, several)
    assert_equal [ :shared ], self.class.screens_of("app/views/setup/mail.html.erb", map, several)
    assert_equal [ :shared ], self.class.screens_of("app/views/layouts/admin.html.erb", map, several)

    classes = [ [ "Admin::BScreen::RowComponent", "b_screen" ], [ "Admin::CScreen::RowComponent", "c_screen" ] ]
    drawn = self.class.strangers(classes, { "app/controllers/admin/w_controller.rb" => "Admin::BScreen::RowComponent; CScreen::RowComponent" }, map, several)
    assert_equal [ [ "Admin::CScreen::RowComponent", "app/controllers/admin/w_controller.rb", %w[a_screen b_screen] ] ], drawn
  end
end
