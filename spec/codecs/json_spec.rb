require "logstash/devutils/rspec/spec_helper"
require "logstash/codecs/json"
require "logstash/event"
require "logstash/json"
require "insist"

describe LogStash::Codecs::JSONNginx do
  subject do
    next LogStash::Codecs::JSONNginx.new
  end

  context "#decode" do
    it "should return an event from json data" do
      data = {"foo" => "bar", "baz" => {"bah" => ["a","b","c"]}}
      subject.decode(LogStash::Json.dump(data)) do |event|
        insist { event.is_a? LogStash::Event }
        insist { event["foo"] } == data["foo"]
        insist { event["baz"] } == data["baz"]
        insist { event["bah"] } == data["bah"]
      end
    end

    it "should parse escape characters from Nginx configuration files" do
      data = %q[{"foo": "\x22aaa\x0a\x0Abbb\x22"}]
      subject.decode(data) do |event|
        insist { event.is_a? LogStash::Event }
        insist { event["foo"] } == %["aaa\n\nbbb"]
      end
    end

    it "should be fast", :performance => true do
      json = '{"message":"Hello world!","@timestamp":"2013-12-21T07:01:25.616Z","@version":"1","host":"Macintosh.local","sequence":1572456}'
      iterations = 500000
      count = 0

      # Warmup
      10000.times { subject.decode(json) { } }

      start = Time.now
      iterations.times do
        subject.decode(json) do |event|
          count += 1
        end
      end
      duration = Time.now - start
      insist { count } == iterations
      puts "codecs/json rate: #{"%02.0f/sec" % (iterations / duration)}, elapsed: #{duration}s"
    end

    context "processing plain text" do
      it "falls back to plain text" do
        decoded = false
        subject.decode("something that isn't json") do |event|
          decoded = true
          insist { event.is_a?(LogStash::Event) }
          insist { event["message"] } == "something that isn't json"
          insist { event["tags"] }.include?("_jsonparsefailure")
        end
        insist { decoded } == true
      end
    end

    context "processing weird binary blobs" do
      it "falls back to plain text and doesn't crash (LOGSTASH-1595)" do
        decoded = false
        blob = (128..255).to_a.pack("C*").force_encoding("ASCII-8BIT")
        subject.decode(blob) do |event|
          decoded = true
          insist { event.is_a?(LogStash::Event) }
          insist { event["message"].encoding.to_s } == "UTF-8"
        end
        insist { decoded } == true
      end
    end

    context "when json could not be parsed" do

      let(:message)    { "random_message" }

      it "add the failure tag" do
        subject.decode(message) do |event|
          expect(event).to include "tags"
        end
      end

      it "uses an array to store the tags" do
        subject.decode(message) do |event|
          expect(event['tags']).to be_a Array
        end
      end

      it "add a json parser failure tag" do
        subject.decode(message) do |event|
          expect(event['tags']).to include "_jsonparsefailure"
        end
      end
    end
  end

  context "#encode" do
    it "should return json data" do
      data = {"foo" => "bar", "baz" => {"bah" => ["a","b","c"]}}
      event = LogStash::Event.new(data)
      got_event = false
      subject.on_event do |e, d|
        insist { d.chomp } == LogStash::Event.new(data).to_json
        insist { LogStash::Json.load(d)["foo"] } == data["foo"]
        insist { LogStash::Json.load(d)["baz"] } == data["baz"]
        insist { LogStash::Json.load(d)["bah"] } == data["bah"]
        got_event = true
      end
      subject.encode(event)
      insist { got_event }
    end
  end
end
