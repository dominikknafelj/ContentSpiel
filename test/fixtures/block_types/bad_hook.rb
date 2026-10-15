# A gem's hook that names a bare type, loaded into a production boot ahead of
# everything (`RUBYOPT=-r<this file>`) by test/lib/production_boot_test.rb:
# the boot does not start, and its error names this file and line. The hook's
# file is the application's own, so Ruby loads it once, here and again
# (as nothing) from config/application.rb.
require_relative "../../../lib/content_spiel/plugins"

ContentSpiel::Plugins.block_types { |types| types.register("album") { |t| t.label "Album" } }
