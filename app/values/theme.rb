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
    def with(theme)
      before = current
      @current = theme
      yield
    ensure
      @current = before
    end

    # The theme a folder is (`ThemeFolder`), with the fingerprint and the
    # number of templates it has at this moment. The application's own is
    # loaded when it is prepared (`config/initializers/theme.rb`); a test
    # loads the second theme (`test/support/theme_test_helper.rb`).
    def load(folder)
      new(path: folder.path, fingerprint: folder.fingerprint, template_count: folder.templates.size)
    end
  end

  attr_reader :path, :fingerprint, :template_count

  def initialize(path: nil, fingerprint: DEFAULT_FINGERPRINT, template_count: 0)
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
