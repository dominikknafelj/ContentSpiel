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
end
