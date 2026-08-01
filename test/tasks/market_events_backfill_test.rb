require "test_helper"
require "rake"

class MarketEventsBackfillTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("market_events:backfill_insights")
    @task = Rake::Task["market_events:backfill_insights"]
    @task.reenable
    stub_anthropic_key!
    stub_anthropic_new(text: "Backfilled prose.")
  end

  teardown do
    if Anthropic::Client.singleton_class.instance_methods(false).include?(:new)
      Anthropic::Client.singleton_class.remove_method(:new)
    end
  end

  def stub_anthropic_new(text:)
    fake = fake_anthropic_search_client(text: text)
    Anthropic::Client.define_singleton_method(:new) { |**_| fake }
  end

  test "fills published events missing a so_what, skipping drafts and already-filled events" do
    blank  = MarketEvent.create!(title: "Blank", event_date: Date.new(2025, 1, 1), kind: "market", status: "published")
    filled = MarketEvent.create!(title: "Filled", event_date: Date.new(2025, 1, 2), kind: "market",
                                 status: "published", so_what: "already here")
    draft  = MarketEvent.create!(title: "Draft", event_date: Date.new(2025, 1, 3), kind: "market", status: "draft")

    capture_io { @task.invoke }

    assert_equal "Backfilled prose.", blank.reload.so_what
    assert_equal "already here",      filled.reload.so_what
    assert_nil draft.reload.so_what
  end

  test "regenerates a so_what left cut mid-sentence by the old raw-character truncation" do
    cut = MarketEvent.create!(title: "Cut", event_date: Date.new(2025, 1, 4), kind: "market",
                              status: "published", so_what: "Frontier prices fell by a thi...")

    capture_io { @task.invoke }

    assert_equal "Backfilled prose.", cut.reload.so_what
  end
end
