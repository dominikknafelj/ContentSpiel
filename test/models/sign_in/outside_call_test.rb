require "test_helper"

# The one request a sign-in check sends out: cut at its overall deadline
# even when every single read is quick.
class SignIn::OutsideCallTest < ActiveSupport::TestCase
  test "a server that drips its answer is cut at the deadline although no single read waits long" do
    server = TCPServer.new("127.0.0.1", 0)
    dripping = Thread.new do
      Thread.current.report_on_exception = false
      client = server.accept
      client.gets until client.gets == "\r\n"
      client.write("HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n")
      100.times do
        client.write("0")
        sleep 0.05
      end
    rescue IOError, SystemCallError
      nil
    end
    uri = URI("http://127.0.0.1:#{server.addr[1]}/range/ABCDE")

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_raises(Timeout::Error) do
      SignIn::OutsideCall.perform(uri, Net::HTTP::Get.new(uri), open_timeout: 1, read_timeout: 1, deadline: 0.5)
    end
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2, "cut at the deadline, not after the drip's five seconds"
  ensure
    dripping&.kill
    server&.close
  end

  test "the deadline is the sum of the timeouts unless one is named" do
    deadlines = []
    with_singleton_override(Timeout, :timeout, ->(seconds, *) { deadlines << seconds; raise Timeout::Error }) do
      uri = URI("http://127.0.0.1:1/")
      assert_raises(Timeout::Error) { SignIn::OutsideCall.perform(uri, Net::HTTP::Get.new(uri), open_timeout: 2, read_timeout: 3) }
    end
    assert_equal [ 5 ], deadlines
  end

  test "a body over max_body is refused with the reason too_large, whether declared or streamed" do
    with_http_stub(status: 200, body: "x" * 100) do |base, _|
      uri = URI("#{base}/")
      error = assert_raises(SignIn::OutsideCall::Unavailable) do
        SignIn::OutsideCall.perform(uri, Net::HTTP::Get.new(uri), open_timeout: 1, read_timeout: 1, max_body: 99)
      end
      assert_equal "too_large", error.reason
    end

    server = TCPServer.new("127.0.0.1", 0)
    sender = Thread.new do
      Thread.current.report_on_exception = false
      client = server.accept
      while (line = client.gets) && line != "\r\n"; end
      client.write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n")
      10.times { client.write("a\r\n#{"x" * 10}\r\n") }
      client.write("0\r\n\r\n")
      client.close
    rescue IOError, SystemCallError
      nil
    end
    uri = URI("http://127.0.0.1:#{server.addr[1]}/")
    error = assert_raises(SignIn::OutsideCall::Unavailable) do
      SignIn::OutsideCall.perform(uri, Net::HTTP::Get.new(uri), open_timeout: 1, read_timeout: 1, max_body: 50)
    end
    assert_equal "too_large", error.reason
  ensure
    sender&.kill
    server&.close
  end

  test "a body within max_body is the response's body, and without max_body the body is read whole" do
    with_http_stub(status: 200, body: "x" * 100) do |base, _|
      uri = URI("#{base}/")
      assert_equal "x" * 100, SignIn::OutsideCall.perform(uri, Net::HTTP::Get.new(uri), open_timeout: 1, read_timeout: 1, max_body: 100).body
      assert_equal "x" * 100, SignIn::OutsideCall.perform(uri, Net::HTTP::Get.new(uri), open_timeout: 1, read_timeout: 1).body
    end
  end

  test "Unavailable.status carries the status and its reason" do
    error = SignIn::OutsideCall::Unavailable.status("503")
    assert_equal [ 503, "http_503" ], [ error.status, error.reason ]
  end
end
