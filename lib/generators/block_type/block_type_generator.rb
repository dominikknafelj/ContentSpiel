require "rails/generators/named_base"

# `bin/rails generate block_type callout` (block types spec, "The
# generator"): a built-in block type of this repository, in the places Rails
# expects (decision 15), with the two lines every type declares filled in.
# An engine's generator, for an `owner/name` type, is step 2. In lib/generators,
# Rails' place for a generator, which `autoload_lib` ignores.
#
# `bin/rails destroy block_type callout` takes back what this wrote: Thor
# reverses each step, the inserted lines included.
class BlockTypeGenerator < Rails::Generators::NamedBase
  source_root File.expand_path("templates", __dir__)

  # The three marker lines, each exactly as it stands in its file (with that
  # file's indentation): the built-ins' registrations in types.rb are inside
  # `to_prepare` and its `begin`, so four spaces; a type's scope is under
  # `public.blocks` (six) and under the tile's `types` (twelve).
  TYPES_MARKER = "    # bin/rails generate block_type adds a built-in's line above this one.\n".freeze
  PUBLIC_MARKER = "      # bin/rails generate block_type adds a type's scope below this line.\n".freeze
  TILE_MARKER = "            # bin/rails generate block_type adds a type's scope below this line.\n".freeze

  def refuse_a_name_that_is_not_a_built_ins
    raise Thor::Error, "#{name}: an outside type is an engine's (owner/name), and its generator is not built yet" if name.include?("/")
    raise Thor::Error, "#{name}: a block type's name is lowercase words joined by underscores (callout, pull_quote)" unless name.match?(/\A[a-z][a-z0-9_]*\z/)
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
