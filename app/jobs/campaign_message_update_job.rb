class CampaignMessageUpdateJob < ApplicationJob
  queue_as :low

  def perform(campaign_id, audience_id, status)
    campaign = Campaign.find(campaign_id)
    new_audience = campaign.audience.map do |a|
      if a['audience_id'] == audience_id && (!a['status'] || a['status'] == :failed || (statuses(status) > statuses(a['status'])))
        a['status'] = status
      end
      a
    end
    # rubocop:disable Rails/SkipsModelValidations
    campaign.update_column(:audience, new_audience)
    # rubocop:enable Rails/SkipsModelValidations
  end

  private

  def statuses(status)
    [:scheduled, :progress, :sent, :delivered, :read, :failed].find_index(status.to_sym)
  end
end
