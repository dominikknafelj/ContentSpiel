# What a theme's author runs (theming spec, "What a person gets"). The work
# is Theme::Scaffold's and Theme::Check's; these say it to a person.
#
# The path is a rake argument, so the shell needs the quotes:
#   bin/rails 'theme:new[../my-site/theme]'
#   bin/rails 'theme:check[../my-site/theme]'    or, with THEME_PATH set:  bin/rails theme:check
namespace :theme do
  desc "Write a copy of the default theme into a new folder: bin/rails 'theme:new[PATH]'"
  task :new, [ :path ] => :environment do |_task, arguments|
    path = arguments[:path].to_s.strip
    abort "Say where: bin/rails 'theme:new[PATH]'" if path.empty?

    begin
      written = Theme::Scaffold.write(path)
    rescue Theme::Scaffold::Refused => error
      abort error.message
    end

    target = File.expand_path(path)
    puts "Wrote #{written.size} files to #{target}."
    puts "Start the site with THEME_PATH=#{target} and it is drawn by that folder. It looks as before until a file there changes."
  end

  # What an integrator runs, and what a site's image build runs with
  # THEME_PATH set by its Dockerfile. It says every problem as one line that
  # starts with the file, says what is wrong and ends with what to do
  # (`Theme::Check`), then how many, and ends 1; a sound folder is one line
  # and 0. Never an exception's trace for a folder that is refused: this
  # output is read in a build's log.
  #
  # NOT `=> :environment`: the task starts the application itself, inside
  # `ThemeFolder.checking`. Under a THEME_PATH whose folder the contract
  # refuses the application does not start, so as a prerequisite the boot
  # ended the command before this body ran, with rake's "aborted!", a trace
  # and the boot's half of the list (the deep half, a template that does
  # not compile, came to light one build later).
  #
  # What still ends it before the list, each with its own sentence and no
  # trace: a path that is no directory, something at the folder's top that
  # is no part of a theme, a file that cannot be read, a link out of the
  # folder (`ThemeFolder::Invalid`: the folder cannot be read as a theme at
  # all, so there is no list to make), and in production with a real secret
  # a stylesheet built for another theme.
  desc "Say what is wrong with a theme folder: THEME_PATH, or bin/rails 'theme:check[PATH]'"
  task :check, [ :path ] do |_task, arguments|
    path = arguments[:path].to_s.strip

    begin
      folder = path.empty? ? ThemeFolder.from_env(ENV) : ThemeFolder.new(path)
      abort "No theme folder to check: set THEME_PATH or run bin/rails 'theme:check[PATH]'." unless folder.configured?

      ThemeFolder.checking { Rake::Task["environment"].invoke }
      problems = Theme::Check.problems(folder, deep: true)
    rescue ThemeFolder::Invalid => error
      abort error.message
    end

    if problems.empty?
      puts "#{folder.path}: #{folder.templates.size} templates, no problems."
    else
      problems.each.with_index(1) { |problem, number| warn "#{number.to_s.rjust(problems.size.to_s.size)}. #{problem}" }
      abort "#{folder.path}: #{problems.size} #{problems.size == 1 ? "problem" : "problems"}."
    end
  end
end
