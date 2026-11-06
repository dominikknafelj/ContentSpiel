# bin/rails 'release:prepare[0.5.0]': the logic is ContentSpiel::Release
# (lib/content_spiel/release.rb). It edits VERSION and CHANGELOG.md and prints
# the commands to run; it runs none of them, so pushing stays the person's.
namespace :release do
  desc "Prepare release V: write VERSION and the changelog section, print the commands to run"
  task :prepare, [ :version ] do |_task, args|
    require_relative "../content_spiel/release"
    version = args[:version] or abort "Usage: bin/rails 'release:prepare[0.5.0]'"
    begin
      commands = ContentSpiel::Release.new(Rails.root).prepare(version)
    rescue ContentSpiel::Release::Refused => e
      abort "release:prepare: #{e.message}"
    end
    puts "Prepared #{version}: lib/content_spiel/version.rb and CHANGELOG.md are changed. Now run:\n\n"
    puts commands.map { |command| "  #{command}" }
    puts "\nMerging the pull request tags v#{version} and publishes the image (docs/reference/hosting.md, \"Releases\")."
  end
end
