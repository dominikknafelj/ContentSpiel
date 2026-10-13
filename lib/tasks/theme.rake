require "shellwords"

# What a theme's author runs (theming spec, "What a person gets"). The work
# is Theme::Scaffold's and Theme::Check's; these say it to a person.
#
# The path is a rake argument, so the shell needs the quotes:
#   bin/rails 'theme:new[../my-site/theme]'
#   bin/rails 'theme:check[../my-site/theme]'    or, with THEME_PATH set:  bin/rails theme:check
# A space in the path is carried by those quotes. A COMMA IS NOT: rake cuts
# a task's arguments at every comma and trims around them, so
# `[/a b/c, d/theme]` arrives as `/a b/c` and `d/theme`, and what was between
# them cannot be put back. Such a path is given in a variable instead, and a
# path that arrives in pieces is refused with that sentence, never used by
# its first piece:
#   THEME_NEW_PATH='/sites/a, b/theme' bin/rails theme:new
#   THEME_PATH='/sites/a, b/theme' bin/rails theme:check
namespace :theme do
  # The folder may hold a repository, dot files and a README already
  # (`Theme::Scaffold`). The second line it prints is a shell's word: the
  # path quoted as a shell needs it, so it pastes.
  #
  # NOT `=> :environment`, as `theme:check` is not: an integrator exports
  # THEME_PATH once, for the folder this command is about to make, and the
  # application does not start under a path that names no directory. So a
  # THEME_PATH that names none is taken out of this process before the
  # application starts, with a line that says so. One that names a folder
  # is left alone: the application starts under it as it would anywhere.
  desc "Write a copy of the default theme into a new folder: bin/rails 'theme:new[PATH]', or THEME_NEW_PATH"
  task :new, [ :path ] do |_task, arguments|
    if arguments.extras.any?
      abort "The path arrived in pieces: rake cuts an argument at a comma. Give a path with a comma in it as " \
            "THEME_NEW_PATH='…' bin/rails theme:new"
    end
    named = ENV[ThemeFolder::VARIABLE].to_s.strip
    if !named.empty? && !File.directory?(File.expand_path(named))
      puts "#{ThemeFolder::VARIABLE} names no folder yet and is not read by this command."
      ENV[ThemeFolder::VARIABLE] = nil # taken out of this process: assigning nil to a variable of the environment deletes it
      ThemeFolder.reset!
    end
    Rake::Task["environment"].invoke
    path = arguments[:path].to_s.strip
    if path.empty?
      path = ENV["THEME_NEW_PATH"].to_s.strip
      # Said BEFORE anything is written: a variable left in a shell from the
      # last run names a folder nobody is thinking of now.
      puts "The path is THEME_NEW_PATH's: #{File.expand_path(path)}" unless path.empty?
    end
    abort "Say where: bin/rails 'theme:new[PATH]'" if path.empty?

    begin
      written = Theme::Scaffold.write(path)
    rescue Theme::Scaffold::Refused => error
      abort error.message
    end

    target = File.expand_path(path)
    puts "Wrote #{written.size} files to #{target}."
    puts "Start the site with THEME_PATH=#{Shellwords.escape(target)} bin/dev and it is drawn by that folder " \
         "(bin/dev also builds the stylesheet as you write). It looks as before until a file there changes."
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
  # folder or to nothing, a hidden folder below the top
  # (`ThemeFolder::Invalid`: the folder cannot be read as a theme at all,
  # so there is no list to make; everything at the top that is no part of a
  # theme is said together), and in production with a real secret a
  # stylesheet built for another theme.
  desc "Say what is wrong with a theme folder: THEME_PATH, or bin/rails 'theme:check[PATH]'"
  task :check, [ :path ] do |_task, arguments|
    if arguments.extras.any?
      abort "The path arrived in pieces: rake cuts an argument at a comma. Give a path with a comma in it as " \
            "THEME_PATH='…' bin/rails theme:check"
    end
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
      warn "#{folder.path}: #{problems.size} #{problems.size == 1 ? "problem" : "problems"}."
    end

    # The application was started under THEME_PATH's folder whatever folder
    # was asked about, and inside `checking` a refusal of THAT folder is
    # kept, not raised. Saying nothing of it would end 0 in a process whose
    # every public page raises.
    #
    # Not when the folder asked about IS that folder (`theme:check[x]` with
    # THEME_PATH=x): it was checked, and its list is above.
    real = ->(directory) { File.realpath(directory.to_s) rescue File.expand_path(directory.to_s) }
    started = ThemeFolder.current
    same = started.configured? && real.(started.path) == real.(folder.path)
    other = path.empty? || same ? nil : Theme.current.refusal
    if other
      warn "#{ThemeFolder::VARIABLE} names another folder, which was NOT checked here and is refused: the application does " \
           "not start under it. Run bin/rails theme:check with no path to hear why."
    end
    exit 1 if problems.any? || other
  end
end
