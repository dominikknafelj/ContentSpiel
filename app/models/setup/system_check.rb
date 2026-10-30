# Read-only environment checks shown in the setup wizard and on CS Studio's
# System status page (design spec 2026-09-26 §4). Never blocking: every
# failure is a warning explaining what won't work and how to fix it. Each
# probe is a callable so tests can swap it; a probe that raises (including
# LoadError, which is what a missing libvips looks like) counts as a
# failure.
module Setup
  class SystemCheck
    # `command` is a console command the reader may copy (nil for most
    # checks) and `docs` a link to read more (nil: nothing in the repo is
    # linked yet). Both default to nil so a Result built with only the three
    # original keywords still works.
    #
    # `link` is a symbol naming where a row sends the reader (today
    # `:mail_settings`), for the component that draws the row to resolve:
    # this model names no route and no component.
    Result = Data.define(:label, :status, :message, :command, :docs, :link) do
      def initialize(label:, status:, message:, command: nil, docs: nil, link: nil) = super

      def ok? = status == :ok
    end

    # What the Mail row offers to copy while mail is NOT ready (Not set up,
    # Saved not tested): the way in for a sole owner with no mail who forgot
    # their password. Shown to anyone who may view System status and copied
    # to a clipboard, so it is this fixed string with a placeholder address
    # and password, nothing computed. It goes through `Users::UpdatePassword`
    # rather than `update!`: the service audits the change and ends every
    # session of that user. `p` prints true/false so a refusal isn't silent
    # (`MAIL_FALLBACK_MESSAGE` says what each means). The new password is
    # typed twice inside double quotes inside the shell's single quotes, so
    # it must contain no quote. Same command as docs/reference/hosting.md.
    MAIL_FALLBACK_MESSAGE = "To set a password from the server instead, run this command with the account's email address, " \
      "replacing “a new password” in both places with the new one (at least #{User::MINIMUM_PASSWORD_LENGTH} characters, with no quotes in it). " \
      "It prints true when the password was changed, and false when it was refused (too short, or the two don't match).".freeze
    MAIL_FALLBACK_COMMAND = %(bin/rails runner 'p Users::UpdatePassword.call(User.find_by!(email_address: "you@example.com"), password: "a new password", password_confirmation: "a new password").ok?').freeze

    # What the "Site address" warning offers to copy: the variable with a
    # placeholder address, a fixed string like the command above. The check's
    # OK message does name the configured origin, which is the address the
    # site is published at and no secret.
    SITE_ADDRESS_COMMAND = "PUBLIC_HOST=https://www.example.org".freeze

    # What the "Theme" warning offers to copy outside production: the build
    # of both stylesheets, which reads THEME_PATH as the server does. A
    # fixed string, like the two above. In production the build is the
    # image's, which is no one command, and the warning carries none.
    STYLESHEET_COMMAND = "bin/rails tailwindcss:build".freeze

    # Talks to the storage service directly rather than through
    # ActiveStorage::Blob.create_and_upload!, which saves the blob row before
    # uploading -- if the upload fails (the case this probe exists to catch),
    # the row would be orphaned since there'd be nothing left to purge it.
    STORAGE_PROBE = -> {
      payload = "contentspiel system check"
      key = "system-check-#{SecureRandom.hex(8)}"
      service = ActiveStorage::Blob.service
      service.upload(key, StringIO.new(payload))
      begin
        service.download(key) == payload
      ensure
        service.delete(key)
      end
    }

    IMAGE_PROBE = -> {
      require "vips"
      Vips::Image.black(4, 4).resize(0.5).write_to_buffer(".png").bytesize.positive?
    }

    WORKER_ALIVE_PROBE = -> { SolidQueue::Process.where(last_heartbeat_at: 5.minutes.ago..).exists? }

    def self.run(**options) = new(**options).run

    # `address` is the site's configured address (`SiteAddress`). `request_ssl`
    # is whether the request that asked for the checks came over an encrypted
    # connection (`request.ssl?`, which both screens hand over): nil when
    # nobody said, as from the console, and then there is nothing to say
    # about HTTPS. `production` is handed in so a test can say it.
    #
    # `reset_link_from_request` is whether a password reset mail takes its
    # link from the request when no address is set: the mailer's own rule
    # (`PasswordsMailer.request_origin_used?`, development and test), which
    # both screens hand over as a boolean so this model knows no mailer. It
    # chooses between two true sentences and nothing else. Nobody having
    # said (the console) it is false, the wording of everywhere that is not
    # a developer's machine.
    #
    # `mail_settings` is the mail's state (`MailSettings.current` when
    # nobody says, handed in so a test can say it) and `mail_settings_link`
    # whether the viewer may manage Settings: the caller decides
    # (`can?("settings.manage")`), and only then does the Mail row carry the
    # link to the Mail card. The wizard has its own Mail step and hands none.
    #
    # `theme` is the theme that draws the site (`Theme.current`), handed in so
    # a test can say it. `stylesheet_probe` answers whether the public
    # stylesheet was built for that theme: by default, whether the build's
    # stamp is the theme's fingerprint (`ThemeFolder.stamp`, one small file).
    def initialize(storage_probe: STORAGE_PROBE, image_probe: IMAGE_PROBE, worker_alive_probe: WORKER_ALIVE_PROBE,
      queue_adapter: ActiveJob::Base.queue_adapter_name,
      address: SiteAddress.current, request_ssl: nil, production: Rails.env.production?,
      reset_link_from_request: false, theme: Theme.current, stylesheet_probe: nil,
      mail_settings: nil, mail_settings_link: false)
      @storage_probe = storage_probe
      @image_probe = image_probe
      @worker_alive_probe = worker_alive_probe
      @queue_adapter = queue_adapter.to_s
      @mail_settings = mail_settings
      @mail_settings_link = mail_settings_link
      @address = address
      @request_ssl = request_ssl
      @production = production
      @reset_link_from_request = reset_link_from_request
      @theme = theme
      @stylesheet_probe = stylesheet_probe || self.class.stylesheet_probe(theme)
    end

    # Whether the public stylesheet was built for `theme`, in three answers:
    # true (the build's stamp is the theme's fingerprint), false (it is
    # another theme's, or an earlier state's of this one) and nil (there is
    # no stamp: nothing was built in this checkout, or the last build
    # failed, since a build takes the stamp away before it starts and writes
    # it after it succeeded, `ThemeCss.build`). The row has a sentence for
    # each of the two that are not true.
    def self.stylesheet_probe(theme, root: Rails.root)
      -> { ThemeFolder.stamp(root)&.then { |stamp| stamp == theme.fingerprint } }
    end

    def run
      [ site_address, https, theme, storage, image_processing, background_jobs, mail ].compact
    end

    private
      # Without an address the app accepts any Host header and builds the
      # addresses in its pages from it, and outside development and test
      # sends no reset mail at all (`PasswordsMailer`: a link taken from the
      # request could be made to point anywhere). In development and test
      # the mail is sent with the request's origin, so the warning has two
      # wordings and shows the one that is true where it is read. The one
      # for development and test says nothing of hosts: test answers any,
      # development keeps Rails' own list (localhost, `.test`, IP addresses).
      #
      # An http address on a page that was reached over HTTPS (a proxy ends
      # TLS and nobody changed the variable) is a warning too. Everything
      # built from the address is still http then (canonical links, the
      # sitemap, the reset mail's link), no cookie is `Secure` and no HSTS is
      # sent, and without this the row would say OK beside an "HTTPS" row
      # that says OK as well, neither telling the person what to change.
      def site_address
        if @address.configured? && !@address.https? && @request_ssl
          warning("Site address", "This site answers at #{@address.origin}. The address is http but this page was reached " \
            "over HTTPS: set PUBLIC_HOST to the https address.", command: SITE_ADDRESS_COMMAND)
        elsif @address.configured?
          ok("Site address", "This site answers at #{@address.origin}.")
        elsif @reset_link_from_request
          warning("Site address", "No site address is set. Addresses in pages and in password reset mails follow the request.",
            command: SITE_ADDRESS_COMMAND)
        else
          warning("Site address", "No site address is set. Any host name is accepted, addresses in pages follow the request, " \
            "and password reset mails are not sent until it is set.", command: SITE_ADDRESS_COMMAND)
        end
      end

      # Production only, and only for a request: nil (no row) otherwise. A
      # development server is plain HTTP on purpose. With an https address
      # set, plain HTTP is redirected before it reaches the app
      # (`HostSettings.apply`), so the warning is seen only where the address
      # is an http one or missing, and its last sentence is right for both.
      # The same fact raises `Admin::Ui::InsecureNoticeComponent`.
      #
      # "Reached over an encrypted connection" is what `request.ssl?` says,
      # and the app sees no connection but the proxy's: it is true when the
      # proxy in front said so (`X-Forwarded-Proto: https`) or when
      # `ASSUME_SSL=1` says it for every request. A proxy that claims HTTPS
      # for a plain connection, or `ASSUME_SSL=1` in front of none, makes
      # this row say OK about a connection that is not encrypted, and
      # nothing in the app can tell.
      def https
        return nil unless @production
        return nil if @request_ssl.nil?

        if @request_ssl
          ok("HTTPS", "This page was reached over an encrypted connection.")
        else
          warning("HTTPS", "This page was reached over plain HTTP. Passwords and sessions can be read on the way. " \
            "Set PUBLIC_HOST to an https address.")
        end
      end

      # Which theme draws the site (theming spec §1): the fact the boot line
      # says, for someone who does not read the log. The folder's NAME and
      # not its path, and of the fingerprint its first eight characters:
      # this page is shown to anyone who may view it, and where a server
      # keeps its files is nobody's business there.
      #
      # And whether the stylesheet is that theme's: the build stamps its
      # output with the fingerprint of the theme it was built for
      # (`ThemeCss.stamp!`), and a stamp that is another's, or none, means
      # the right templates are drawn with the wrong styles. No stamp has a
      # sentence of its own ("has not been built, or its last build
      # failed"): a fresh checkout and a failed build were built for no
      # other theme. For a stamp that is another's, two wordings, because
      # what a person does about it differs:
      # - in production the boot already refuses such a stylesheet
      #   (config/application.rb), so the warning is seen only where that
      #   check was passed over (a process started with
      #   SECRET_KEY_BASE_DUMMY), and the remedy is the image's build;
      # - everywhere else nothing refuses (a development server starts under
      #   anything), so this row is the one place that says it: THEME_PATH
      #   set or unset since the last build, a theme's file changed with no
      #   `theme_css:watch` running to build and stamp again, or, the usual
      #   cause, a test run: development and test share the built
      #   stylesheet, and the tests build the default theme's, also under a
      #   running watch (lib/theme_css.rb). So the sentence does not say
      #   that bin/dev keeps it built. It names the command, a fixed string.
      # It costs one small file read. A probe that raises or answers false
      # is a stylesheet built for another theme (`probe` answers false for
      # both), and its message is not shown; nil is no build at all.
      #
      # FIRST, a theme that was refused when it was last read (a development
      # reload: `Theme.prepare`). Such a theme has no path, since it brings
      # nothing, and without this branch the row said "The default theme
      # draws the site (THEME_PATH is not set)", OK, while a theme was set
      # and every public page raised. Neither the path nor the refusal's
      # words are shown: the refusal names the server's path.
      def theme
        if @theme.refusal
          return warning("Theme", "The theme folder was refused when it was last read, and the public site answers with the " \
            "reason until the folder is corrected. bin/rails theme:check says what is wrong with it.")
        end

        described = @theme.configured? ? "The theme “#{@theme.name}”" : "The default theme"
        with = @theme.configured? ? "with THEME_PATH set" : "without THEME_PATH"

        built = probe(@stylesheet_probe)
        if built
          if @theme.configured?
            ok("Theme", "#{described} draws the site (#{@theme.template_count} templates, fingerprint #{@theme.fingerprint[0, 8]}).")
          else
            ok("Theme", "#{described} draws the site (THEME_PATH is not set).")
          end
        elsif built.nil?
          # No stamp at all: nothing here "was built for another theme".
          missing = "#{described} is set, but the public stylesheet has not been built, or its last build failed, so the site " \
            "is drawn with an earlier build's styles or with none."
          if @production
            warning("Theme", "#{missing} Build the site's image again: assets:precompile #{with}.")
          else
            warning("Theme", "#{missing} Build it #{with}#{" as the server has it" if @theme.configured?}: run this command, " \
              "or start bin/dev again. If the build fails, it says why where it runs.", command: STYLESHEET_COMMAND)
          end
        elsif @production
          warning("Theme", "#{described} is set, but the stylesheet was built for another theme, so the site is drawn " \
            "with the wrong styles. Build the site's image again: assets:precompile #{with}.")
        else
          remedy = "run this command, or start bin/dev again."
          if @theme.configured?
            warning("Theme", "#{described} is set, but the stylesheet was built for another theme or for an earlier state of " \
              "this one, so the site is drawn with the wrong styles. A test run does that, also while bin/dev runs: it builds " \
              "the default theme's stylesheet into the same place. Build the theme's again #{with} as the server has it: #{remedy}",
              command: STYLESHEET_COMMAND)
          else
            warning("Theme", "#{described} is set, but the stylesheet was built for another theme, so the site is drawn with " \
              "the wrong styles. Build it again #{with}: #{remedy}", command: STYLESHEET_COMMAND)
          end
        end
      end

      def storage
        if probe(@storage_probe)
          ok("File storage", "Uploads can be stored and read back.")
        else
          warning("File storage", "Uploads can't be stored, so logos and images will fail. " \
            "Check that the storage directory (storage/ by default) is writable and on a persistent volume.")
        end
      end

      def image_processing
        if probe(@image_probe)
          ok("Image processing", "Images can be resized.")
        else
          warning("Image processing", "Images can't be resized, so image variants and logo resizing will fail. " \
            "Install libvips on the server.")
        end
      end

      def background_jobs
        if @queue_adapter != "solid_queue"
          ok("Background jobs", "Jobs run inside the web process (#{@queue_adapter} adapter).")
        elsif probe(@worker_alive_probe)
          ok("Background jobs", "A Solid Queue worker is running.")
        else
          warning("Background jobs", "No Solid Queue worker has checked in recently, so queued work " \
            "(upload analysis, emails) won't run. Set SOLID_QUEUE_IN_PUMA=1 or run bin/jobs.")
        end
      end

      # Outgoing mail's state in its own words (`MailStateSentence`, the
      # sentence the Settings card shows): Working is OK and the other three
      # warn, Last send failed included, since a real mail was lost. A
      # failure is said by its sentence and never the server's line: this
      # page is open to `system_status.view`, the line to `settings.manage`.
      # Production without a site address is "Not set up" and the sentence
      # says the address is what is missing (`MailSettings#complete?`).
      def mail
        settings = @mail_settings || MailSettings.current
        link = :mail_settings if @mail_settings_link
        message = MailStateSentence.for(settings)

        if settings.state == :working
          Result.new(label: "Mail", status: :ok, message:, link:)
        elsif settings.ready?
          # Last send failed: the reset link is there, so no command.
          Result.new(label: "Mail", status: :warning, message:, link:)
        else
          Result.new(label: "Mail", status: :warning, message: "#{message} #{MAIL_FALLBACK_MESSAGE}", command: MAIL_FALLBACK_COMMAND, link:)
        end
      end

      def probe(callable)
        callable.call
      rescue StandardError, LoadError
        false
      end

      def ok(label, message) = Result.new(label:, status: :ok, message:)
      def warning(label, message, command: nil) = Result.new(label:, status: :warning, message:, command:)
  end
end
