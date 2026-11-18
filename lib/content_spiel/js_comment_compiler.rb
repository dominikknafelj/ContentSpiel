require "propshaft/compiler"
require_relative "js_comment_stripper"

# The Propshaft compiler that serves the app's own JavaScript without its
# comments (`ContentSpiel::JsCommentStripper` says what goes and what never
# does). Registered for `text/javascript` by config/initializers/assets.rb in
# production only, so `assets:precompile` in the image writes the stripped
# files into public/assets while development and test serve every file
# exactly as written.
#
# Whose files: the app's own, under app/javascript, and a theme's own
# controllers, under its `javascript` folder (`ThemeFolder#asset_paths`),
# which are written the same way and served the same way. Never
# vendor/javascript (Turbo, Stimulus, Tiptap, Mermaid…), a gem's files or a
# `.min.js` anywhere.
module ContentSpiel
  class JsCommentCompiler < Propshaft::Compiler
    def self.own_roots
      [ Rails.root.join("app/javascript"), ThemeFolder.current.controllers_path&.parent ].compact.map { |root| "#{root}/" }
    end

    def self.own?(path)
      path = path.to_s
      !path.end_with?(".min.js") && own_roots.any? { |root| path.start_with?(root) }
    end

    def compile(asset, input)
      return input unless self.class.own?(asset.path)

      result = JsCommentStripper.call(input)
      unless result.stripped?
        Propshaft.logger.warn "Kept the comments of #{asset.logical_path}: #{result.untouched}"
      end
      result.output
    end
  end
end
