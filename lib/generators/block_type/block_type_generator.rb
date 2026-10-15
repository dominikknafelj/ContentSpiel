require "rails/generators/named_base"

# `bin/rails generate block_type callout` (block types spec, "The
# generator"): a built-in block type of this repository, in the places Rails
# expects (decision 15), with the two lines every type declares filled in.
# An engine's generator, for an `owner/name` type, is step 2. In lib/generators,
# Rails' place for a generator, which `autoload_lib` ignores.
#
# `bin/rails destroy block_type callout` takes back what this wrote: Thor
# reverses each step, the inserted lines included. It removes only a type
# whose definition still carries `GENERATED` (the line the template writes),
# so `destroy block_type code` removes nothing of the Code block, and
# `destroy block_type tokens` nothing of the default theme.
class BlockTypeGenerator < Rails::Generators::NamedBase
  source_root File.expand_path("templates", __dir__)

  # The three marker lines, each exactly as it stands in its file (with that
  # file's indentation): the built-ins' registrations in types.rb are inside
  # `to_prepare` and its `begin`, so four spaces; a type's scope is under
  # `public.blocks` (six) and under the tile's `types` (twelve).
  TYPES_MARKER = "    # bin/rails generate block_type adds a built-in's line above this one.\n".freeze
  PUBLIC_MARKER = "      # bin/rails generate block_type adds a type's scope below this line.\n".freeze
  TILE_MARKER = "            # bin/rails generate block_type adds a type's scope below this line.\n".freeze

  # The words the generated definition and stylesheet carry, by which
  # `destroy` knows a file this generator wrote and a person has not yet
  # taken as theirs (the line says to take it out then).
  GENERATED = "Written by bin/rails generate block_type".freeze

  # Psych reads these as true, false or nil, so `on: {}` would be no scope
  # named "on" in a locale file.
  YAML_WORDS = %w[yes no on off true false null].freeze

  NAME = /\A[a-z][a-z0-9]*(?:_[a-z][a-z0-9]*)*\z/

  def refuse_a_name_that_is_not_a_built_ins
    refuse_the_name
    behavior == :revoke ? refuse_what_this_did_not_write : refuse_what_exists
  end

  def definition
    template "definition.rb", "app/models/block_types/#{file_name}.rb"
    insert_into_file "config/initializers/types.rb", "    BlockTypes::#{class_name}.register\n", before: TYPES_MARKER
  end

  def public_render
    template "component.rb", "app/components/blocks/#{file_name}_component.rb"
    template "component.html.erb", "app/components/blocks/#{file_name}_component.html.erb"
    template "stylesheet.css", "app/assets/tailwind/themes/default/#{file_name}.css"
  end

  def scopes
    scope "config/locales/public.en.yml", PUBLIC_MARKER, "      #{file_name}: {}\n"
    scope "config/locales/admin/editor_screen.en.yml", TILE_MARKER, "            #{file_name}: {}\n"
  end

  def tests_and_preview
    template "preview.rb", "test/components/previews/blocks/#{file_name}_component_preview.rb"
    template "definition_test.rb", "test/models/block_types/#{file_name}_test.rb"
    template "component_test.rb", "test/components/blocks/#{file_name}_component_test.rb"
  end

  private

  def refuse(reason) = raise(Thor::Error, "#{name}: #{reason}")

  # What makes a name no type's name, whether generated or destroyed.
  def refuse_the_name
    refuse "an outside type is an engine's (owner/name), and its generator is not built yet" if name.include?("/")
    refuse "a block type's name is lowercase words joined by underscores, each starting with a letter (callout, pull_quote)" unless name.match?(NAME)
    refuse "the name must come back from its class name (#{class_name}), and this one comes back as #{class_name.underscore}" unless class_name.underscore == name && name.camelize == class_name
    refuse "a locale file reads #{name}: as #{YAML.load("#{name}: 1").keys.first.inspect}, so the type's scope could not be named; choose another name" if YAML_WORDS.include?(name)
    # `BlockTypes::Post` would be what a bare `Post` written inside
    # `module BlockTypes` means: `Post.kept` in the Post list, `Blocks::` in
    # every definition's `t.component` (the shadowing CLAUDE.md describes
    # for `Admin::`).
    refuse "#{class_name} is a constant of the application, which a module BlockTypes::#{class_name} would shadow inside module BlockTypes (every built-in names #{class_name} there or may); choose another name" if Object.const_defined?(class_name)
  end

  def refuse_what_exists
    refuse "is a block type already; a type is generated once" if BlockTypes.find(name) || BlockTypes.const_defined?(class_name, false)
    refuse "#{name}.css is a stylesheet of the default theme, which the type's stylesheet would replace; choose another name" if theme_stylesheets.include?("#{name}.css")
    taken = targets.select { |path| File.exist?(File.join(destination_root, path)) }
    refuse "these files exist, and a generator writes only new ones: #{taken.join(", ")}" if taken.any?
  end

  # `destroy` removes a definition, a stylesheet and the tests: only where
  # the definition (and the stylesheet, if there is one) still carries the
  # line this generator wrote, so nothing a person wrote, or took as theirs,
  # is removed.
  def refuse_what_this_did_not_write
    ours = %W[app/models/block_types/#{file_name}.rb app/assets/tailwind/themes/default/#{file_name}.css].map { |path| File.join(destination_root, path) }
    refuse "has no definition this generator wrote (app/models/block_types/#{file_name}.rb), and destroy removes nothing" unless File.exist?(ours.first)
    not_ours = ours.select { |path| File.exist?(path) && !File.read(path).include?(GENERATED) }
    refuse "#{not_ours.map { |path| path.delete_prefix("#{destination_root}/") }.join(" and ")} #{not_ours.one? ? "carries" : "carry"} no line \"#{GENERATED}\": #{not_ours.one? ? "it is" : "they are"} not this generator's (or #{not_ours.one? ? "it is" : "they are"} yours now), and destroy removes nothing" if not_ours.any?
  end

  def theme_stylesheets
    [ Rails.root, destination_root ].flat_map { |root| Dir.glob("*.css", base: File.join(root, "app/assets/tailwind/themes/default")) }.uniq
  end

  def targets
    %W[
      app/models/block_types/#{file_name}.rb
      app/components/blocks/#{file_name}_component.rb
      app/components/blocks/#{file_name}_component.html.erb
      app/assets/tailwind/themes/default/#{file_name}.css
      test/components/previews/blocks/#{file_name}_component_preview.rb
      test/models/block_types/#{file_name}_test.rb
      test/components/blocks/#{file_name}_component_test.rb
    ]
  end

  # A scope goes below the file's marker line; a file without one gets
  # nothing, and the generator says where to write it by hand.
  def scope(file, marker, line)
    path = File.join(destination_root, file)
    if File.exist?(path) && File.read(path).include?(marker)
      insert_into_file file, line, after: marker
    else
      say_status :skip, "#{file} has no marker line (#{marker.strip}): add the #{file_name} scope by hand", :yellow
    end
  end
end
