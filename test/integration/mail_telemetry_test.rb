require "test_helper"

# No secret reaches a span (CLAUDE.md, telemetry). A send is traced: the job's
# `process` span (a consumer root, `Telemetry::WorkSampler`) and Action
# Mailer's instrumentation, which records the delivery and the exception it
# raised. A server that echoes the login in its refusal (`:login_refused`
# echoes both the username and the password) would put it in that
# exception's message unless `ApplicationMailer::SmtpDelivery` raised the
# scrubbed copy. Every span's name, attributes, events (an exception's
# message and stack are an event's attributes) and status are read.
class MailTelemetryTest < ActionMailer::TestCase
  USERNAME = "span-login@example.test".freeze
  PASSWORD = "span-Pa55-w0rd".freeze
  SECRETS = [ USERNAME, PASSWORD, Base64.strict_encode64("\0#{USERNAME}\0#{PASSWORD}"),
              Base64.strict_encode64(USERNAME), Base64.strict_encode64(PASSWORD) ].freeze

  class ProbeMailer < ApplicationMailer
    def probe(to)
      mail(to: to, subject: "Probe") { |format| format.text { render plain: "Hello from the probe." } }
    end
  end

  setup do
    @exporter = Rails.application.config.x.otel_test_exporter
    @exporter.reset
  end

  def written(spans)
    spans.map do |span|
      [ span.name, span.attributes.to_a, span.status&.description,
        Array(span.events).map { |event| [ event.name, event.attributes.to_a ] } ].flatten.compact.join(" ")
    end.join("\n")
  end

  def refused_login
    SmtpStub.start(:login_refused) do |port|
      with_mail_state(:working, mail_server: SmtpStub::HOST, mail_port: port, mail_security: "starttls",
        mail_username: USERNAME, mail_password: PASSWORD) do
        SmtpStub.trusted { yield }
        assert_equal "login", SiteSetting.instance.reload.mail_failure["key"]
      end
    end
  end

  test "no span of a failed send by the job holds the username or the password" do
    refused_login { perform_enqueued_jobs { ApplicationMailer.queue(ProbeMailer, :probe, "bea@example.test") } }

    spans = @exporter.finished_spans
    text = written(spans)
    assert spans.any? { |span| span.kind == :consumer }, "the job's span is recorded: #{spans.map(&:name)}"
    assert_match(/535/, text, "the refusal reached a span, so the check below can fail")
    SECRETS.each { |secret| assert_not_includes text.downcase, secret.downcase }
  end

  test "no span of a failed test mail holds the username or the password" do
    tracer = OpenTelemetry.tracer_provider.tracer("mail-telemetry-test")
    refused_login do
      tracer.in_span("POST /settings/mail/test", kind: :server) do
        ApplicationMailer.deliver_now_and_record(ProbeMailer.probe("bea@example.test"))
      end
    end

    text = written(@exporter.finished_spans)
    assert_match(/535/, text, "the refusal reached a span, so the check below can fail")
    SECRETS.each { |secret| assert_not_includes text.downcase, secret.downcase }
  end
end
