# The theme that draws the public site (theming spec §1 and §3). `Theme.current`
# is built from the folder `THEME_PATH` names when the application is prepared
# (`config/initializers/theme.rb`), as every registry is, and a test swaps it
# for the length of a block (`Theme.with`, `test/support/theme_test_helper.rb`).
# Without a folder it is the default theme: every question below is answered
# with the CMS's own.
#
# THE ONE PLACE THAT KNOWS HOW A COMPONENT'S TEMPLATE IS REPLACED.
# ViewComponent finds a template beside its class file and never asks the
# view path, so a theme's `components/blocks/image_component.html.erb` is not
# found by putting the folder on a path. `component_for` is already where the
# public site gets a block's, a post list's and a post's component from
# (`ThemeHelper#render_block`, `Blocks::PostListComponent#list_component`).
# For a component whose template the folder holds it answers a subclass
# generated here, once per theme: `Class.new(component)` whose
# `sidecar_files` answers the theme's file. The template is therefore
# compiled into a class of the theme's own and calls everything the default
# template calls (the private readers included, as any subclass may), and
# the CMS's class keeps its own template, so one process can hold two themes
# and a test can draw both.
#
# Three things the subclass has to say because it is anonymous, each read
# from view_component 4.15.0:
# - `name`: `ViewComponent::Template#safe_method_name` calls
#   `@component.name.underscore`, and an anonymous class has no name;
# - `virtual_path`: `ViewComponent::Base.inherited` derives it from the name
#   at a moment the class has none yet;
# - `identifier`: `inherited` takes it from the call stack, which is this
#   file; with the component's own, every question but the template's
#   (`sidecar_files` for a translation file) is answered as the component's.
#
# The rejected way is the spike's: an override of
# `ApplicationComponent.sidecar_files`, which compiles the theme's template
# into the CMS's own class, so a process holds one theme and no test draws
# two. `test/values/theme_test.rb` is the proof that this way works, and it
# fails on the day an upgrade of the gem changes `sidecar_files`.
#
# The subclasses live as long as their Theme does. A code reload in
# development builds a new Theme (`to_prepare`), and with it new subclasses
# of the freshly loaded components.
class Theme
  DEFAULT_FINGERPRINT = "default".freeze

  class << self
    attr_writer :current

    def current = @current ||= new

    # `theme` for the length of the block, and the theme that was current
    # before afterwards, also when the block raises.
    #
    # FOR TESTS ONLY, and so is `current=` outside the one assignment in
    # `config/initializers/theme.rb`. `current` is one variable of the
    # PROCESS, not of a request or a thread: a swap made while a request is
    # being answered draws every other request of the process with the
    # other theme, and puts its fingerprint into their ETags. That is what a
    # test wants (a system test's server runs in the test's process and
    # must see the swap) and what the application must never do: it asks
    # `Theme.current` and sets nothing. `test/lib/theme_guards_test.rb`
    # ("nothing in the application swaps the theme") reads app, lib and
    # config for either.
    def with(theme)
      before = current
      @current = theme
      yield
    ensure
      @current = before
    end

    # The theme a folder is (`ThemeFolder`), with the fingerprint and the
    # number of templates it has at this moment. REFUSES a folder that holds
    # anything the contract does not name, or a template that cannot draw a
    # page or writes what is the CMS's to write (`Theme::Check`), with every
    # problem in the message: called when the application is prepared
    # (`config/initializers/theme.rb`), whose first run is the boot, so such
    # a folder stops the boot (theming spec §8). A test loads the second
    # theme through here too (`test/support/theme_test_helper.rb`).
    #
    # The one door: nothing in the application builds a Theme of a folder
    # with `new`, which checks nothing (`test/lib/theme_guards_test.rb`).
    def load(folder)
      problems = Check.problems(folder)
      if problems.any?
        raise ThemeFolder::Invalid, "#{ThemeFolder::VARIABLE} (#{folder.path}) is not a theme this version can draw:\n" \
                                    "#{problems.map { |problem| "  - #{problem}\n" }.join}" \
                                    "Correct the folder, or unset #{ThemeFolder::VARIABLE} to start with the default theme. " \
                                    "bin/rails theme:check says these and what only it reads for: a template that does not " \
                                    "compile, and one that reads the request."
      end

      new(path: folder.path, fingerprint: folder.fingerprint, template_count: folder.templates.size)
    end

    # `load` for the application's own theme, with the two ways a refusal is
    # answered (`config/initializers/theme.rb`).
    #
    # AT BOOT IT RAISES, and the application does not start.
    #
    # ON A RELOAD IT DOES NOT. In development a changed file of the theme
    # reloads the application and the check runs again in `to_prepare`. An
    # exception there stops the chain of prepare blocks where it is raised:
    # the type registries, filled by a block that runs after the theme's
    # (`config/initializers/types.rb`), stay empty, the reloader counts the
    # reload as done, and the request after the error page is drawn by the
    # default theme with no block types. So the refusal is kept: the answer
    # is a theme that brings nothing and remembers why, and every public
    # request raises it (`PublicPageRendering#look_in_the_theme_first`)
    # until a reload finds the folder sound. CS Studio is untouched, as it
    # is by any theme (`test/integration/theme_pages_test.rb`: "a theme
    # refused on a reload leaves the registries prepared…").
    #
    # WHAT IS RESCUED. At boot nothing: a refusal (`ThemeFolder::Invalid`)
    # stops the boot with its message, and anything else is a fault and
    # stops it as loudly. On a reload EVERYTHING the check can raise
    # (`StandardError`), and not the refusal alone: the reason for keeping
    # a refusal is that nothing may leave a reload's prepare, and that
    # holds for a fault as much as for a finding. The check reads a folder
    # somebody is saving into while it reads (a file listed and then gone
    # is an `Errno::ENOENT`), and a fault of its own did get out this way
    # once (a `KeyError` for a note saved at the folder's top). Such an
    # error is kept as a refusal that says what was raised, so the public
    # page shows it and the next save reads the folder again. Narrower
    # than `StandardError` would be a list of what the check raises today,
    # which is the list that was wrong. Not `Exception`: a `SyntaxError` in
    # the application's own code, an interrupt and an exhausted memory are
    # not the folder's and are not to be kept.
    def prepare(folder, reload:)
      load(folder)
    rescue ThemeFolder::Invalid => error
      raise unless reload

      new(refusal: error)
    rescue StandardError => error
      raise unless reload

      new(refusal: unchecked(folder, error))
    end

    private

    def unchecked(folder, error)
      ThemeFolder::Invalid.new(
        "#{ThemeFolder::VARIABLE} (#{folder.path}) could not be checked: #{error.class}: #{error.message}. The folder may have " \
        "changed while it was read: save a file of the theme to have it read again. If this is said again, it is a fault of " \
        "the check and not of the folder."
      ).tap { |refusal| refusal.set_backtrace(error.backtrace) }
    end
  end

  # `refusal` is why the folder was refused on a reload (`Theme.prepare`),
  # nil for every theme that draws.
  attr_reader :path, :fingerprint, :template_count, :refusal

  def initialize(path: nil, fingerprint: DEFAULT_FINGERPRINT, template_count: 0, refusal: nil)
    @refusal = refusal
    @path = path && Pathname(path)
    @fingerprint = fingerprint
    @template_count = template_count
    @components = Concurrent::Map.new
  end

  def configured? = !path.nil?

  # The folder's base name, for a log line and System status.
  def name = path ? path.basename.to_s : "default"

  # Where the theme's page and layout templates are, looked up before
  # app/views by the two public controllers (`PublicPageRendering`).
  def views_path = path&.join("views")

  # That folder as the view path it is prepended as, or nil when the theme
  # has no `views` folder (or there is no theme). Asked on every public
  # request, so the filesystem is asked once per Theme and the answer kept:
  # a Theme is built when the application is prepared and built again by a
  # reload, which a changed file of the folder causes in development
  # (`config/initializers/theme.rb`).
  def views_directory
    return @views_directory if defined?(@views_directory)

    @views_directory = views_path&.directory? ? views_path.to_s : nil
  end

  # The component that draws `definition` in `role` (`:component` for a
  # block, `:list_component` and `:detail_component` for a content type):
  # the theme's class when the folder holds that component's template, the
  # definition's own otherwise.
  def component_for(definition, role = :component)
    component = definition.public_send(role)
    return component if component.nil?

    @components.compute_if_absent(component) do
      template = template_for(component)
      template ? subclass_with(component, template) : component
    end
  end

  # The theme's own template for a component class, by the component's path:
  # `Blocks::ImageComponent` is `components/blocks/image_component.html.erb`.
  # nil when the folder holds none, and without a folder.
  def template_for(component)
    return nil unless path && component.name

    file = path.join("components", "#{component.name.underscore}.html.erb")
    file.file? ? file : nil
  end

  private

  def subclass_with(component, template)
    Class.new(component) do
      define_singleton_method(:name) { component.name }
      define_singleton_method(:sidecar_files) do |extensions|
        extensions.map(&:to_s).include?("erb") ? [ template.to_s ] : super(extensions)
      end
      self.identifier = component.identifier
      self.virtual_path = component.virtual_path
    end
  end
end
