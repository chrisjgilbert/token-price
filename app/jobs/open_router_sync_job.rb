# Pulls the OpenRouter model catalogue and prices every 6 hours (see
# config/recurring.yml). All the work lives in OpenRouter::ModelSync; this is
# just the schedulable Active Job wrapper.
class OpenRouterSyncJob < ApplicationJob
  queue_as :default

  def perform
    result = OpenRouter::ModelSync.call
    payload = OpenRouter::SyncDigest.new(result).to_slack_payload
    SlackNotifier.post(payload) if payload
  end
end
